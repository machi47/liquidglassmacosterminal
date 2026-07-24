#if os(macOS)
import AppKit
import CoreGraphics
import LiquidGlassCore

@MainActor
final class AgentApplicationDelegate: NSObject, NSApplicationDelegate {
    private let paths = AppPaths()
    private lazy var configurationStore = AtomicJSONStore(
        url: paths.configurationFile,
        defaultValue: { LiquidGlassConfiguration.default }
    )
    private lazy var stateStore = AtomicJSONStore(
        url: paths.stateFile,
        defaultValue: { LiquidGlassState.disabled }
    )
    private lazy var runtimeStore = AtomicJSONStore<AgentRuntimeStatus?>(
        url: paths.agentRuntimeFile,
        defaultValue: { nil }
    )
    private let tracker = TerminalWindowTracker()
    private let logger: any LiquidGlassLogging = StandardLogger(category: "agent")

    private var metalContext: MetalContext?
    private var captureCoordinator: CaptureCoordinator?
    private var overlayManager: OverlayManager?
    private var configurationNotificationToken: NSObjectProtocol?
    private var permissionNotificationToken: NSObjectProtocol?
    private var heartbeatTimer: Timer?
    private var reloadTask: Task<Void, Never>?

    private var currentConfiguration = LiquidGlassConfiguration.default
    private var currentEnabled = false
    private var currentWindows: [TrackedTerminalWindow] = []
    private let startedAt = Date()
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try paths.createRequiredDirectories()
            let context = try MetalContext()
            metalContext = context
            captureCoordinator = CaptureCoordinator(context: context)
            overlayManager = OverlayManager(context: context)
        } catch {
            lastError = error.localizedDescription
            logger.log(.error, error.localizedDescription)
        }

        configurationNotificationToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(LiquidGlassVersion.notificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadConfiguration() }
        }
        permissionNotificationToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(LiquidGlassVersion.permissionNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.requestScreenCapturePermission() }
        }

        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(workspaceChanged),
                name: name,
                object: nil
            )
        }

        let heartbeat = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.writeRuntimeStatus() }
        }
        heartbeat.tolerance = 0.2
        RunLoop.main.add(heartbeat, forMode: .common)
        heartbeatTimer = heartbeat

        reloadConfiguration()
        writeRuntimeStatus()
        logger.log(.info, "LiquidGlassAgent \(LiquidGlassVersion.current) started.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        reloadTask?.cancel()
        tracker.stop()
        overlayManager?.stop()
        captureCoordinator?.stop()
        heartbeatTimer?.invalidate()
        if let token = configurationNotificationToken {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        if let token = permissionNotificationToken {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        reconcileTrackingState()
        writeRuntimeStatus()
    }

    private func requestScreenCapturePermission() {
        guard let captureCoordinator else {
            writeRuntimeStatus()
            return
        }
        let granted = captureCoordinator.requestPermission()
        if !granted {
            lastError = "Screen Recording permission has not been granted to LiquidGlass.app."
        } else {
            lastError = nil
            reloadConfiguration()
        }
        writeRuntimeStatus()
    }

    private func reloadConfiguration() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let configuration = self.configurationStore.load()
                async let state = self.stateStore.load()
                let (loadedConfiguration, loadedState) = try await (configuration, state)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    do {
                        self.apply(
                            configuration: try loadedConfiguration.validated(),
                            state: loadedState
                        )
                    } catch {
                        self.record(error: error)
                    }
                }
            } catch {
                await MainActor.run { self.record(error: error) }
            }
        }
    }

    private func apply(
        configuration: LiquidGlassConfiguration,
        state: LiquidGlassState
    ) {
        currentConfiguration = configuration
        currentEnabled = state.enabled && state.transition == nil
        if state.lastError != nil { lastError = state.lastError }
        reconcileTrackingState()
        writeRuntimeStatus()
    }

    private func reconcileTrackingState() {
        let terminalIsRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.Terminal")
            .isEmpty

        guard currentEnabled,
              terminalIsRunning,
              captureCoordinator != nil,
              overlayManager != nil else {
            tracker.stop()
            currentWindows = []
            overlayManager?.stop()
            captureCoordinator?.stop()
            writeRuntimeStatus()
            return
        }

        tracker.start(
            intervalMilliseconds: currentConfiguration.followIntervalMilliseconds,
            updateHandler: { [weak self] windows in self?.consume(windows: windows) }
        )
    }

    private func consume(windows: [TrackedTerminalWindow]) {
        currentWindows = windows
        guard let captureCoordinator, let overlayManager else { return }
        captureCoordinator.reconcile(
            windows: windows,
            configuration: currentConfiguration
        ) { [weak self] in
            guard let self, let coordinator = self.captureCoordinator else { return }
            self.overlayManager?.refresh(captureCoordinator: coordinator)
            self.lastError = coordinator.lastError
            self.writeRuntimeStatus()
        }
        overlayManager.synchronize(
            windows: windows,
            configuration: currentConfiguration,
            captureCoordinator: captureCoordinator
        )
        lastError = captureCoordinator.lastError
    }

    private func record(error: Error) {
        currentEnabled = false
        currentWindows = []
        lastError = error.localizedDescription
        logger.log(.error, error.localizedDescription)
        tracker.stop()
        overlayManager?.stop()
        captureCoordinator?.stop()
        writeRuntimeStatus()
    }

    private func writeRuntimeStatus() {
        let statistics = captureCoordinator?.statistics() ?? (captured: 0, dropped: 0)
        let runtime = AgentRuntimeStatus(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            startedAt: startedAt,
            heartbeatAt: Date(),
            enabled: currentEnabled,
            windowTrackingMode: .coreGraphicsMetadataPolling,
            terminalWindowCount: currentWindows.count,
            overlayCount: overlayManager?.overlayCount ?? 0,
            activeDisplayCaptureCount: captureCoordinator?.activeCaptureCount ?? 0,
            screenCaptureAuthorized: captureCoordinator?.isAuthorized ?? CGPreflightScreenCaptureAccess(),
            metalDeviceName: captureCoordinator?.metalDeviceName ?? metalContext?.device.name,
            capturedFrameCount: statistics.captured,
            droppedFrameCount: statistics.dropped,
            lastError: lastError ?? captureCoordinator?.lastError
        )
        Task {
            do {
                try await runtimeStore.save(runtime)
            } catch {
                logger.log(.error, "Unable to write agent heartbeat: \(error.localizedDescription)")
            }
        }
    }
}
#endif
