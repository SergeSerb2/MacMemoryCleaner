import SwiftUI

/// The apps holding the most memory, each with a Quit button.
struct TopAppsList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top Apps")
                    .font(.subheadline.weight(.semibold))
                    .help("Quitting a large app you don’t need often frees more memory than a clean.")
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(filePath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Label("Activity Monitor", systemImage: "arrow.up.forward.app")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            if state.topApps.isEmpty {
                Text("Measuring apps…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(state.topApps) { usage in
                        AppRow(usage: usage)
                    }
                }
                .onHover { state.appOrderFrozen = $0 }
            }
        }
    }
}

private struct AppRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let usage: AppMemoryUsage
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: usage.icon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(usage.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(ByteFormat.string(usage.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
            Button {
                quit(force: NSEvent.modifierFlags.contains(.option))
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Quit \(usage.name). Hold Option to force quit.")
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
        .padding(.horizontal, -6)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Quit \(usage.name)") { quit(force: false) }
            Button("Force Quit \(usage.name)…") { quit(force: true) }
        }
        .animation(reduceMotion ? nil : .smooth, value: usage.bytes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.name), \(ByteFormat.string(usage.bytes))")
        .accessibilityAction(named: "Quit") { quit(force: false) }
        .accessibilityAction(named: "Force Quit") { quit(force: true) }
    }

    private func quit(force: Bool) {
        guard !force || confirmForceQuit() else { return }
        state.quit(usage, force: force)
    }

    /// Force quitting loses unsaved work, so ask first, like Force Quit Applications does.
    private func confirmForceQuit() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force “\(usage.name)” to quit?"
        alert.informativeText = "You will lose any unsaved changes."
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
