import Foundation

public enum TerminalWindowTrackingMode: String, Codable, Equatable, Sendable {
    case coreGraphicsMetadataPolling = "core-graphics-metadata-polling"
}

public struct AgentRuntimeStatus: Codable, Equatable, Sendable {
    public var processIdentifier: Int32
    public var startedAt: Date
    public var heartbeatAt: Date
    public var enabled: Bool
    public var windowTrackingMode: TerminalWindowTrackingMode
    public var terminalWindowCount: Int
    public var overlayCount: Int
    public var activeDisplayCaptureCount: Int
    public var screenCaptureAuthorized: Bool
    public var metalDeviceName: String?
    public var capturedFrameCount: UInt64
    public var droppedFrameCount: UInt64
    public var lastError: String?

    public init(
        processIdentifier: Int32,
        startedAt: Date,
        heartbeatAt: Date,
        enabled: Bool,
        windowTrackingMode: TerminalWindowTrackingMode,
        terminalWindowCount: Int,
        overlayCount: Int,
        activeDisplayCaptureCount: Int,
        screenCaptureAuthorized: Bool,
        metalDeviceName: String?,
        capturedFrameCount: UInt64,
        droppedFrameCount: UInt64,
        lastError: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.startedAt = startedAt
        self.heartbeatAt = heartbeatAt
        self.enabled = enabled
        self.windowTrackingMode = windowTrackingMode
        self.terminalWindowCount = terminalWindowCount
        self.overlayCount = overlayCount
        self.activeDisplayCaptureCount = activeDisplayCaptureCount
        self.screenCaptureAuthorized = screenCaptureAuthorized
        self.metalDeviceName = metalDeviceName
        self.capturedFrameCount = capturedFrameCount
        self.droppedFrameCount = droppedFrameCount
        self.lastError = lastError
    }
}
