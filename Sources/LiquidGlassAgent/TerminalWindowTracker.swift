#if os(macOS)
import AppKit
import CoreGraphics
import LiquidGlassCore

@MainActor
final class TerminalWindowTracker {
    typealias UpdateHandler = @MainActor ([TrackedTerminalWindow]) -> Void

    private var timer: Timer?
    private var updateHandler: UpdateHandler?
    private var interval: TimeInterval = 1.0 / 60.0
    private let logger: any LiquidGlassLogging

    init(logger: any LiquidGlassLogging = StandardLogger(category: "window-tracker")) {
        self.logger = logger
    }

    func start(intervalMilliseconds: Int, updateHandler: @escaping UpdateHandler) {
        self.updateHandler = updateHandler
        let newInterval = max(Double(intervalMilliseconds) / 1_000.0, 0.008)
        if timer != nil, abs(newInterval - interval) < 0.000_1 {
            publishCurrentWindows()
            return
        }

        stopTimerOnly()
        interval = newInterval
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishCurrentWindows() }
        }
        newTimer.tolerance = min(interval * 0.15, 0.003)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        publishCurrentWindows()
        logger.log(.info, "Tracking Terminal windows at approximately \(Int(1 / interval)) Hz.")
    }

    func stop() {
        stopTimerOnly()
        updateHandler = nil
    }

    func currentWindows() -> [TrackedTerminalWindow] {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            CGWindowID(kCGNullWindowID)
        ) as? [[String: Any]] else {
            return []
        }

        let terminalPIDs = Set(
            NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.Terminal")
                .map(\.processIdentifier)
        )
        guard !terminalPIDs.isEmpty else { return [] }

        let mainScreenTop = NSScreen.main?.frame.maxY
            ?? NSScreen.screens.first?.frame.maxY
            ?? 0
        var windows: [TrackedTerminalWindow] = []
        windows.reserveCapacity(6)

        for item in rawList {
            guard let pidNumber = item[kCGWindowOwnerPID as String] as? NSNumber,
                  terminalPIDs.contains(pidNumber.int32Value),
                  let windowNumber = item[kCGWindowNumber as String] as? NSNumber,
                  let layerNumber = item[kCGWindowLayer as String] as? NSNumber,
                  layerNumber.intValue == 0,
                  let boundsDictionary = item[kCGWindowBounds as String] as? CFDictionary,
                  let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary),
                  quartzFrame.width >= 120,
                  quartzFrame.height >= 80 else {
                continue
            }

            let alpha = (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.001 else { continue }

            let appKitFrame = CGRect(
                x: quartzFrame.minX,
                y: mainScreenTop - quartzFrame.maxY,
                width: quartzFrame.width,
                height: quartzFrame.height
            )
            let isOnScreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false

            windows.append(
                TrackedTerminalWindow(
                    identifier: CGWindowID(windowNumber.uint32Value),
                    processIdentifier: pidNumber.int32Value,
                    quartzFrame: quartzFrame,
                    appKitFrame: appKitFrame,
                    alpha: alpha,
                    isOnScreen: isOnScreen
                )
            )
        }

        return windows
            .filter(\.isOnScreen)
            .sorted { lhs, rhs in lhs.identifier < rhs.identifier }
    }

    private func publishCurrentWindows() {
        updateHandler?(currentWindows())
    }

    private func stopTimerOnly() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
