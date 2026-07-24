#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import LiquidGlassCore

@MainActor
final class CaptureCoordinator {
    private struct CaptureSignature: Equatable {
        let renderScale: Double
        let captureFPS: Int
        let blurSigma: Double
    }

    private let context: MetalContext
    private let logger: any LiquidGlassLogging
    private var captures: [CGDirectDisplayID: DisplayCapture] = [:]
    private var desiredDisplayIDs: Set<CGDirectDisplayID> = []
    private var signature: CaptureSignature?
    private var reconciliationTask: Task<Void, Never>?
    private(set) var lastError: String?

    init(
        context: MetalContext,
        logger: any LiquidGlassLogging = StandardLogger(category: "capture-coordinator")
    ) {
        self.context = context
        self.logger = logger
    }

    var activeCaptureCount: Int { captures.count }
    var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }
    var metalDeviceName: String { context.device.name }

    func framePool(for displayID: CGDirectDisplayID) -> DisplayFramePool? {
        captures[displayID]?.framePool
    }

    func reconcile(
        windows: [TrackedTerminalWindow],
        configuration: LiquidGlassConfiguration,
        completion: @escaping @MainActor () -> Void
    ) {
        let desired = displayIDsIntersecting(windows: windows)
        let newSignature = CaptureSignature(
            renderScale: configuration.renderScale,
            captureFPS: configuration.captureFramesPerSecond,
            blurSigma: configuration.blurSigma
        )
        guard desired != desiredDisplayIDs || newSignature != signature else { return }

        desiredDisplayIDs = desired
        signature = newSignature
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.rebuildCaptures(
                    displayIDs: desired,
                    configuration: configuration
                )
                guard !Task.isCancelled else { return }
                self.lastError = nil
                completion()
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
                self.logger.log(.error, error.localizedDescription)
                completion()
            }
        }
    }

    func requestPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    func stop() {
        reconciliationTask?.cancel()
        reconciliationTask = nil
        let old = captures.values
        captures.removeAll()
        desiredDisplayIDs.removeAll()
        signature = nil
        Task {
            for capture in old { await capture.stop() }
        }
    }

    func statistics() -> (captured: UInt64, dropped: UInt64) {
        captures.values.reduce(into: (captured: UInt64(0), dropped: UInt64(0))) { result, capture in
            let statistics = capture.framePool.statistics()
            result.captured &+= statistics.captured
            result.dropped &+= statistics.dropped
        }
    }

    func displaySegments(
        for window: TrackedTerminalWindow
    ) -> [(displayID: CGDirectDisplayID, quartzBounds: CGRect, intersection: CGRect)] {
        activeDisplayBounds().compactMap { displayID, bounds in
            let intersection = window.quartzFrame.intersection(bounds)
            guard !intersection.isNull, intersection.width >= 1, intersection.height >= 1 else {
                return nil
            }
            return (displayID, bounds, intersection)
        }
    }

    private func rebuildCaptures(
        displayIDs: Set<CGDirectDisplayID>,
        configuration: LiquidGlassConfiguration
    ) async throws {
        let oldCaptures = captures.values
        captures.removeAll()
        for capture in oldCaptures { await capture.stop() }
        guard !displayIDs.isEmpty else { return }

        guard requestPermission(), CGPreflightScreenCaptureAccess() else {
            throw LiquidGlassError.agent(
                "Screen Recording permission is required for LiquidGlass.app. Approve the macOS prompt, then run `liquidglass on` again."
            )
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let excludedBundleIDs: Set<String> = [
            "com.apple.Terminal",
            "com.machi47.LiquidGlassAgent",
            "com.machi47.LiquidGlassCLI",
            Bundle.main.bundleIdentifier
        ].compactMap { $0 }.reduce(into: Set<String>()) { $0.insert($1) }
        let excludedApplications = content.applications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return excludedBundleIDs.contains(bundleIdentifier)
        }

        let displaysByID = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
        var created: [CGDirectDisplayID: DisplayCapture] = [:]
        do {
            for displayID in displayIDs.sorted() {
                guard let display = displaysByID[displayID] else { continue }
                let capture = try DisplayCapture(
                    display: display,
                    excludedApplications: excludedApplications,
                    context: context,
                    configuration: configuration
                )
                try await capture.start()
                created[displayID] = capture
            }
        } catch {
            for capture in created.values { await capture.stop() }
            throw error
        }
        captures = created
    }

    private func displayIDsIntersecting(
        windows: [TrackedTerminalWindow]
    ) -> Set<CGDirectDisplayID> {
        let bounds = activeDisplayBounds()
        var result: Set<CGDirectDisplayID> = []
        for window in windows {
            for (displayID, displayBounds) in bounds {
                if window.quartzFrame.intersects(displayBounds) {
                    result.insert(displayID)
                }
            }
        }
        return result
    }

    private func activeDisplayBounds() -> [(CGDirectDisplayID, CGRect)] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return []
        }
        var identifiers = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &identifiers, &displayCount) == .success else {
            return []
        }
        return identifiers.prefix(Int(displayCount)).map { ($0, CGDisplayBounds($0)) }
    }
}
#endif
