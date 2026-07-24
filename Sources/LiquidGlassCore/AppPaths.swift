import Foundation

public struct AppPaths: Sendable, Equatable {
    public let homeDirectory: URL
    public let applicationSupportDirectory: URL
    public let configurationFile: URL
    public let stateFile: URL
    public let operationLockFile: URL
    public let profileExportFile: URL
    public let agentRuntimeFile: URL
    public let logDirectory: URL
    public let agentLogFile: URL
    public let agentErrorLogFile: URL
    public let agentApplication: URL
    public let launchAgentFile: URL

    public init(homeDirectory: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let fileManager = FileManager.default
        let resolvedHome: URL

        if let override = environment["LIQUIDGLASS_HOME"], !override.isEmpty {
            resolvedHome = URL(fileURLWithPath: override, isDirectory: true)
        } else if let homeDirectory {
            resolvedHome = homeDirectory
        } else {
            resolvedHome = fileManager.homeDirectoryForCurrentUser
        }

        self.homeDirectory = resolvedHome
        self.applicationSupportDirectory = resolvedHome
            .appendingPathComponent("Library/Application Support/LiquidGlass", isDirectory: true)
        self.configurationFile = applicationSupportDirectory.appendingPathComponent("config.json")
        self.stateFile = applicationSupportDirectory.appendingPathComponent("state.json")
        self.operationLockFile = applicationSupportDirectory.appendingPathComponent("operation.lock")
        self.profileExportFile = applicationSupportDirectory.appendingPathComponent("LiquidGlass Managed.terminal")
        self.agentRuntimeFile = applicationSupportDirectory.appendingPathComponent("agent-runtime.json")
        self.logDirectory = applicationSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
        self.agentLogFile = logDirectory.appendingPathComponent("agent.log")
        self.agentErrorLogFile = logDirectory.appendingPathComponent("agent-error.log")
        self.agentApplication = applicationSupportDirectory.appendingPathComponent("LiquidGlass.app", isDirectory: true)
        self.launchAgentFile = resolvedHome
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(LiquidGlassVersion.agentLabel).plist")
    }

    public func createRequiredDirectories(fileManager: FileManager = .default) throws {
        do {
            try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: launchAgentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw LiquidGlassError.fileSystem("Unable to create LiquidGlass directories: \(error.localizedDescription)")
        }
    }
}
