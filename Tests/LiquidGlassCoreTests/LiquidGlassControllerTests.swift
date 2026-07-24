import Foundation
import XCTest
@testable import LiquidGlassCore

private enum MockFailure: LocalizedError {
    case install
    case restore

    var errorDescription: String? {
        switch self {
        case .install: "mock profile installation failed"
        case .restore: "mock profile restoration failed"
        }
    }
}

private struct PreferenceStats: Sendable {
    var installCount: Int
    var updateCount: Int
    var restoreCount: Int
}

private actor MockPreferences: TerminalPreferencesManaging {
    private(set) var installed = false
    private(set) var installCount = 0
    private(set) var updateCount = 0
    private(set) var restoreCount = 0
    private var failInstall = false
    private var failRestore = false

    func setFailInstall(_ value: Bool) { failInstall = value }
    func setFailRestore(_ value: Bool) { failRestore = value }

    func stats() -> PreferenceStats {
        PreferenceStats(
            installCount: installCount,
            updateCount: updateCount,
            restoreCount: restoreCount
        )
    }

    func capturePreferenceBackup(configuration: LiquidGlassConfiguration) async throws -> TerminalPreferenceBackup {
        TerminalPreferenceBackup(
            previousDefaultProfileName: "Basic",
            previousStartupProfileName: "Basic",
            sourceProfileName: "Basic",
            previousManagedProfilePropertyList: nil
        )
    }

    func installManagedProfile(
        configuration: LiquidGlassConfiguration,
        backup: TerminalPreferenceBackup
    ) async throws {
        if failInstall { throw MockFailure.install }
        installed = true
        installCount += 1
    }

    func updateManagedProfile(configuration: LiquidGlassConfiguration) async throws {
        updateCount += 1
    }

    func restorePreferences(from backup: TerminalPreferenceBackup, managedProfileName: String) async throws {
        restoreCount += 1
        if failRestore { throw MockFailure.restore }
        installed = false
    }

    func managedProfileExists(named name: String) async throws -> Bool { installed }
}

private struct AutomationStats: Sendable {
    var appliedProfiles: [String]
    var restoredSnapshots: [[TerminalTabSnapshot]]
    var restoreManagedProfileNames: [String]
    var restoreFallbackProfileNames: [String]
    var defaultRestoreCount: Int
}

private actor MockAutomation: TerminalAutomating {
    private(set) var appliedProfiles: [String] = []
    private(set) var restoredSnapshots: [[TerminalTabSnapshot]] = []
    private(set) var restoreManagedProfileNames: [String] = []
    private(set) var restoreFallbackProfileNames: [String] = []
    private(set) var defaultRestoreCount = 0
    private var running = true
    private var capturedSnapshots = [
        TerminalTabSnapshot(
            windowIndex: 1,
            tabIndex: 1,
            tty: "/dev/ttys001",
            profileName: "Basic"
        )
    ]

    func setRunning(_ value: Bool) { running = value }
    func setCapturedSnapshots(_ value: [TerminalTabSnapshot]) { capturedSnapshots = value }

    func stats() -> AutomationStats {
        AutomationStats(
            appliedProfiles: appliedProfiles,
            restoredSnapshots: restoredSnapshots,
            restoreManagedProfileNames: restoreManagedProfileNames,
            restoreFallbackProfileNames: restoreFallbackProfileNames,
            defaultRestoreCount: defaultRestoreCount
        )
    }

    func isRunning() async -> Bool { running }
    func captureTabProfiles() async throws -> [TerminalTabSnapshot] { capturedSnapshots }
    func applyProfile(named profileName: String) async throws { appliedProfiles.append(profileName) }

    func restoreTabProfiles(
        _ snapshots: [TerminalTabSnapshot],
        managedProfileName: String,
        fallbackProfileName: String
    ) async throws {
        restoredSnapshots.append(snapshots)
        restoreManagedProfileNames.append(managedProfileName)
        restoreFallbackProfileNames.append(fallbackProfileName)
    }

    func restoreDefaultProfiles(
        defaultProfileName: String?,
        startupProfileName: String?,
        fallbackProfileName: String
    ) async throws {
        defaultRestoreCount += 1
    }

    func profileIsVisible(named profileName: String) async throws -> Bool { true }
    func importManagedProfileIfNeeded(named profileName: String) async throws {}
    func requestAutomationConsent() async throws {}
}

