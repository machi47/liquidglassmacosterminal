#if os(macOS)
import CoreGraphics
import Foundation
import Metal

final class DisplayFramePool: @unchecked Sendable {
    final class Slot {
        let sharpTexture: MTLTexture
        let blurredTexture: MTLTexture
        var captureInFlight = false
        var leaseCount = 0
        var generation: UInt64 = 0

        init(sharpTexture: MTLTexture, blurredTexture: MTLTexture) {
            self.sharpTexture = sharpTexture
            self.blurredTexture = blurredTexture
        }
    }

    final class FrameLease: @unchecked Sendable {
        let sharpTexture: MTLTexture
        let blurredTexture: MTLTexture
        let quartzBounds: CGRect
        let generation: UInt64

        private let releaseClosure: () -> Void
        private let lock = NSLock()
        private var released = false

        init(
            sharpTexture: MTLTexture,
            blurredTexture: MTLTexture,
            quartzBounds: CGRect,
            generation: UInt64,
            release: @escaping () -> Void
        ) {
            self.sharpTexture = sharpTexture
            self.blurredTexture = blurredTexture
            self.quartzBounds = quartzBounds
            self.generation = generation
            self.releaseClosure = release
        }

        func release() {
            lock.lock()
            guard !released else {
                lock.unlock()
                return
            }
            released = true
            lock.unlock()
            releaseClosure()
        }

        deinit { release() }
    }

    struct Statistics: Sendable {
        let captured: UInt64
        let dropped: UInt64
    }

    let displayID: CGDirectDisplayID
    let quartzBounds: CGRect
    let textureWidth: Int
    let textureHeight: Int

    private let lock = NSLock()
    private let slots: [Slot]
    private var currentIndex: Int?
    private var nextGeneration: UInt64 = 1
    private var capturedFrameCount: UInt64 = 0
    private var droppedFrameCount: UInt64 = 0

    init(
        device: MTLDevice,
        displayID: CGDirectDisplayID,
        quartzBounds: CGRect,
        textureWidth: Int,
        textureHeight: Int,
        slotCount: Int = 3
    ) throws {
        self.displayID = displayID
        self.quartzBounds = quartzBounds
        self.textureWidth = textureWidth
        self.textureHeight = textureHeight

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]

        var created: [Slot] = []
        created.reserveCapacity(slotCount)
        for index in 0..<slotCount {
            guard let sharp = device.makeTexture(descriptor: descriptor),
                  let blurred = device.makeTexture(descriptor: descriptor) else {
                throw NSError(
                    domain: "LiquidGlass.DisplayFramePool",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to allocate GPU texture slot \(index)."]
                )
            }
            sharp.label = "LiquidGlass display \(displayID) sharp \(index)"
            blurred.label = "LiquidGlass display \(displayID) blurred \(index)"
            created.append(Slot(sharpTexture: sharp, blurredTexture: blurred))
        }
        slots = created
    }

    func beginCapture() -> Int? {
        lock.lock()
        defer { lock.unlock() }

        for (index, slot) in slots.enumerated() {
            guard index != currentIndex,
                  !slot.captureInFlight,
                  slot.leaseCount == 0 else {
                continue
            }
            slot.captureInFlight = true
            return index
        }
        droppedFrameCount &+= 1
        return nil
    }

    func textures(for index: Int) -> (sharp: MTLTexture, blurred: MTLTexture) {
        let slot = slots[index]
        return (slot.sharpTexture, slot.blurredTexture)
    }

    func publish(index: Int, succeeded: Bool) {
        lock.lock()
        let slot = slots[index]
        slot.captureInFlight = false
        if succeeded {
            slot.generation = nextGeneration
            nextGeneration &+= 1
            currentIndex = index
            capturedFrameCount &+= 1
        } else {
            droppedFrameCount &+= 1
        }
        lock.unlock()
    }

    func leaseCurrent() -> FrameLease? {
        lock.lock()
        guard let index = currentIndex else {
            lock.unlock()
            return nil
        }
        let slot = slots[index]
        slot.leaseCount += 1
        let generation = slot.generation
        lock.unlock()

        return FrameLease(
            sharpTexture: slot.sharpTexture,
            blurredTexture: slot.blurredTexture,
            quartzBounds: quartzBounds,
            generation: generation
        ) { [weak self, weak slot] in
            guard let self, let slot else { return }
            self.lock.lock()
            slot.leaseCount = max(0, slot.leaseCount - 1)
            self.lock.unlock()
        }
    }

    func statistics() -> Statistics {
        lock.lock()
        let result = Statistics(captured: capturedFrameCount, dropped: droppedFrameCount)
        lock.unlock()
        return result
    }
}
#endif
