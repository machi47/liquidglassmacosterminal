#if os(macOS)
import AppKit
import CoreGraphics

struct TrackedTerminalWindow: Equatable, Sendable {
    let identifier: CGWindowID
    let processIdentifier: pid_t
    let quartzFrame: CGRect
    let appKitFrame: CGRect
    let alpha: Double
    let isOnScreen: Bool
}

struct DisplaySegmentKey: Hashable, Sendable {
    let windowID: CGWindowID
    let displayID: CGDirectDisplayID
}
#endif