private actor MockAgent: AgentSignaling {
    private(set) var signalCount = 0
    private var loaded = true

    func setLoaded(_ value: Bool) { loaded = value }
    func signalConfigurationChanged() async throws { signalCount += 1 }
    func requestScreenCapturePermission() async throws {}
    func isAgentLoaded() async -> Bool { loaded }
}

final class LiquidGlassControllerTests: XCTestCase {
    func testDoctorPromptFailsClearlyWhenTerminalIsNotRunning() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await fixture.automation.setRunning(false)

        let checks = await fixture.controller.doctor(promptForPermissions: true)
        let automation = try XCTUnwrap(checks.first { $0.name == "automation" })

        XCTAssertEqual(automation.severity, .warning)
        XCTAssertTrue(automation.message.contains("Open Terminal"))
    }

    func testEnableRefusesToMutateTerminalWhenAgentIsNotLoaded() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await fixture.agent.setLoaded(false)

        do {
            _ = try await fixture.controller.turnOn()
            XCTFail("Expected enable to fail when the agent is unavailable.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not loaded"))
        }

        let preferenceStats = await fixture.preferences.stats()
        let automationStats = await fixture.automation.stats()
        XCTAssertEqual(preferenceStats.installCount, 0)
        XCTAssertTrue(automationStats.appliedProfiles.isEmpty)
        let persistedState = try await stateStore(for: fixture.paths).load()
        XCTAssertFalse(persistedState.enabled)
    }

    func testEnableAndDisableAreTransactional() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let enabled = try await fixture.controller.turnOn()
        XCTAssertTrue(enabled.enabled)
        let enabledPreferenceStats = await fixture.preferences.stats()
        let enabledAutomationStats = await fixture.automation.stats()
        XCTAssertEqual(enabledPreferenceStats.installCount, 1)
        XCTAssertEqual(enabledAutomationStats.appliedProfiles, [LiquidGlassVersion.managedProfileName])

        let disabled = try await fixture.controller.turnOff()
        XCTAssertFalse(disabled.enabled)
        let disabledPreferenceStats = await fixture.preferences.stats()
        let disabledAutomationStats = await fixture.automation.stats()
        XCTAssertEqual(disabledPreferenceStats.restoreCount, 1)
        XCTAssertEqual(disabledAutomationStats.restoredSnapshots.count, 1)
        XCTAssertEqual(disabledAutomationStats.restoreManagedProfileNames, [LiquidGlassVersion.managedProfileName])
        XCTAssertEqual(disabledAutomationStats.restoreFallbackProfileNames, ["Basic"])
        XCTAssertEqual(disabledAutomationStats.defaultRestoreCount, 1)
    }

    func testDisableSweepsManagedTabsCreatedAfterAnEmptyInitialSnapshot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await fixture.automation.setCapturedSnapshots([])

        _ = try await fixture.controller.turnOn()
        _ = try await fixture.controller.turnOff()

        let automationStats = await fixture.automation.stats()
        XCTAssertEqual(automationStats.restoredSnapshots, [[]])
        XCTAssertEqual(automationStats.restoreManagedProfileNames, [LiquidGlassVersion.managedProfileName])
        XCTAssertEqual(automationStats.restoreFallbackProfileNames, ["Basic"])
    }

    func testSecondEnableRefreshesWithoutReplacingBackup() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        _ = try await fixture.controller.turnOn()
        _ = try await fixture.controller.turnOn()

        let stats = await fixture.preferences.stats()
        XCTAssertEqual(stats.installCount, 1)
        XCTAssertEqual(stats.updateCount, 1)
    }

    func testLiveConfigurationUpdateRefreshesManagedProfile() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        _ = try await fixture.controller.turnOn()
        let updated = try await fixture.controller.updateConfiguration([.cornerRadius(27)])

        XCTAssertEqual(updated.cornerRadius, 27)
        let stats = await fixture.preferences.stats()
        XCTAssertEqual(stats.updateCount, 1)
    }

    func testEnableFailureRollsBackTabsDefaultsAndPreferences() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await fixture.preferences.setFailInstall(true)

        do {
            _ = try await fixture.controller.turnOn()
            XCTFail("Expected the mocked profile installation to fail.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("mock profile installation failed"))
        }

        let automationStats = await fixture.automation.stats()
        let preferenceStats = await fixture.preferences.stats()
        XCTAssertEqual(automationStats.restoredSnapshots.count, 1)
        XCTAssertEqual(automationStats.defaultRestoreCount, 1)
        XCTAssertEqual(preferenceStats.restoreCount, 1)

        let state = try await stateStore(for: fixture.paths).load()
        XCTAssertFalse(state.enabled)
        XCTAssertNil(state.transition)
        XCTAssertNil(state.preferenceBackup)
        XCTAssertTrue(state.tabSnapshots.isEmpty)
        XCTAssertNotNil(state.lastError)
    }

    func testInterruptedEnableIsRecoveredBeforeASecondEnable() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let backup = TerminalPreferenceBackup(
            previousDefaultProfileName: "Basic",
            previousStartupProfileName: "Basic",
            sourceProfileName: "Basic",
            previousManagedProfilePropertyList: nil
        )
        let snapshot = TerminalTabSnapshot(
            windowIndex: 1,
            tabIndex: 1,
            tty: "/dev/ttys001",
            profileName: "Basic"
        )
        try await stateStore(for: fixture.paths).save(
            LiquidGlassState(
                enabled: false,
                transition: .enabling,
                preferenceBackup: backup,
                tabSnapshots: [snapshot],
                changedAt: Date()
            )
        )

        let status = try await fixture.controller.turnOn()

        XCTAssertTrue(status.enabled)
        let preferenceStats = await fixture.preferences.stats()
        let automationStats = await fixture.automation.stats()
        XCTAssertEqual(preferenceStats.restoreCount, 1)
        XCTAssertEqual(preferenceStats.installCount, 1)
        XCTAssertEqual(automationStats.restoredSnapshots, [[snapshot]])
    }

    func testFailedDisableRetainsRecoveryDataAndCanBeRetried() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        _ = try await fixture.controller.turnOn()
        await fixture.preferences.setFailRestore(true)

        do {
            _ = try await fixture.controller.turnOff()
            XCTFail("Expected the mocked profile restoration to fail.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("mock profile restoration failed"))
        }

        let failedState = try await stateStore(for: fixture.paths).load()
        XCTAssertFalse(failedState.enabled)
        XCTAssertNil(failedState.transition)
        XCTAssertNotNil(failedState.preferenceBackup)
        XCTAssertFalse(failedState.tabSnapshots.isEmpty)

        await fixture.preferences.setFailRestore(false)
        let recovered = try await fixture.controller.turnOff()
        XCTAssertFalse(recovered.enabled)

        let recoveredState = try await stateStore(for: fixture.paths).load()
        XCTAssertNil(recoveredState.preferenceBackup)
        XCTAssertTrue(recoveredState.tabSnapshots.isEmpty)
        XCTAssertNil(recoveredState.lastError)
    }

    private func stateStore(for paths: AppPaths) -> AtomicJSONStore<LiquidGlassState> {
        AtomicJSONStore(url: paths.stateFile, defaultValue: { .disabled })
    }

    private func makeFixture() throws -> (
        directory: URL,
        paths: AppPaths,
        controller: LiquidGlassController,
        preferences: MockPreferences,
        automation: MockAutomation,
        agent: MockAgent
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let paths = AppPaths(homeDirectory: directory, environment: [:])
        try paths.createRequiredDirectories()
        let runtime = AgentRuntimeStatus(
            processIdentifier: 123,
            startedAt: Date(),
            heartbeatAt: Date(),
            enabled: true,
            windowTrackingMode: .coreGraphicsMetadataPolling,
            terminalWindowCount: 1,
            overlayCount: 1,
            activeDisplayCaptureCount: 1,
            screenCaptureAuthorized: true,
            metalDeviceName: "Mock Metal",
            capturedFrameCount: 1,
            droppedFrameCount: 0,
            lastError: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(runtime).write(to: paths.agentRuntimeFile, options: .atomic)
        let preferences = MockPreferences()
        let automation = MockAutomation()
        let agent = MockAgent()
        let controller = LiquidGlassController(
            paths: paths,
            preferences: preferences,
            automation: automation,
            agent: agent,
            logger: NullLogger()
        )
        return (directory, paths, controller, preferences, automation, agent)
    }
}
