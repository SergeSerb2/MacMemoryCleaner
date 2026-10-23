import AppKit
import Observation

/// The single source of truth for the menu bar panel and the settings window.
@Observable
final class AppState {
    private(set) var snapshot = MemorySnapshot.current()
    private(set) var topApps: [AppMemoryUsage] = []
    private(set) var isCleaning = false
    private(set) var currentStep: CleanStep?
    private(set) var lastReport: CleanReport?

    /// `nil` until the first check finishes.
    private(set) var adminInstalled: Bool?
    private(set) var adminBusy = false
    var adminError: String?

    private(set) var hotKeyAvailable = true

    /// The panel only samples per-app memory while someone is looking at it.
    var isPanelVisible = false {
        didSet {
            guard isPanelVisible != oldValue else { return }
            if isPanelVisible { Task { await refresh(includeApps: true) } }
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Created in `start()`: the notification center only works inside the app bundle.
    @ObservationIgnored private var notifier: Notifier?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var lastCleanFinished: Date?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        Preference.registerDefaults()
    }

    /// Starts timers, the hot key, and the pressure monitor. The command-line mode never calls this.
    func start() {
        // UNUserNotificationCenter throws outside an app bundle, e.g. for a bare `swift run`.
        if Bundle.main.bundleIdentifier != nil { notifier = Notifier() }
        hotKey = GlobalHotKey { [weak self] in self?.clean(trigger: .hotKey) }
        applyHotKeyPreference()
        startPressureMonitor()
        startPolling()
        Task { await refreshAdminStatus() }
    }

    // MARK: Cleaning

    func clean(trigger: CleanTrigger) {
        guard !isCleaning else { return }
        isCleaning = true
        Log.app.info("Clean started: \(trigger.title, privacy: .public)")
        Task {
            let report = await Cleaner.clean(options: defaults.cleanOptions, trigger: trigger) { step in
                self.currentStep = step
            }
            lastReport = report
            lastCleanFinished = report.finished
            let steps = report.steps.map { "\($0.step.rawValue)=\($0.outcome)" }.joined(separator: " ")
            Log.app.info("Clean finished: freed \(report.freed) bytes in \(report.duration, format: .fixed(precision: 1)) s; \(steps, privacy: .public)")
            currentStep = nil
            isCleaning = false
            if report.needsSetup { adminInstalled = false }
            await refresh(includeApps: isPanelVisible)
            // The panel already shows the result, so only notify when it is closed.
            if defaults.bool(forKey: Preference.notifyAfterClean) && !isPanelVisible {
                await notifier?.post(report)
            }
        }
    }

    // MARK: Apps

    func quit(_ usage: AppMemoryUsage, force: Bool = false) {
        if force {
            usage.app.forceTerminate()
        } else {
            usage.app.terminate()
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await refresh(includeApps: true)
        }
    }

    // MARK: Admin access

    func refreshAdminStatus() async {
        adminInstalled = await AdminAccess.isInstalled()
        Log.app.info("Admin access installed: \(self.adminInstalled ?? false)")
    }

    func installAdminAccess() async {
        await changeAdminAccess { try await AdminAccess.install() }
    }

    func removeAdminAccess() async {
        await changeAdminAccess { try await AdminAccess.uninstall() }
    }

    private func changeAdminAccess(_ change: () async throws -> Void) async {
        adminBusy = true
        adminError = nil
        do {
            try await change()
        } catch AdminAccess.SetupError.cancelled {
            // The user closed the password prompt. Nothing to report.
        } catch {
            adminError = error.localizedDescription
        }
        await refreshAdminStatus()
        adminBusy = false
    }

    // MARK: Notifications

    func requestNotificationPermission() async -> Bool {
        await notifier?.requestAuthorization() ?? false
    }

    func notificationsDenied() async -> Bool {
        await notifier?.isDenied() ?? false
    }

    // MARK: Hot key

    func applyHotKeyPreference() {
        guard let hotKey else { return }
        guard defaults.bool(forKey: Preference.hotKeyEnabled) else {
            hotKey.unregister()
            hotKeyAvailable = true
            return
        }
        hotKeyAvailable = hotKey.register(
            keyCode: defaults.integer(forKey: Preference.hotKeyCode),
            carbonModifiers: defaults.integer(forKey: Preference.hotKeyModifiers)
        )
        Log.app.info("Hot key \(self.defaults.string(forKey: Preference.hotKeyLabel) ?? "", privacy: .public) registered: \(self.hotKeyAvailable)")
    }

    /// Lets the shortcut recorder capture the current shortcut instead of triggering it.
    func suspendHotKey() {
        hotKey?.unregister()
    }

    // MARK: Monitoring

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let visible = self.isPanelVisible
                await self.refresh(includeApps: visible)
                self.checkAvailableMemoryThreshold()
                try? await Task.sleep(for: .seconds(visible ? 2 : 5))
            }
        }
    }

    func refresh(includeApps: Bool) async {
        let current = MemorySnapshot.current()
        if current != snapshot { snapshot = current }
        if includeApps { topApps = await AppMemorySampler.topApps(limit: 6) }
    }

    private func startPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, unowned source] in
            Log.app.info("Memory pressure event: \(source.data.rawValue)")
            guard let self, self.defaults.bool(forKey: Preference.autoCleanOnPressure) else { return }
            self.autoClean(trigger: .memoryPressure)
        }
        source.activate()
        pressureSource = source
    }

    private func checkAvailableMemoryThreshold() {
        guard defaults.bool(forKey: Preference.autoCleanBelowThreshold) else { return }
        let threshold = defaults.integer(forKey: Preference.autoCleanThreshold)
        if snapshot.availablePercent < threshold {
            autoClean(trigger: .lowAvailableMemory(percent: snapshot.availablePercent))
        }
    }

    private func autoClean(trigger: CleanTrigger) {
        // Our own pressure signal also reaches this app, which is one more reason for the
        // isCleaning guard and the cool-down.
        guard !isCleaning else { return }
        let minimumGap = TimeInterval(max(defaults.integer(forKey: Preference.autoCleanMinimumMinutes), 1) * 60)
        if let lastCleanFinished, Date.now.timeIntervalSince(lastCleanFinished) < minimumGap {
            Log.app.info("Auto-clean skipped: last clean was under \(Int(minimumGap / 60)) minutes ago")
            return
        }
        clean(trigger: trigger)
    }
}
