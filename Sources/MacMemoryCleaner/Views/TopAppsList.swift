import SwiftUI

/// The apps holding the most memory, each with a Quit button.
struct TopAppsList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top Apps")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Quitting frees the most")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 2)

            if state.topApps.isEmpty {
                Text("Measuring apps…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(state.topApps) { usage in
                    AppRow(usage: usage)
                }
            }
        }
    }
}

private struct AppRow: View {
    @Environment(AppState.self) private var state
    let usage: AppMemoryUsage
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: usage.app.icon ?? NSImage(named: NSImage.applicationIconName)!)
                .resizable()
                .frame(width: 20, height: 20)
            Text(usage.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(ByteFormat.string(usage.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Button {
                state.quit(usage, force: NSEvent.modifierFlags.contains(.option))
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            .help("Quit \(usage.name). Hold Option to force quit.")
            .accessibilityLabel("Quit \(usage.name)")
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
        .padding(.horizontal, -6)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Quit \(usage.name)") { state.quit(usage) }
            Button("Force Quit \(usage.name)") { state.quit(usage, force: true) }
        }
        .animation(.smooth, value: usage.bytes)
    }
}
