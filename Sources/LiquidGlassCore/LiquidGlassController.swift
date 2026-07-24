import Foundation

public actor LiquidGlassController {
    private let paths: AppPaths
    private let configurationStore: AtomicJSONStore<LiquidGlassConfiguration>
    private let stateStore: AtomicJSONStore<LiquidGlassState>
    private let runtimeStore: AtomicJSONStore<AgentRuntimeStatus?>
    private let preferences: any TerminalPreferencesManaging
    private let automation: any TerminalAutomating
    private let agent: any AgentSignaling
    private let logger: any LiquidGlassLogging

    public init(
        paths: AppPaths,
        preferences: any TerminalPreferencesManaging,
        automation: any TerminalAutomating,
        agent: any AgentSignaling,
        logger: any LiquidGlassLogging = StandardLogger(category: "controller")
    ) {
        self.paths = paths
        self.configurationStore = AtomicJSONStore(
            url: paths.configurationFile,
            defaultValue: { .default }
        )
        self.stateStore = AtomicJSONStore(
            url: paths.stateFile,
            defaultValue: { .disabled }
        )
        self.runtimeStore = AtomicJSONStore(
            url: paths.agentRuntimeFile,
            defaultValue: { nil }
        )
        self.preferences = preferences
        self.automation = automation
        self.agent = agent
        self.logger = logger
    }

    @discardableResult
    public func turnOn() async throws -> LiquidGlassStatus {
        try paths.createRequiredDirectories()
        let configuration = try await loadConfiguration()
        var state = try await stateStore.load()
        if !state.enabled, (state.transition != nil || state.preferenceBackup != nil || !state.tabSnapshots.isEmpty) {
            _ = try await turnOff()
            state = try await stateStore.load()
        }

        guard await agent.isAgentLoaded() else {
            throw LiquidGlassError.agent(
                "LiquidGlassAgent is not loaded. Run `./Scripts/install.sh`, then retry."
            )
        }

        if state.enabled, state.transition == nil {
            try await preferences.updateManagedProfile(configuration: configuration)
            if await automation.isRunning() {
                try await automation.importManagedProfileIfNeeded(named: configuration.managedProfileName)
                try await automation.applyProfile(named: configuration.managedProfileName)
            }
            try await agent.signalConfigurationChanged()
            try await waitForRendererStartupIfTerminalIsRunning()
            logger.log(.info, "LiquidGlass was already enabled; refreshed its profile and Metal compositor.")
            return try await status()
        }

        state.transition = .enabling
        state.lastError = nil
        state.changedAt = Date()
        try await stateStore.save(state)

        var capturedTabs: [TerminalTabSnapshot] = []
        var backup: TerminalPreferenceBackup?

        do {
            if await automation.isRunning() {
                capturedTabs = try await automation.captureTabProfiles()
            }
            state.tabSnapshots = capturedTabs
            state.changedAt = Date()
            try await stateStore.save(state)

            let capturedBackup = try await preferences.capturePreferenceBackup(configuration: configuration)
            backup = capturedBackup
            state.preferenceBackup = capturedBackup
            state.changedAt = Date()
            try await stateStore.save(state)

            try await preferences.installManagedProfile(
                configuration: configuration,
                backup: capturedBackup
            )

            if await automation.isRunning() {
                try await automation.importManagedProfileIfNeeded(named: configuration.managedProfileName)
                try await automation.applyProfile(named: configuration.managedProfileName)
            }

            state.enabled = true
            state.transition = nil
            state.preferenceBackup = capturedBackup
            state.tabSnapshots = capturedTabs
            state.enabledAt = Date()
            state.changedAt = Date()
            state.lastError = nil
            try await stateStore.save(state)
            try await agent.signalConfigurationChanged()
            try await waitForRendererStartupIfTerminalIsRunning()
            logger.log(.info, "LiquidGlass enabled and the Metal compositor is producing frames.")
            return try await status()
        } catch {
            let primaryError = error
            var rollbackErrors: [String] = []

            if await automation.isRunning(), backup != nil || !capturedTabs.isEmpty {
                do {
                    try await automation.restoreTabProfiles(
                        capturedTabs,
                        managedProfileName: configuration.managedProfileName,
                        fallbackProfileName: backup?.sourceProfileName ?? "Basic"
                    )
                } catch {
                    rollbackErrors.append("tab restore: \(error.localizedDescription)")
                }
            }
            if let backup, await automation.isRunning() {
                do {
                    try await automation.restoreDefaultProfiles(
                        defaultProfileName: backup.previousDefaultProfileName,
                        startupProfileName: backup.previousStartupProfileName,
                        fallbackProfileName: backup.sourceProfileName
                    )
                } catch {
                    rollbackErrors.append("default profile restore: \(error.localizedDescription)")
                }
            }
            if let backup {
                do {
                    try await preferences.restorePreferences(
                        from: backup,
                        managedProfileName: configuration.managedProfileName
                    )
                } catch {
                    rollbackErrors.append("preference restore: \(error.localizedDescription)")
                }
            }

            state.enabled = false
            state.transition = nil
            state.preferenceBackup = rollbackErrors.isEmpty ? nil : backup
            state.tabSnapshots = rollbackErrors.isEmpty ? [] : capturedTabs
            state.enabledAt = nil
            state.changedAt = Date()
            state.lastError = rollbackErrors.isEmpty
                ? primaryError.localizedDescription
                : "\(primaryError.localizedDescription) Rollback also failed (\(rollbackErrors.joined(separator: "; ")))."
            try? await stateStore.save(state)
            try? await agent.signalConfigurationChanged()
            logger.log(.error, "Enable failed: \(state.lastError ?? primaryError.localizedDescription)")
            throw LiquidGlassError.state(state.lastError ?? primaryError.localizedDescription)
        }
    }

    @discardableResult
    public func turnOff() async throws -> LiquidGlassStatus {
        try paths.createRequiredDirectories()
        let configuration = try await loadConfiguration()
        var state = try await stateStore.load()

        guard state.enabled || state.preferenceBackup != nil || state.transition != nil else {
            try await agent.signalConfigurationChanged()
            logger.log(.info, "LiquidGlass was already disabled.")
            return try await status()
        }

        state.enabled = false
        state.transition = .disabling
        state.changedAt = Date()
        state.lastError = nil
        try await stateStore.save(state)
        try? await agent.signalConfigurationChanged()

        do {
            if await automation.isRunning() {
                try await automation.restoreTabProfiles(
                    state.tabSnapshots,
                    managedProfileName: configuration.managedProfileName,
                    fallbackProfileName: state.preferenceBackup?.sourceProfileName ?? "Basic"
                )
                if let backup = state.preferenceBackup {
                    try await automation.restoreDefaultProfiles(
                        defaultProfileName: backup.previousDefaultProfileName,
                        startupProfileName: backup.previousStartupProfileName,
                        fallbackProfileName: backup.sourceProfileName
                    )
                }
            }
            if let backup = state.preferenceBackup {
                try await preferences.restorePreferences(
                    from: backup,
                    managedProfileName: configuration.managedProfileName
                )
            }

            state.enabled = false
            state.transition = nil
            state.preferenceBackup = nil
            state.tabSnapshots = []
            state.enabledAt = nil
            state.changedAt = Date()
            state.lastError = nil
            try await stateStore.save(state)
            try await agent.signalConfigurationChanged()
            logger.log(.info, "LiquidGlass disabled and Terminal profiles restored.")
            return try await status()
        } catch {
            state.enabled = false
            state.transition = nil
            state.changedAt = Date()
            state.lastError = error.localizedDescription
            try? await stateStore.save(state)
            try? await agent.signalConfigurationChanged()
            logger.log(.error, "Disable failed: \(error.localizedDescription)")
            throw error
        }
    }

    @discardableResult
    public func toggle() async throws -> LiquidGlassStatus {
        let state = try await stateStore.load()
        return try await state.enabled ? turnOff() : turnOn()
    }

    public func status() async throws -> LiquidGlassStatus {
        let configuration = try await loadConfiguration()
        let state = try await stateStore.load()
        let profileInstalled = (try? await preferences.managedProfileExists(named: configuration.managedProfileName)) ?? false
        return LiquidGlassStatus(
            enabled: state.enabled,
            transition: state.transition,
            agentLoaded: await agent.isAgentLoaded(),
            terminalRunning: await automation.isRunning(),
            managedProfileInstalled: profileInstalled,
            configuration: configuration,
            enabledAt: state.enabledAt,
            lastError: state.lastError
        )
    }

    public func loadConfiguration() async throws -> LiquidGlassConfiguration {
        try await configurationStore.load().validated()
    }

    @discardableResult
    public func updateConfiguration(
        _ mutations: [ConfigurationMutation]
    ) async throws -> LiquidGlassConfiguration {
        let current = try await loadConfiguration()
        let updated = try current.applying(mutations)
        try await configurationStore.save(updated)

        let state = try await stateStore.load()
        if state.enabled {
            do {
                try await applyEnabledConfiguration(updated)
            } catch {
                await restoreConfigurationAfterFailedApply(current)
                throw error
            }
        } else {
            try await agent.signalConfigurationChanged()
        }
        return updated
    }

    @discardableResult
    public func resetConfiguration() async throws -> LiquidGlassConfiguration {
        let current = try await loadConfiguration()
        let reset = LiquidGlassConfiguration.default
        try await configurationStore.save(reset)

        let state = try await stateStore.load()
        if state.enabled {
            do {
                try await applyEnabledConfiguration(reset)
            } catch {
                await restoreConfigurationAfterFailedApply(current)
                throw error
            }
        } else {
            try await agent.signalConfigurationChanged()
        }
        return reset
    }

    private func waitForRendererStartupIfTerminalIsRunning() async throws {
        guard await automation.isRunning() else { return }

        let deadline = Date().addingTimeInterval(20)
        var mostRecentError: String?
        while Date() < deadline {
            if let runtime = try? await runtimeStore.load(),
               Date().timeIntervalSince(runtime.heartbeatAt) < 8 {
                if let error = runtime.lastError, !error.isEmpty {
                    mostRecentError = error
                    if !runtime.screenCaptureAuthorized {
                        throw LiquidGlassError.agent(error)
                    }
                }
                if runtime.enabled,
                   runtime.screenCaptureAuthorized,
                   runtime.metalDeviceName != nil,
                   runtime.overlayCount > 0,
                   runtime.capturedFrameCount > 0 {
                    return
                }
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        throw LiquidGlassError.agent(
            mostRecentError
                ?? "The Metal compositor did not produce a frame within 20 seconds. Run `liquidglass doctor --prompt` and inspect the agent log."
        )
    }

    private func applyEnabledConfiguration(
        _ configuration: LiquidGlassConfiguration
    ) async throws {
        try await preferences.updateManagedProfile(configuration: configuration)
        if await automation.isRunning() {
            try await automation.applyProfile(named: configuration.managedProfileName)
        }
        try await agent.signalConfigurationChanged()
    }

    private func restoreConfigurationAfterFailedApply(
        _ previous: LiquidGlassConfiguration
    ) async {
        try? await configurationStore.save(previous)
        try? await preferences.updateManagedProfile(configuration: previous)
        if await automation.isRunning() {
            try? await automation.applyProfile(named: previous.managedProfileName)
        }
        try? await agent.signalConfigurationChanged()
    }

    public func doctor(promptForPermissions: Bool) async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []

        #if os(macOS)
        checks.append(.init(
            name: "platform",
            severity: .pass,
            message: "Running on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)."
        ))
        #else
        checks.append(.init(name: "platform", severity: .failure, message: "LiquidGlass Terminal requires macOS."))
        #endif

        do {
            try paths.createRequiredDirectories()
            checks.append(.init(name: "storage", severity: .pass, message: "Application support is writable."))
        } catch {
            checks.append(.init(name: "storage", severity: .failure, message: error.localizedDescription))
        }

        do {
            _ = try await loadConfiguration()
            checks.append(.init(name: "configuration", severity: .pass, message: "Shader configuration is valid."))
        } catch {
            checks.append(.init(name: "configuration", severity: .failure, message: error.localizedDescription))
        }

        let loaded = await agent.isAgentLoaded()
        checks.append(.init(
            name: "launch-agent",
            severity: loaded ? .pass : .failure,
            message: loaded ? "LiquidGlassAgent is loaded." : "LiquidGlassAgent is not loaded; rerun Scripts/install.sh."
        ))

        if promptForPermissions, loaded {
            do {
                try await agent.requestScreenCapturePermission()
                try? await Task.sleep(nanoseconds: 900_000_000)
            } catch {
                checks.append(.init(name: "screen-capture-request", severity: .warning, message: error.localizedDescription))
            }
        }

        let runtime = (try? await runtimeStore.load()) ?? nil
        if let runtime, Date().timeIntervalSince(runtime.heartbeatAt) < 15 {
            checks.append(.init(
                name: "agent-heartbeat",
                severity: .pass,
                message: "Agent heartbeat is current (PID \(runtime.processIdentifier))."
            ))
            checks.append(.init(
                name: "metal",
                severity: runtime.metalDeviceName == nil ? .failure : .pass,
                message: runtime.metalDeviceName.map { "Metal device: \($0)." } ?? "No Metal device is available."
            ))
            checks.append(.init(
                name: "screen-capture",
                severity: runtime.screenCaptureAuthorized ? .pass : .failure,
                message: runtime.screenCaptureAuthorized
                    ? "ScreenCaptureKit is authorized; \(runtime.activeDisplayCaptureCount) display stream(s) active."
                    : "Screen Recording permission is not active for LiquidGlass.app. Approve the macOS prompt, then run `liquidglass on` again."
            ))
            checks.append(.init(
                name: "renderer",
                severity: runtime.lastError == nil ? .pass : .warning,
                message: runtime.lastError ?? "Metal compositor is healthy: \(runtime.overlayCount) overlay(s), \(runtime.capturedFrameCount) captured frame(s), \(runtime.droppedFrameCount) dropped."
            ))
        } else {
            checks.append(.init(
                name: "agent-heartbeat",
                severity: loaded ? .warning : .failure,
                message: "No current agent heartbeat is available."
            ))
            checks.append(.init(
                name: "screen-capture",
                severity: .warning,
                message: "ScreenCaptureKit authorization cannot be verified until the agent is running."
            ))
        }

        if promptForPermissions {
            if await automation.isRunning() {
                do {
                    try await automation.requestAutomationConsent()
                    checks.append(.init(name: "automation", severity: .pass, message: "Terminal Automation is authorized."))
                } catch {
                    checks.append(.init(name: "automation", severity: .failure, message: error.localizedDescription))
                }
            } else {
                checks.append(.init(
                    name: "automation",
                    severity: .warning,
                    message: "Open Terminal to verify the one-time Automation permission."
                ))
            }
        } else {
            checks.append(.init(
                name: "automation",
                severity: .warning,
                message: "Run `liquidglass doctor --prompt` with Terminal open to verify Automation permission."
            ))
        }

        return checks
    }

    public func purgeState() async throws {
        let state = try await stateStore.load()
        guard !state.enabled, state.preferenceBackup == nil else {
            throw LiquidGlassError.state("Turn LiquidGlass off successfully before purging its state.")
        }
        try await stateStore.reset()
        try await configurationStore.reset()
        try await runtimeStore.reset()
        try? FileManager.default.removeItem(at: paths.profileExportFile)
    }
}
