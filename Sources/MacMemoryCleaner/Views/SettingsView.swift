import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Cleaning", systemImage: "sparkles") { CleaningSettings() }
            Tab("Auto-Clean", systemImage: "timer") { AutoCleanSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 500)
    }
}

struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.showUsageInMenuBar) private var showUsage: Bool
    @AppStorage(Preference.notifyAfterClean) private var notify: Bool
    @AppStorage(Preference.hotKeyEnabled) private var hotKeyEnabled: Bool
    /// Mirrors the system's login item state. Only the toggle's setter changes it.
    @State private var launchAtLogin = LoginItem.isEnabled || LoginItem.needsApproval
    @State private var loginItemNeedsApproval = LoginItem.needsApproval
    @State private var loginItemError: String?
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: launchAtLoginBinding)
                if loginItemNeedsApproval {
                    LabeledContent("Allow Mac Memory Cleaner in Login Items to finish.") {
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                    .font(.caption)
                }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show memory used in the menu bar", isOn: $showUsage)
                Toggle(isOn: $notify) {
                    Text("Notify when a clean finishes")
                    Text("For shortcut and automatic cleans.")
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
                        Button("Open Notification Settings") { Notifier.openSystemSettings() }
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
            // The user may have changed either setting in System Settings.
            syncLoginItem()
            Task { notificationsDenied = await state.notificationsDenied() }
        }
    }

    /// Writes go to the system and reads come back from it, so syncing the state never
    /// registers or unregisters the login item by accident.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLogin
        } set: { enabled in
            do {
                try LoginItem.setEnabled(enabled)
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
            }
            syncLoginItem()
        }
    }

    private func syncLoginItem() {
        loginItemNeedsApproval = LoginItem.needsApproval
        launchAtLogin = LoginItem.isEnabled || loginItemNeedsApproval
    }
}

struct CleaningSettings: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.flushWrites) private var flushWrites: Bool
    @AppStorage(Preference.pressureSignal) private var pressureSignal: Bool
    @AppStorage(Preference.pressureStrength) private var strength: PressureStrength
    @AppStorage(Preference.purgeDiskCache) private var purge: Bool

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $flushWrites) {
                    Text(CleanStep.flushWrites.title)
                    Text("Saves changes that wait in RAM to the disk, so macOS can release that memory. Runs `sync`.")
                }
                Toggle(isOn: $pressureSignal) {
                    Text(CleanStep.releaseAppMemory.title)
                    Text("Sends the macOS low-memory signal for two seconds. Apps drop caches and return memory they do not need. Runs `memory_pressure`.")
                }
                Picker("Signal strength", selection: $strength) {
                    ForEach(PressureStrength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!pressureSignal)
                .help("Standard sends the warning level. Strong sends the critical level, so apps release more.")
                Toggle(isOn: $purge) {
                    Text(CleanStep.purgeDiskCache.title)
                    Text("Removes cached files from RAM. Apps can open files a little slower right after a clean. Runs `purge`.")
                }
            } header: {
                Text("Clean Memory runs these steps in order")
            }

            Section {
                LabeledContent {
                    adminControls
                } label: {
                    Text("Admin access")
                    Text("Needed for “\(CleanStep.releaseAppMemory.title)” and “\(CleanStep.purgeDiskCache.title)”.")
                }
                if let error = state.adminError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("Setup adds a rule in `/etc/sudoers.d` that lets your account run only `purge` and `memory_pressure` as root without a password. You can remove it here at any time.")
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
    @AppStorage(Preference.autoCleanOnPressure) private var onPressure: Bool
    @AppStorage(Preference.autoCleanBelowThreshold) private var belowThreshold: Bool
    @AppStorage(Preference.autoCleanThreshold) private var threshold: Int
    @AppStorage(Preference.autoCleanMinimumMinutes) private var minimumMinutes: Int
    @AppStorage(Preference.notifyAfterClean) private var notify: Bool

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
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                    Text("1 hour").tag(60)
                }
            } footer: {
                if !notify {
                    Text("To see each result, turn on “Notify when a clean finishes” in General.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(AppInfo.name)
                    .font(.title2.weight(.semibold))
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Free up RAM with one click.")
            HStack(spacing: 12) {
                Link("Source Code", destination: AppInfo.repository)
                Link("Report an Issue", destination: AppInfo.issues)
            }
            .buttonStyle(.bordered)
            VStack(spacing: 2) {
                // Markdown links only work in a literal string, not an interpolated one.
                Text("Inspired by [Windows Memory Cleaner](https://github.com/IgorMundstein/WinMemoryCleaner) by Igor Mundstein.")
                Text("Copyright © 2026 Serge Alex Serbinenko. MIT License.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
