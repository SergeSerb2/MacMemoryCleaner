import SwiftUI

/// The window that drops down from the menu bar icon.
struct PanelView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MemoryBreakdownView(snapshot: state.snapshot)

            CleanButton()

            if state.adminInstalled == false {
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
                Button("Quit") { NSApp.terminate(nil) }
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
    @AppStorage(Preference.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(Preference.hotKeyLabel) private var hotKeyLabel = ""

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

            ResultLine(report: state.lastReport, isCleaning: state.isCleaning, hint: hotKeyEnabled ? hotKeyLabel : nil)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct ResultLine: View {
    let report: CleanReport?
    let isCleaning: Bool
    let hint: String?

    var body: some View {
        Group {
            if isCleaning {
                Text("This can take up to a minute.")
                    .foregroundStyle(.secondary)
            } else if let report {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    HStack(spacing: 5) {
                        if !report.failures.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("A step failed: \(report.failures[0])").lineLimit(1)
                        } else if report.freed > 0 {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Freed \(ByteFormat.string(report.freed))").fontWeight(.medium)
                        } else {
                            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                            Text("Nothing more to free")
                        }
                        Text("· \(report.finished, format: .relative(presentation: .named))")
                            .foregroundStyle(.secondary)
                    }
                    .help(report.trigger.title)
                }
            } else if let hint {
                Text("Press \(hint) to clean from any app.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .monospacedDigit()
    }
}

private struct SetupCallout: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Turn on deep clean")
                    .font(.callout.weight(.semibold))
                Text("Purging caches needs admin rights. Enter your password once, and the app never asks again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = state.adminError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(state.adminBusy ? "Waiting for password…" : "Set Up…") {
                    Task { await state.installAdminAccess() }
                }
                .controlSize(.small)
                .disabled(state.adminBusy)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
    }
}
