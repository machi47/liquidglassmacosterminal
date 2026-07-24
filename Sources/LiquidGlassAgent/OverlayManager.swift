#if os(macOS)
import AppKit
import CoreGraphics
import LiquidGlassCore

@MainActor
final class OverlayManager {
    private let context: MetalContext
    private let logger: any LiquidGlassLogging
    private var panels: [DisplaySegmentKey: GlassPanel] = [:]
    private var lastWindows: [TrackedTerminalWindow] = []
    private var lastConfiguration = LiquidGlassConfiguration.default

    init(
        context: MetalContext,
        logger: any LiquidGlassLogging = StandardLogger(category: "overlay-manager")
    ) {
        self.context = context
        self.logger = logger
    }

    var overlayCount: Int { panels.count }

    func synchronize(
        windows: [TrackedTerminalWindow],
        configuration: LiquidGlassConfiguration,
        captureCoordinator: CaptureCoordinator
    ) {
        lastWindows = windows
        lastConfiguration = configuration
        var liveKeys: Set<DisplaySegmentKey> = []

        for window in windows {
            for segmentInfo in captureCoordinator.displaySegments(for: window) {
                guard let framePool = captureCoordinator.framePool(for: segmentInfo.displayID) else {
                    continue
                }
                let key = DisplaySegmentKey(
                    windowID: window.identifier,
                    displayID: segmentInfo.displayID
                )
                liveKeys.insert(key)

                let appKitFrame = appKitFrame(fromQuartzFrame: segmentInfo.intersection)
                let segment = GlassSegmentDescriptor(
                    windowID: window.identifier,
                    windowQuartzFrame: window.quartzFrame,
                    displayQuartzBounds: segmentInfo.quartzBounds,
                    segmentQuartzFrame: segmentInfo.intersection
                )
                let panel: GlassPanel
                if let existing = panels[key] {
                    panel = existing
                } else {
                    panel = GlassPanel(
                        key: key,
                        context: context,
                        targetWindowID: window.identifier,
                        frame: appKitFrame
                    )
                    panels[key] = panel
                    logger.log(
                        .debug,
                        "Created Metal segment for window \(window.identifier), display \(segmentInfo.displayID)."
                    )
                }
                panel.update(
                    targetWindowID: window.identifier,
                    frame: appKitFrame,
                    configuration: configuration,
                    segment: segment,
                    framePool: framePool
                )
            }
        }

        let stale = Set(panels.keys).subtracting(liveKeys)
        for key in stale {
            panels.removeValue(forKey: key)?.close()
        }
    }

    func refresh(captureCoordinator: CaptureCoordinator) {
        synchronize(
            windows: lastWindows,
            configuration: lastConfiguration,
            captureCoordinator: captureCoordinator
        )
    }

    func stop() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
        lastWindows = []
    }

    private func appKitFrame(fromQuartzFrame frame: CGRect) -> CGRect {
        let mainScreenTop = NSScreen.main?.frame.maxY
            ?? NSScreen.screens.first?.frame.maxY
            ?? 0
        return CGRect(
            x: frame.minX,
            y: mainScreenTop - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
#endif
