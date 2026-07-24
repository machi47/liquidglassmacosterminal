import Foundation

public enum TransitionState: String, Codable, Sendable {
    case enabling
    case disabling
}

public struct TerminalTabSnapshot: Codable, Equatable, Sendable {
    public var windowIndex: Int
    public var tabIndex: Int
    public var tty: String?
    public var profileName: String

    public init(windowIndex: Int, tabIndex: Int, tty: String?, profileName: String) {
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.tty = tty
        self.profileName = profileName
    }
}

public struct TerminalPreferenceBackup: Codable, Equatable, Sendable {
    public var previousDefaultProfileName: String?
    public var previousStartupProfileName: String?
    public var sourceProfileName: String
    public var previousManagedProfilePropertyList: Data?

    public init(
        previousDefaultProfileName: String?,
        previousStartupProfileName: String?,
        sourceProfileName: String,
        previousManagedProfilePropertyList: Data?
    ) {
        self.previousDefaultProfileName = previousDefaultProfileName
        self.previousStartupProfileName = previousStartupProfileName
        self.sourceProfileName = sourceProfileName
        self.previousManagedProfilePropertyList = previousManagedProfilePropertyList
    }
}

public struct LiquidGlassState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var enabled: Bool
    public var transition: TransitionState?
    public var preferenceBackup: TerminalPreferenceBackup?
    public var tabSnapshots: [TerminalTabSnapshot]
    public var enabledAt: Date?
    public var changedAt: Date?
    public var lastError: String?

    public init(
        schemaVersion: Int = LiquidGlassVersion.schemaVersion,
        enabled: Bool = false,
        transition: TransitionState? = nil,
        preferenceBackup: TerminalPreferenceBackup? = nil,
        tabSnapshots: [TerminalTabSnapshot] = [],
        enabledAt: Date? = nil,
        changedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.enabled = enabled
        self.transition = transition
        self.preferenceBackup = preferenceBackup
        self.tabSnapshots = tabSnapshots
        self.enabledAt = enabledAt
        self.changedAt = changedAt
        self.lastError = lastError
    }

    public static let disabled = LiquidGlassState()
}
