import Foundation
#if os(macOS)
import AppKit
import Darwin
#elseif os(Linux)
import Glibc
#endif

public actor SystemAgentSignal: AgentSignaling {
    private let runner: any ProcessRunning
    private let logger: any LiquidGlassLogging

    public init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        logger: any LiquidGlassLogging = StandardLogger(category: "agent-signal")
    ) {
        self.runner = runner
        self.logger = logger
    }

    public func signalConfigurationChanged() async throws {
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(LiquidGlassVersion.notificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        logger.log(.debug, "Posted agent configuration notification.")
        #else
        throw LiquidGlassError.unsupportedPlatform
        #endif
    }

    public func requestScreenCapturePermission() async throws {
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(LiquidGlassVersion.permissionNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        logger.log(.debug, "Posted screen-capture permission request to the agent.")
        #else
        throw LiquidGlassError.unsupportedPlatform
        #endif
    }

    public func isAgentLoaded() async -> Bool {
        #if os(macOS)
        let uid = getuid()
        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["print", "gui/\(uid)/\(LiquidGlassVersion.agentLabel)"]
            )
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}
