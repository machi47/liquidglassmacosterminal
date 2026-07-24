import Foundation

public protocol TerminalPreferencesManaging: Sendable {
    func capturePreferenceBackup(configuration: LiquidGlassConfiguration) async throws -> TerminalPreferenceBackup
    func installManagedProfile(
        configuration: LiquidGlassConfiguration,
        backup: TerminalPreferenceBackup
    ) async throws
    func updateManagedProfile(configuration: LiquidGlassConfiguration) async throws
    func restorePreferences(from backup: TerminalPreferenceBackup, managedProfileName: String) async throws
    func managedProfileExists(named name: String) async throws -> Bool
}

public protocol TerminalAutomating: Sendable {
    func isRunning() async -> Bool
    func captureTabProfiles() async throws -> [TerminalTabSnapshot]
    func applyProfile(named profileName: String) async throws
    func restoreTabProfiles(
        _ snapshots: [TerminalTabSnapshot],
        managedProfileName: String,
        fallbackProfileName: String
    ) async throws
    func restoreDefaultProfiles(
        defaultProfileName: String?,
        startupProfileName: String?,
        fallbackProfileName: String
    ) async throws
    func profileIsVisible(named profileName: String) async throws -> Bool
    func importManagedProfileIfNeeded(named profileName: String) async throws
    func requestAutomationConsent() async throws
}

public protocol AgentSignaling: Sendable {
    func signalConfigurationChanged() async throws
    func requestScreenCapturePermission() async throws
    func isAgentLoaded() async -> Bool
}

public struct LiquidGlassStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var transition: TransitionState?
    public var agentLoaded: Bool
    public var terminalRunning: Bool
    public var managedProfileInstalled: Bool
    public var configuration: LiquidGlassConfiguration
    public var enabledAt: Date?
    public var lastError: String?

    public init(
        enabled: Bool,
        transition: TransitionState?,
        agentLoaded: Bool,
        terminalRunning: Bool,
        managedProfileInstalled: Bool,
        configuration: LiquidGlassConfiguration,
        enabledAt: Date?,
        lastError: String?
    ) {
        self.enabled = enabled
        self.transition = transition
        self.agentLoaded = agentLoaded
        self.terminalRunning = terminalRunning
        self.managedProfileInstalled = managedProfileInstalled
        self.configuration = configuration
        self.enabledAt = enabledAt
        self.lastError = lastError
    }
}

public enum DoctorSeverity: String, Codable, Sendable {
    case pass
    case warning
    case failure
}

public struct DoctorCheck: Codable, Equatable, Sendable {
    public var name: String
    public var severity: DoctorSeverity
    public var message: String

    public init(name: String, severity: DoctorSeverity, message: String) {
        self.name = name
        self.severity = severity
        self.message = message
    }
}
