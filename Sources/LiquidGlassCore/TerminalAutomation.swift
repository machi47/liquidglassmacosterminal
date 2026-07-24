import Foundation

#if os(macOS)
import AppKit

public actor SystemTerminalAutomation: TerminalAutomating {
    private let runner: any ProcessRunning
    private let paths: AppPaths
    private let logger: any LiquidGlassLogging

    public init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        paths: AppPaths,
        logger: any LiquidGlassLogging = StandardLogger(category: "automation")
    ) {
        self.runner = runner
        self.paths = paths
        self.logger = logger
    }

    public func isRunning() async -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty
    }

    public func captureTabProfiles() async throws -> [TerminalTabSnapshot] {
        guard await isRunning() else { return [] }

        let script = """
        tell application "Terminal"
            set fieldSeparator to character id 31
            set rowSeparator to character id 30
            set outputText to ""
            repeat with windowIndex from 1 to count of windows
                set terminalWindow to window windowIndex
                repeat with tabIndex from 1 to count of tabs of terminalWindow
                    set terminalTab to tab tabIndex of terminalWindow
                    set profileName to name of current settings of terminalTab
                    try
                        set ttyName to tty of terminalTab as text
                    on error
                        set ttyName to ""
                    end try
                    set outputText to outputText & windowIndex & fieldSeparator & tabIndex & fieldSeparator & ttyName & fieldSeparator & profileName & rowSeparator
                end repeat
            end repeat
            return outputText
        end tell
        """

        let output = try await runAppleScript(script)
        return parseSnapshots(output)
    }

    public func applyProfile(named profileName: String) async throws {
        guard await isRunning() else { return }
        let escaped = appleScriptString(profileName)
        let script = """
        tell application "Terminal"
            if not (exists settings set "\(escaped)") then error "Terminal has not loaded profile \(escaped)."
            set targetSettings to settings set "\(escaped)"
            repeat with terminalWindow in windows
                repeat with terminalTab in tabs of terminalWindow
                    set current settings of terminalTab to targetSettings
                end repeat
            end repeat
            try
                set default settings to targetSettings
            end try
            try
                set startup settings to targetSettings
            end try
        end tell
        """
        _ = try await runAppleScript(script)
        logger.log(.info, "Applied profile '\(profileName)' to open Terminal tabs.")
    }

    public func restoreTabProfiles(
        _ snapshots: [TerminalTabSnapshot],
        managedProfileName: String,
        fallbackProfileName: String
    ) async throws {
        guard await isRunning() else { return }

        var statements: [String] = []
        statements.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            let tty = appleScriptString(snapshot.tty ?? "")
            let profile = appleScriptString(snapshot.profileName)
            statements.append(
                """
                    set targetTab to missing value
                    if "\(tty)" is not "" then
                        repeat with candidateWindow in windows
                            repeat with candidateTab in tabs of candidateWindow
                                try
                                    if (tty of candidateTab as text) is "\(tty)" then
                                        set targetTab to candidateTab
                                        exit repeat
                                    end if
                                end try
                            end repeat
                            if targetTab is not missing value then exit repeat
                        end repeat
                    end if
                    if targetTab is missing value then
                        try
                            set targetTab to tab \(snapshot.tabIndex) of window \(snapshot.windowIndex)
                        end try
                    end if
                    if targetTab is not missing value then
                        try
                            if exists settings set "\(profile)" then
                                set current settings of targetTab to settings set "\(profile)"
                            end if
                        end try
                    end if
                """
            )
        }

        let managed = appleScriptString(managedProfileName)
        let fallback = appleScriptString(fallbackProfileName)
        let script = """
        tell application "Terminal"
        \(statements.joined(separator: "\n"))
            -- Tabs and windows created after LiquidGlass was enabled do not
            -- appear in the original snapshot. Restore any such tab that still
            -- uses the managed profile to the pre-enable source profile.
            if exists settings set "\(fallback)" then
                set fallbackSettings to settings set "\(fallback)"
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        try
                            if name of current settings of terminalTab is "\(managed)" then
                                set current settings of terminalTab to fallbackSettings
                            end if
                        end try
                    end repeat
                end repeat
            end if
        end tell
        """
        _ = try await runAppleScript(script)
        logger.log(
            .info,
            "Restored \(snapshots.count) Terminal tab snapshots and any later managed-profile tabs."
        )
    }

    public func restoreDefaultProfiles(
        defaultProfileName: String?,
        startupProfileName: String?,
        fallbackProfileName: String
    ) async throws {
        guard await isRunning() else { return }
        let defaultName = appleScriptString(defaultProfileName ?? fallbackProfileName)
        let startupName = appleScriptString(startupProfileName ?? defaultProfileName ?? fallbackProfileName)
        let script = """
        tell application "Terminal"
            if exists settings set "\(defaultName)" then
                set default settings to settings set "\(defaultName)"
            end if
            if exists settings set "\(startupName)" then
                set startup settings to settings set "\(startupName)"
            end if
        end tell
        """
        _ = try await runAppleScript(script)
    }

    public func profileIsVisible(named profileName: String) async throws -> Bool {
        guard await isRunning() else { return true }
        let escaped = appleScriptString(profileName)
        let output = try await runAppleScript(
            "tell application \"Terminal\" to return (exists settings set \"\(escaped)\") as text"
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    public func requestAutomationConsent() async throws {
        guard await isRunning() else { return }
        _ = try await runAppleScript("tell application \"Terminal\" to get name")
    }

    public func importManagedProfileIfNeeded(named profileName: String) async throws {
        guard await isRunning() else { return }
        if try await profileIsVisible(named: profileName) { return }
        guard FileManager.default.fileExists(atPath: paths.profileExportFile.path) else {
            throw LiquidGlassError.terminalAutomation("The generated .terminal profile is missing.")
        }

        let existingWindowIDs = try await terminalWindowIDs()
        _ = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-g", "-a", "Terminal", paths.profileExportFile.path]
        )

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if try await profileIsVisible(named: profileName) {
                // Importing a .terminal file can publish the settings set just
                // before Terminal creates its one-off import window. Give that
                // window a short bounded interval to appear, then close only a
                // newly-created window that is using the managed profile.
                for _ in 0..<8 {
                    if try await closeImportedWindow(
                        excluding: existingWindowIDs,
                        profileName: profileName
                    ) {
                        break
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                return
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw LiquidGlassError.terminalAutomation(
            "Terminal did not load the managed profile. Quit and reopen Terminal once, then run `liquidglass on` again."
        )
    }

    private func terminalWindowIDs() async throws -> Set<Int> {
        guard await isRunning() else { return [] }
        let output = try await runAppleScript(
            """
            tell application "Terminal"
                set oldDelimiters to AppleScript's text item delimiters
                set AppleScript's text item delimiters to ","
                set windowIDText to (id of every window) as text
                set AppleScript's text item delimiters to oldDelimiters
                return windowIDText
            end tell
            """
        )
        return Set(
            output
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .compactMap { Int($0) }
        )
    }

    private func closeImportedWindow(
        excluding existingIDs: Set<Int>,
        profileName: String
    ) async throws -> Bool {
        let ids = existingIDs.sorted().map(String.init).joined(separator: ", ")
        let excludedList = ids.isEmpty ? "{}" : "{\(ids)}"
        let escaped = appleScriptString(profileName)
        let script = """
        tell application "Terminal"
            set oldWindowIDs to \(excludedList)
            repeat with terminalWindow in windows
                if (id of terminalWindow is not in oldWindowIDs) then
                    try
                        if name of current settings of selected tab of terminalWindow is "\(escaped)" then
                            close terminalWindow
                            return true
                        end if
                    end try
                end if
            end repeat
            return false
        end tell
        """
        let output = try await runAppleScript(script)
        return output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    private func parseSnapshots(_ text: String) -> [TerminalTabSnapshot] {
        text.split(separator: Character(UnicodeScalar(30)!))
            .compactMap { row in
                let fields = row.split(
                    separator: Character(UnicodeScalar(31)!),
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard fields.count == 4,
                      let windowIndex = Int(fields[0]),
                      let tabIndex = Int(fields[1]),
                      !fields[3].isEmpty else {
                    return nil
                }
                return TerminalTabSnapshot(
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    tty: fields[2].isEmpty ? nil : fields[2],
                    profileName: fields[3]
                )
            }
    }

    private func runAppleScript(_ script: String) async throws -> String {
        do {
            return try await MainActor.run {
                guard let appleScript = NSAppleScript(source: script) else {
                    throw LiquidGlassError.terminalAutomation("Unable to compile the Terminal automation script.")
                }
                var errorInfo: NSDictionary?
                let descriptor = appleScript.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                        ?? errorInfo.description
                    throw LiquidGlassError.terminalAutomation(
                        "AppleScript error \(number): \(message)"
                    )
                }
                return descriptor.stringValue ?? descriptor.description
            }
        } catch {
            throw mapAutomationError(error)
        }
    }

    private func mapAutomationError(_ error: Error) -> LiquidGlassError {
        let message = error.localizedDescription
        if message.contains("-1743") || message.localizedCaseInsensitiveContains("not authorized") {
            return .terminalAutomation(
                "Terminal automation permission was denied. Open System Settings > Privacy & Security > Automation and allow LiquidGlass Terminal to control Terminal."
            )
        }
        return .terminalAutomation("Terminal automation failed: \(message)")
    }

    private func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

}

public extension TerminalAutomating {
    func importManagedProfileIfNeeded(named profileName: String) async throws {
        // Implementations used by tests or alternate Terminal integrations may
        // already expose newly written profiles immediately.
    }
}

#else

public actor SystemTerminalAutomation: TerminalAutomating {
    public init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        paths: AppPaths,
        logger: any LiquidGlassLogging = StandardLogger(category: "automation")
    ) {}

    public func isRunning() async -> Bool { false }
    public func captureTabProfiles() async throws -> [TerminalTabSnapshot] { throw LiquidGlassError.unsupportedPlatform }
    public func applyProfile(named profileName: String) async throws { throw LiquidGlassError.unsupportedPlatform }
    public func restoreTabProfiles(
        _ snapshots: [TerminalTabSnapshot],
        managedProfileName: String,
        fallbackProfileName: String
    ) async throws { throw LiquidGlassError.unsupportedPlatform }
    public func restoreDefaultProfiles(
        defaultProfileName: String?,
        startupProfileName: String?,
        fallbackProfileName: String
    ) async throws { throw LiquidGlassError.unsupportedPlatform }
    public func profileIsVisible(named profileName: String) async throws -> Bool { false }
    public func requestAutomationConsent() async throws { throw LiquidGlassError.unsupportedPlatform }
}

public extension TerminalAutomating {
    func importManagedProfileIfNeeded(named profileName: String) async throws {}
}

#endif
