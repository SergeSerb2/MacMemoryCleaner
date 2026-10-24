import SwiftUI

/// The headline number, the stacked memory bar, and its legend.
struct MemoryBreakdownView: View {
    let snapshot: MemorySnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Memory Used")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(ByteFormat.string(snapshot.used))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .contentTransition(reduceMotion ? .identity : .numericText())
                        Text("of \(ByteFormat.string(snapshot.total))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Spacer()
                PressureBadge(pressure: snapshot.pressure)
            }
            .animation(reduceMotion ? nil : .smooth, value: snapshot.used)

            MemoryBar(snapshot: snapshot)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    LegendItem(segment: .app, value: snapshot.appMemory)
                    LegendItem(segment: .cached, value: snapshot.cachedFiles)
                }
                GridRow {
                    LegendItem(segment: .wired, value: snapshot.wired)
                    LegendItem(segment: .free, value: snapshot.free)
                }
                GridRow {
                    LegendItem(segment: .compressed, value: snapshot.compressed)
                    LegendItem(segment: .swap, value: snapshot.swapUsed)
                }
            }
            .font(.caption)
        }
    }
}

enum MemorySegment {
    case app, wired, compressed, cached, free, swap

    var title: String {
        switch self {
        case .app: "App Memory"
        case .wired: "Wired"
        case .compressed: "Compressed"
        case .cached: "Cached Files"
        case .free: "Free"
        case .swap: "Swap Used"
        }
    }

    var color: Color {
        switch self {
        case .app: .blue
        case .wired: .orange
        case .compressed: .purple
        case .cached: .teal
        case .free, .swap: .secondary
        }
    }

    var help: String {
        switch self {
        case .app: "Memory apps have allocated for their own data."
        case .wired: "Memory the system keeps in RAM at all times."
        case .compressed: "RAM holding compressed copies of memory that was not used recently."
        case .cached: "Files kept in RAM so they open fast. macOS can drop these at any time."
        case .free: "RAM that holds nothing at all."
        case .swap: "Memory macOS moved to the disk because RAM ran short."
        }
    }
}

private struct MemoryBar: View {
    let snapshot: MemorySnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let segments: [(MemorySegment, UInt64)] = [
            (.app, snapshot.appMemory),
            (.wired, snapshot.wired),
            (.compressed, snapshot.compressed),
            (.cached, snapshot.cachedFiles),
        ]
        GeometryReader { proxy in
            let total = max(Double(snapshot.total), 1)
            HStack(spacing: 1.5) {
                ForEach(segments, id: \.0) { segment, bytes in
                    Rectangle()
                        .fill(segment.color.gradient)
                        .frame(width: max(0, proxy.size.width * Double(bytes) / total - 1.5))
                }
                Spacer(minLength: 0)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: snapshot)
        }
        .frame(height: 12)
        .background(.quaternary)
        .clipShape(.capsule)
        .accessibilityElement()
        .accessibilityLabel("Memory used: \(ByteFormat.string(snapshot.used)) of \(ByteFormat.string(snapshot.total))")
    }
}

private struct LegendItem: View {
    let segment: MemorySegment
    let value: UInt64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            switch segment {
            case .free:
                Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 8, height: 8)
            case .swap:
                Image(systemName: "internaldrive").font(.system(size: 8)).frame(width: 8, height: 8)
                    .foregroundStyle(.secondary)
            default:
                Circle().fill(segment.color).frame(width: 8, height: 8)
            }
            Text(segment.title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(ByteFormat.string(value))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .help(segment.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(segment.title), \(ByteFormat.string(value))")
        .accessibilityHint(segment.help)
    }
}

struct PressureBadge: View {
    let pressure: MemoryPressure

    private var color: Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(pressure.title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: .capsule)
        .help("Memory pressure, as macOS reports it.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory pressure: \(pressure.title)")
    }
}
