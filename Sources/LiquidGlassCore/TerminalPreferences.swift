import Foundation

#if os(macOS)
import AppKit
import CoreFoundation

public actor SystemTerminalPreferences: TerminalPreferencesManaging {
    private let paths: AppPaths
    private let logger: any LiquidGlassLogging
    private let applicationID = "com.apple.Terminal" as CFString

    public init(paths: AppPaths, logger: any LiquidGlassLogging = StandardLogger(category: "preferences")) {
        self.paths = paths
        self.logger = logger
    }

    public func capturePreferenceBackup(
        configuration: LiquidGlassConfiguration
    ) async throws -> TerminalPreferenceBackup {
        _ = try configuration.validated()
        let windowSettings = try readWindowSettings()
        let previousDefault = stringPreference(for: "Default Window Settings")
        let previousStartup = stringPreference(for: "Startup Window Settings")
        let sourceName = resolveSourceProfileName(
            preferred: previousDefault,
            windowSettings: windowSettings,
            excluding: configuration.managedProfileName
        )
        guard windowSettings[sourceName] is [String: Any] else {
            throw LiquidGlassError.terminalPreferences(
                "Terminal profile '\(sourceName)' could not be read. Open Terminal Settings > Profiles once, then retry."
            )
        }

        let previousManagedData: Data?
        if let previousManaged = windowSettings[configuration.managedProfileName] {
            previousManagedData = try encodePropertyList(previousManaged)
        } else {
            previousManagedData = nil
        }

        return TerminalPreferenceBackup(
            previousDefaultProfileName: previousDefault,
            previousStartupProfileName: previousStartup,
            sourceProfileName: sourceName,
            previousManagedProfilePropertyList: previousManagedData
        )
    }

    public func installManagedProfile(
        configuration: LiquidGlassConfiguration,
        backup: TerminalPreferenceBackup
    ) async throws {
        _ = try configuration.validated()
        try paths.createRequiredDirectories()

        var windowSettings = try readWindowSettings()
        guard var managedProfile = windowSettings[backup.sourceProfileName] as? [String: Any] else {
            throw LiquidGlassError.terminalPreferences(
                "The source Terminal profile '\(backup.sourceProfileName)' changed before installation; no preferences were modified."
            )
        }

        managedProfile["name"] = configuration.managedProfileName
        managedProfile["BackgroundColor"] = try backgroundColorData(
            from: managedProfile["BackgroundColor"],
            opacity: configuration.terminalBackgroundOpacity
        )
        managedProfile["BackgroundBlur"] = configuration.terminalBackgroundBlur
        managedProfile["BackgroundBlurInactive"] = configuration.terminalBackgroundBlur
        managedProfile["BackgroundSettingsForInactiveWindows"] = false

        if managedProfile["BackgroundColorInactive"] != nil {
            managedProfile["BackgroundColorInactive"] = try backgroundColorData(
                from: managedProfile["BackgroundColorInactive"],
                opacity: configuration.terminalBackgroundOpacity
            )
        }

        windowSettings[configuration.managedProfileName] = managedProfile
        try writeWindowSettings(windowSettings)
        setStringPreference(configuration.managedProfileName, for: "Default Window Settings")
        setStringPreference(configuration.managedProfileName, for: "Startup Window Settings")
        try synchronize()
        try exportProfile(managedProfile)
        postPreferencesChangedNotification()

        logger.log(.info, "Installed managed Terminal profile from '\(backup.sourceProfileName)'.")
    }

    public func updateManagedProfile(configuration: LiquidGlassConfiguration) async throws {
        _ = try configuration.validated()
        var windowSettings = try readWindowSettings()
        guard var managedProfile = windowSettings[configuration.managedProfileName] as? [String: Any] else {
            throw LiquidGlassError.terminalPreferences(
                "The managed Terminal profile is missing. Run `liquidglass off`, then `liquidglass on`."
            )
        }
        managedProfile["BackgroundColor"] = try backgroundColorData(
            from: managedProfile["BackgroundColor"],
            opacity: configuration.terminalBackgroundOpacity
        )
        managedProfile["BackgroundBlur"] = configuration.terminalBackgroundBlur
        managedProfile["BackgroundBlurInactive"] = configuration.terminalBackgroundBlur
        if managedProfile["BackgroundColorInactive"] != nil {
            managedProfile["BackgroundColorInactive"] = try backgroundColorData(
                from: managedProfile["BackgroundColorInactive"],
                opacity: configuration.terminalBackgroundOpacity
            )
        }
        windowSettings[configuration.managedProfileName] = managedProfile
        try writeWindowSettings(windowSettings)
        try synchronize()
        try exportProfile(managedProfile)
        postPreferencesChangedNotification()
    }

    public func restorePreferences(
        from backup: TerminalPreferenceBackup,
        managedProfileName: String
    ) async throws {
        var windowSettings = try readWindowSettings()

        if let encoded = backup.previousManagedProfilePropertyList {
            let restored = try PropertyListSerialization.propertyList(from: encoded, options: [], format: nil)
            windowSettings[managedProfileName] = restored
        } else {
            windowSettings.removeValue(forKey: managedProfileName)
        }

        try writeWindowSettings(windowSettings)
        setOptionalStringPreference(backup.previousDefaultProfileName, for: "Default Window Settings")
        setOptionalStringPreference(backup.previousStartupProfileName, for: "Startup Window Settings")
        try synchronize()
        postPreferencesChangedNotification()

        try? FileManager.default.removeItem(at: paths.profileExportFile)
        logger.log(.info, "Restored Terminal profile preferences.")
    }

    public func managedProfileExists(named name: String) async throws -> Bool {
        try readWindowSettings()[name] != nil
    }

    private func readWindowSettings() throws -> [String: Any] {
        guard let value = CFPreferencesCopyAppValue("Window Settings" as CFString, applicationID) else {
            throw LiquidGlassError.terminalPreferences(
                "Terminal has no profile preferences yet. Launch Terminal once and retry."
            )
        }
        guard let settings = value as? [String: Any], !settings.isEmpty else {
            throw LiquidGlassError.terminalPreferences("Terminal's profile preferences are malformed or empty.")
        }
        return settings
    }

    private func writeWindowSettings(_ settings: [String: Any]) throws {
        guard PropertyListSerialization.propertyList(settings, isValidFor: .binary) else {
            throw LiquidGlassError.terminalPreferences("The generated Terminal profile is not a valid property list.")
        }
        CFPreferencesSetAppValue("Window Settings" as CFString, settings as CFDictionary, applicationID)
    }

    private func stringPreference(for key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, applicationID) as? String
    }

    private func setStringPreference(_ value: String, for key: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFString, applicationID)
    }

    private func setOptionalStringPreference(_ value: String?, for key: String) {
        if let value {
            setStringPreference(value, for: key)
        } else {
            CFPreferencesSetAppValue(key as CFString, nil, applicationID)
        }
    }

    private func synchronize() throws {
        guard CFPreferencesAppSynchronize(applicationID) else {
            throw LiquidGlassError.terminalPreferences("macOS refused to synchronize Terminal preferences.")
        }
    }

    private func resolveSourceProfileName(
        preferred: String?,
        windowSettings: [String: Any],
        excluding managedName: String
    ) -> String {
        if let preferred, preferred != managedName, windowSettings[preferred] != nil {
            return preferred
        }
        if windowSettings["Basic"] != nil {
            return "Basic"
        }
        return windowSettings.keys
            .filter { $0 != managedName }
            .sorted()
            .first ?? managedName
    }

    private func backgroundColorData(from existingValue: Any?, opacity: Double) throws -> Data {
        let baseColor: NSColor
        if let data = existingValue as? Data,
           let decoded = decodeColor(from: data),
           let converted = decoded.usingColorSpace(.sRGB) {
            baseColor = converted
        } else {
            baseColor = .black
        }

        let color = NSColor(
            srgbRed: baseColor.redComponent,
            green: baseColor.greenComponent,
            blue: baseColor.blueComponent,
            alpha: CGFloat(opacity)
        )
        return try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }

    private func decodeColor(from data: Data) -> NSColor? {
        if let securelyDecoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSColor.self,
            from: data
        ) {
            return securelyDecoded
        }

        // Terminal profiles created by older macOS releases can contain keyed
        // archives that predate secure-coding enforcement. The data is read
        // only from the current user's own Terminal preference domain.
        return (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) as? NSColor
    }

    private func encodePropertyList(_ value: Any) throws -> Data {
        guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
            throw LiquidGlassError.terminalPreferences("An existing managed profile could not be backed up.")
        }
        return try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private func exportProfile(_ profile: [String: Any]) throws {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
            try data.write(to: paths.profileExportFile, options: [.atomic])
        } catch {
            throw LiquidGlassError.terminalPreferences(
                "Unable to write the managed .terminal profile: \(error.localizedDescription)"
            )
        }
    }

    private func postPreferencesChangedNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("NSUserDefaultsDidChangeNotification"),
            object: "com.apple.Terminal",
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

#else

public actor SystemTerminalPreferences: TerminalPreferencesManaging {
    public init(paths: AppPaths, logger: any LiquidGlassLogging = StandardLogger(category: "preferences")) {}

    public func capturePreferenceBackup(
        configuration: LiquidGlassConfiguration
    ) async throws -> TerminalPreferenceBackup {
        throw LiquidGlassError.unsupportedPlatform
    }

    public func installManagedProfile(
        configuration: LiquidGlassConfiguration,
        backup: TerminalPreferenceBackup
    ) async throws {
        throw LiquidGlassError.unsupportedPlatform
    }

    public func updateManagedProfile(configuration: LiquidGlassConfiguration) async throws {
        throw LiquidGlassError.unsupportedPlatform
    }

    public func restorePreferences(from backup: TerminalPreferenceBackup, managedProfileName: String) async throws {
        throw LiquidGlassError.unsupportedPlatform
    }

    public func managedProfileExists(named name: String) async throws -> Bool {
        false
    }
}

#endif
