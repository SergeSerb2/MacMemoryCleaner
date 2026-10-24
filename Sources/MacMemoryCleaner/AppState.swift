import AppKit
import Observation

/// The single source of truth for the menu bar panel and the settings window.
@Observable
final class AppState {
    private(set) var snapshot = MemorySnapshot.current() ?? .empty
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
            // The panel can close under the pointer (for example for the Force Quit alert),
            // and then no hover-end event arrives.
            guard isPanelVisible else { appOrderFrozen = false; return }
            Task {
                await refresh(includeApps: true)
                // Setup may have happened elsewhere, for example with `--setup`.
                if !adminBusy { await refreshAdminStatus() }
            }
        }
    }

    /// While the pointer is over the app list, rows keep their order, so a click never
    /// lands on an app that just moved under the pointer.
    var appOrderFrozen = false

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Created in `start()`: the notification center only works inside the app bundle.
    @ObservationIgnored private var notifier: Notifier?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Set by `showDemoData()`. Stops live data from replacing the sample data.
    @ObservationIgnored private var isDemo = false
    /// A clean cannot raise available memory much (purged cache only becomes free memory),
    /// so after a threshold clean, wait until available memory recovers before the next.
    @ObservationIgnored private var thresholdArmed = true
    /// Set when pressure arrives during the cool-down. Pressure events mark a change of level
    /// only, so pressure that began during the cool-down and never let go would otherwise
    /// never get its clean. Cleared by any clean that runs.
    @ObservationIgnored private var pressurePending = false

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
        Task {
            await refreshAdminStatus()
            // Ask for notification permission now, in context, rather than in the middle of
            // the first automatic clean.
            if defaults[Preference.notifyAfterClean] { _ = await notifier?.requestAuthorization() }
        }
    }

    // MARK: Cleaning

    /// `minimumGap` is for automatic cleans: skip if any clean finished within that time.
    func clean(trigger: CleanTrigger, minimumGap: TimeInterval? = nil) {
        guard !isCleaning else { return }
        isCleaning = true
        Log.app.info("Clean requested. \(trigger.title, privacy: .public)")
        Task {
            let result = await Cleaner.clean(options: defaults.cleanOptions, trigger: trigger, minimumGap: minimumGap) { step in
                self.currentStep = step
            }
            // Done before the refresh and the notification below, which can wait a long
            // time (for example on an unanswered notification permission prompt).
            currentStep = nil
            isCleaning = false
            let report: CleanReport
            switch result {
            case .finished(let finished):
                report = finished
            case .busy:
                Log.app.info("Clean skipped: another clean is running")
                return
            case .tooSoon:
                Log.app.info("Clean skipped: another clean just finished")
                return
            }
            // Only a clean that really ran waits for available memory to recover.
            if case .lowAvailableMemory = trigger { thresholdArmed = false }
            pressurePending = false
            lastReport = report
            let steps = report.steps.map { "\($0.step.rawValue)=\($0.outcome)" }.joined(separator: " ")
            Log.app.info("Clean finished: freed \(report.freed) bytes in \(report.duration, format: .fixed(precision: 1)) s; \(steps, privacy: .public)")
            if report.needsSetup {
                adminInstalled = false
            } else if report.steps.contains(where: { $0.step.needsAdmin && $0.outcome == .done }) {
                adminInstalled = true
            }
            await refresh(includeApps: isPanelVisible)
            // The panel already shows the result, so only notify when it is closed.
            if defaults[Preference.notifyAfterClean] && !isPanelVisible {
                await notifier?.post(report)
            }
        }
    }

    // MARK: Apps

    func quit(_ usage: AppMemoryUsage, force: Bool = false) {
        guard let app = usage.app else { return }
        if force {
            app.forceTerminate()
        } else {
            app.terminate()
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
        } catch AdminAccess.SetupError.canceled {
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
        guard defaults[Preference.hotKeyEnabled] else {
            hotKey.unregister()
            hotKeyAvailable = true
            return
        }
        hotKeyAvailable = hotKey.register(
            keyCode: defaults[Preference.hotKeyCode],
            carbonModifiers: defaults[Preference.hotKeyModifiers]
        )
        Log.app.info("Hot key \(self.defaults[Preference.hotKeyLabel], privacy: .public) registered: \(self.hotKeyAvailable)")
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
                self.checkPendingPressure()
                self.checkAvailableMemoryThreshold()
                try? await Task.sleep(for: .seconds(visible ? 2 : 5))
            }
        }
    }

    func refresh(includeApps: Bool) async {
        guard !isDemo else { return }
        if let current = MemorySnapshot.current(), current != snapshot { snapshot = current }
        guard includeApps else { return }
        let fresh = await AppMemorySampler.topApps(limit: 6)
        if appOrderFrozen && !topApps.isEmpty {
            // Update the numbers in place. Apps that quit drop out; new ones wait.
            topApps = topApps.compactMap { row in
                fresh.first { $0.id == row.id } ?? (row.app?.isTerminated == false ? row : nil)
            }
        } else {
            topApps = fresh
        }
    }

    private func startPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, unowned source] in
            Log.app.info("Memory pressure event: \(source.data.rawValue)")
            guard let self, self.defaults[Preference.autoCleanOnPressure] else { return }
            // Events during a clean come from the clean's own signal. Just after a clean,
            // macOS reports the real level again as the simulated one ends; that echo is
            // not new pressure either.
            guard !self.isCleaning else { return }
            if let last = CleanLock.lastCleanFinished, Date.now.timeIntervalSince(last) < 30 { return }
            if !self.autoClean(trigger: .memoryPressure) { self.pressurePending = true }
        }
        source.activate()
        pressureSource = source
    }

    /// Runs the clean that pressure during the cool-down asked for, once the cool-down ends,
    /// if the pressure is still there. Sustained pressure gets one clean, not one per cool-down.
    private func checkPendingPressure() {
        guard pressurePending else { return }
        guard defaults[Preference.autoCleanOnPressure], snapshot.pressure != .normal else {
            pressurePending = false
            return
        }
        autoClean(trigger: .memoryPressure, quietlySkip: true)
    }

    private func checkAvailableMemoryThreshold() {
        guard defaults[Preference.autoCleanBelowThreshold] else { return }
        let threshold = defaults[Preference.autoCleanThreshold]
        if snapshot.availablePercent >= threshold + 5 { thresholdArmed = true }
        guard thresholdArmed, snapshot.availablePercent < threshold else { return }
        autoClean(trigger: .lowAvailableMemory(percent: snapshot.availablePercent), quietlySkip: true)
    }

    /// Starts a clean unless one ran recently. Every clean counts for the cool-down,
    /// including cleans from the command line. Returns false during the cool-down.
    @discardableResult
    private func autoClean(trigger: CleanTrigger, quietlySkip: Bool = false) -> Bool {
        guard !isCleaning else { return true }
        let minimumGap = TimeInterval(max(defaults[Preference.autoCleanMinimumMinutes], 1) * 60)
        // A cheap early check. Cleaner checks again while it holds the lock.
        if let last = CleanLock.lastCleanFinished, Date.now.timeIntervalSince(last) < minimumGap {
            if !quietlySkip {
                let minutes = Int(minimumGap / 60)
                Log.app.info("Auto-clean waits: the last clean finished less than \(minutes) \(minutes == 1 ? "minute" : "minutes") ago")
            }
            return false
        }
        clean(trigger: trigger, minimumGap: minimumGap)
        return true
    }

    // MARK: Demo data

    /// Fills the state with sample data for an 8 GB Mac, two minutes after a clean, so the
    /// README screenshots show no one's real apps.
    func showDemoData() {
        isDemo = true
        let mb: UInt64 = 1_048_576
        let after = MemorySnapshot(
            total: 8192 * mb, free: 1640 * mb, appMemory: 3690 * mb, wired: 1330 * mb,
            compressed: 920 * mb, cachedFiles: 610 * mb, swapUsed: 1210 * mb, swapTotal: 2048 * mb,
            availablePercent: 28, pressure: .normal
        )
        var before = after
        before.free = 290 * mb
        before.cachedFiles = 1960 * mb
        snapshot = after
        lastReport = CleanReport(
            trigger: .manual, finished: .now.addingTimeInterval(-120), duration: 6.4,
            before: before, after: after,
            steps: CleanStep.allCases.map { StepResult(step: $0, outcome: .done) }
        )
        adminInstalled = true
        topApps = [
            ("Safari", "/Applications/Safari.app", 1830),
            ("Mail", "/System/Applications/Mail.app", 612),
            ("Photos", "/System/Applications/Photos.app", 548),
            ("Music", "/System/Applications/Music.app", 391),
            ("Messages", "/System/Applications/Messages.app", 287),
            ("Notes", "/System/Applications/Notes.app", 204),
        ].enumerated().map { index, app in
            AppMemoryUsage(sampleID: pid_t(index + 1), name: app.0, appPath: app.1, bytes: app.2 * mb)
        }
    }
}
