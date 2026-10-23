import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Cleaning", systemImage: "sparkles") { CleaningSettings() }
            Tab("Auto-Clean", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") { AutoCleanSettings() }
        }
        .frame(width: 500)
    }
}

struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.showUsageInMenuBar) private var showUsage = true
    @AppStorage(Preference.notifyAfterClean) private var notify = true
    @AppStorage(Preference.hotKeyEnabled) private var hotKeyEnabled = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if LoginItem.needsApproval {
                    LabeledContent("macOS needs you to allow this app in Login Items.") {
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                    }
                    .font(.caption)
                }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show memory used in the menu bar", isOn: $showUsage)
                Toggle(isOn: $notify) {
                    Text("Notify when a clean finishes")
                    Text("For cleans that run while the panel is closed: shortcut and automatic cleans.")
                }
                .onChange(of: notify) { _, enabled in
                    guard enabled else { return }
                    Task {
                        _ = await state.requestNotificationPermission()
                        notificationsDenied = await state.notificationsDenied()
                    }
                }
                if notify && notificationsDenied {
                    LabeledContent("Notifications are off for this app in System Settings.") {
                        Button("Turn On…") { Notifier.openSystemSettings() }
                    }
                    .font(.caption)
                }
            }

            Section("Keyboard Shortcut") {
                Toggle("Clean memory from any app", isOn: $hotKeyEnabled)
                    .onChange(of: hotKeyEnabled) { state.applyHotKeyPreference() }
                LabeledContent("Shortcut") {
                    ShortcutRecorder()
                }
                .disabled(!hotKeyEnabled)
                if hotKeyEnabled && !state.hotKeyAvailable {
                    Label("Another app already uses this shortcut. Choose a different one.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .task { notificationsDenied = await state.notificationsDenied() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin = LoginItem.isEnabled
            Task { notificationsDenied = await state.notificationsDenied() }
        }
    }
}

struct CleaningSettings: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.flushWrites) private var flushWrites = true
    @AppStorage(Preference.pressureSignal) private var pressureSignal = true
    @AppStorage(Preference.pressureStrength) private var strength = PressureStrength.strong
    @AppStorage(Preference.purgeDiskCache) private var purge = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $flushWrites) {
                    Text("Flush pending writes")
                    Text("Saves changes that wait in RAM to the disk, so macOS can release that memory. Runs `sync`.")
                }
                Toggle(isOn: $pressureSignal) {
                    Text("Ask apps to release memory")
                    Text("Sends the macOS low-memory signal for two seconds. Apps and idle system services drop caches and return unused memory. Runs `memory_pressure`.")
                }
                Picker("Signal strength", selection: $strength) {
                    ForEach(PressureStrength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!pressureSignal)
                Toggle(isOn: $purge) {
                    Text("Purge disk cache")
                    Text("Removes cached files from RAM. Apps can open files a little slower right after a clean. Runs `purge`.")
                }
            } header: {
                Text("Clean Memory runs these steps in order")
            }

            Section {
                LabeledContent {
                    adminControls
                } label: {
                    Text("Deep clean")
                    Text("The last two steps need admin rights.")
                }
                if let error = state.adminError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Admin Access")
            } footer: {
                Text("Setup adds `/etc/sudoers.d/macmemorycleaner`. That rule lets your account run only `purge` and `memory_pressure` as root without a password. You can remove it here at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var adminControls: some View {
        HStack(spacing: 10) {
            switch state.adminInstalled {
            case nil:
                ProgressView().controlSize(.small)
            case true?:
                Label("On", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button("Remove…") { Task { await state.removeAdminAccess() } }
                    .disabled(state.adminBusy)
            case false?:
                Text("Off").foregroundStyle(.secondary)
                Button("Set Up…") { Task { await state.installAdminAccess() } }
                    .disabled(state.adminBusy)
            }
        }
    }
}

struct AutoCleanSettings: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.autoCleanOnPressure) private var onPressure = true
    @AppStorage(Preference.autoCleanBelowThreshold) private var belowThreshold = false
    @AppStorage(Preference.autoCleanThreshold) private var threshold = 20
    @AppStorage(Preference.autoCleanMinimumMinutes) private var minimumMinutes = 10

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $onPressure) {
                    Text("When macOS reports memory pressure")
                    Text("Cleans as soon as memory runs short, before macOS moves more memory to swap.")
                }
                Toggle(isOn: $belowThreshold) {
                    Text("When available memory falls below \(threshold)%")
                    Text("Available memory is free RAM plus cached files: what macOS can hand out without compressing or swapping. Right now: \(state.snapshot.availablePercent)%.")
                }
                Slider(
                    value: Binding(get: { Double(threshold) }, set: { threshold = Int($0) }),
                    in: 5...50,
                    step: 5
                ) {
                    Text("Threshold")
                } minimumValueLabel: {
                    Text("5%")
                } maximumValueLabel: {
                    Text("50%")
                }
                .disabled(!belowThreshold)
            } header: {
                Text("Clean automatically")
            }

            Section {
                Picker("Wait between automatic cleans", selection: $minimumMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            } footer: {
                Text("Automatic cleans run quietly. Turn on notifications in General to see each result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
