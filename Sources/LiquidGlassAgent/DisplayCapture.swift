#if os(macOS)
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Metal
import MetalPerformanceShaders
import ScreenCaptureKit
import LiquidGlassCore

final class DisplayCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let display: SCDisplay
    let framePool: DisplayFramePool

    private let context: MetalContext
    private let configuration: LiquidGlassConfiguration
    private let sampleQueue: DispatchQueue
    private let blur: MPSImageGaussianBlur
    private var textureCache: CVMetalTextureCache?
    private var stream: SCStream?
    private let logger: any LiquidGlassLogging

    init(
        display: SCDisplay,
        excludedApplications: [SCRunningApplication],
        context: MetalContext,
        configuration: LiquidGlassConfiguration,
        logger: any LiquidGlassLogging = StandardLogger(category: "display-capture")
    ) throws {
        self.display = display
        self.context = context
        self.configuration = configuration
        self.logger = logger
        self.sampleQueue = DispatchQueue(
            label: "com.machi47.liquidglass.capture.\(display.displayID)",
            qos: .userInteractive
        )
        self.blur = MPSImageGaussianBlur(
            device: context.device,
            sigma: Float(configuration.blurSigma)
        )

        let quartzBounds = CGDisplayBounds(display.displayID)
        let width = max(1, Int((Double(display.width) * configuration.renderScale).rounded()))
        let height = max(1, Int((Double(display.height) * configuration.renderScale).rounded()))
        self.framePool = try DisplayFramePool(
            device: context.device,
            displayID: display.displayID,
            quartzBounds: quartzBounds,
            textureWidth: width,
            textureHeight: height
        )
        super.init()

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            context.device,
            nil,
            &cache
        )
        guard status == kCVReturnSuccess, let cache else {
            throw LiquidGlassError.agent("Unable to create a Core Video Metal texture cache (\(status)).")
        }
        textureCache = cache

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = width
        streamConfiguration.height = height
        streamConfiguration.scalesToFit = true
        streamConfiguration.preservesAspectRatio = true
        streamConfiguration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(configuration.captureFramesPerSecond)
        )
        streamConfiguration.queueDepth = 5
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = false
        streamConfiguration.capturesAudio = false

        stream = SCStream(
            filter: filter,
            configuration: streamConfiguration,
            delegate: self
        )
    }

    func start() async throws {
        guard let stream else { throw LiquidGlassError.agent("Capture stream was not initialized.") }
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        logger.log(
            .info,
            "Started display \(display.displayID) capture at \(framePool.textureWidth)x\(framePool.textureHeight), \(configuration.captureFramesPerSecond) FPS."
        )
    }

    func stop() async {
        guard let stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            logger.log(.warning, "Stopping display \(display.displayID) capture failed: \(error.localizedDescription)")
        }
        try? stream.removeStreamOutput(self, type: .screen)
        self.stream = nil
        if let textureCache {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let textureCache,
              let slotIndex = framePool.beginCapture() else {
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            sourceWidth,
            sourceHeight,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture,
              let sourceTexture = CVMetalTextureGetTexture(cvTexture),
              let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            framePool.publish(index: slotIndex, succeeded: false)
            return
        }

        commandBuffer.label = "LiquidGlass preprocess display \(display.displayID)"
        let destination = framePool.textures(for: slotIndex)

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            framePool.publish(index: slotIndex, succeeded: false)
            return
        }
        let copyWidth = min(sourceTexture.width, destination.sharp.width)
        let copyHeight = min(sourceTexture.height, destination.sharp.height)
        blit.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: copyWidth, height: copyHeight, depth: 1),
            to: destination.sharp,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()

        blur.encode(
            commandBuffer: commandBuffer,
            sourceTexture: destination.sharp,
            destinationTexture: destination.blurred
        )

        commandBuffer.addCompletedHandler { [framePool, cvTexture] completed in
            _ = cvTexture
            framePool.publish(index: slotIndex, succeeded: completed.status == .completed)
        }
        commandBuffer.commit()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.log(.error, "Display \(display.displayID) capture stopped: \(error.localizedDescription)")
    }
}
#endif
