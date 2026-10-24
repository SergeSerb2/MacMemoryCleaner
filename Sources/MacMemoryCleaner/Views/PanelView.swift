import SwiftUI

/// The window that drops down from the menu bar icon.
struct PanelView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Preference.setupCalloutDismissed) private var setupCalloutDismissed: Bool
    @AppStorage(Preference.pressureSignal) private var pressureSignal: Bool
    @AppStorage(Preference.purgeDiskCache) private var purgeDiskCache: Bool

    /// Offer setup only while an admin step is on and the user has not said "Not Now".
    private var showsSetupCallout: Bool {
        state.adminInstalled == false && !setupCalloutDismissed && (pressureSignal || purgeDiskCache)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MemoryBreakdownView(snapshot: state.snapshot)

            CleanButton()

            if showsSetupCallout {
                SetupCallout()
            }

            Divider()

            TopAppsList()

            Divider()

            HStack {
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                .keyboardShortcut(",")
                Spacer()
                Button("Quit Mac Memory Cleaner") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { state.isPanelVisible = true }
        .onDisappear { state.isPanelVisible = false }
    }
}

private struct CleanButton: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.hotKeyEnabled) private var hotKeyEnabled: Bool
    @AppStorage(Preference.hotKeyLabel) private var hotKeyLabel: String

    var body: some View {
        VStack(spacing: 8) {
            Button {
                state.clean(trigger: .manual)
            } label: {
                HStack(spacing: 8) {
                    if state.isCleaning {
                        ProgressView().controlSize(.small)
                        Text(state.currentStep?.progressTitle ?? "Measuring…")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Clean Memory")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .disabled(state.isCleaning)
            .keyboardShortcut(.defaultAction)

            ResultLine(
                report: state.lastReport,
                isCleaning: state.isCleaning,
                shortcut: hotKeyEnabled && state.hotKeyAvailable ? hotKeyLabel : nil
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ResultLine: View {
    let report: CleanReport?
    let isCleaning: Bool
    let shortcut: String?

    var body: some View {
        Group {
            if isCleaning {
                Text("This can take up to a minute.")
                    .foregroundStyle(.secondary)
            } else if let report {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    VStack(spacing: 2) {
                        headline(report)
                        if let detail = detail(report) {
                            Text(detail).foregroundStyle(.secondary)
                        }
                    }
                    .help(report.trigger.title)
                }
            } else if let shortcut {
                Text("Press \(shortcut) to clean from any app.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .multilineTextAlignment(.center)
    }

    private func headline(_ report: CleanReport) -> some View {
        HStack(spacing: 5) {
            if let failure = report.failures.first {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("“\(failure.step.title)” failed").fontWeight(.medium)
                    .help(failure.message)
            } else if report.freed > 0 {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Freed \(ByteFormat.string(report.freed))").fontWeight(.medium)
            } else {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text("Free memory unchanged")
            }
            Text("· \(report.finished, format: .relative(presentation: .named))")
                .foregroundStyle(.secondary)
        }
    }

    /// Where the memory came from, or why part of the clean was skipped.
    private func detail(_ report: CleanReport) -> String? {
        if report.needsSetup {
            let skipped = report.steps.count { $0.outcome == .needsSetup }
            return "\(skipped) \(skipped == 1 ? "step" : "steps") skipped: no admin access"
        }
        guard report.freed > 0 else { return nil }
        var parts: [String] = []
        if report.cachedFilesCleared > 0 { parts.append("Cached files −\(ByteFormat.string(report.cachedFilesCleared))") }
        if report.appMemoryReleased > 0 { parts.append("app memory −\(ByteFormat.string(report.appMemoryReleased))") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

private struct SetupCallout: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.setupCalloutDismissed) private var dismissed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Allow a full clean")
                    .font(.callout.weight(.semibold))
                Text("Two cleaning steps need admin access. Enter your password once to allow them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = state.adminError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(state.adminBusy ? "Waiting for Password…" : "Set Up…") {
                        Task { await state.installAdminAccess() }
                    }
                    .disabled(state.adminBusy)
                    Button("Not Now") { dismissed = true }
                        .help("You can set up admin access later in Settings › Cleaning.")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
