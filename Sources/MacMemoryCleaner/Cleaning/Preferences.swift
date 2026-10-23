import Carbon.HIToolbox
import Foundation

nonisolated enum PressureStrength: String, Sendable, CaseIterable, Identifiable {
    /// The "warn" level. Apps trim caches they can rebuild cheaply.
    case standard = "warn"
    /// The "critical" level. Apps and idle system services release everything they can.
    case strong = "critical"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .strong: "Strong"
        }
    }
}

/// UserDefaults keys and defaults. Views bind to these with `@AppStorage`.
enum Preference {
    static let showUsageInMenuBar = "showUsageInMenuBar"
    static let notifyAfterClean = "notifyAfterClean"

    static let flushWrites = "step.flushWrites"
    static let pressureSignal = "step.pressureSignal"
    static let pressureStrength = "step.pressureStrength"
    static let purgeDiskCache = "step.purgeDiskCache"

    static let autoCleanOnPressure = "auto.onPressure"
    static let autoCleanBelowThreshold = "auto.belowThreshold"
    static let autoCleanThreshold = "auto.thresholdPercent"
    static let autoCleanMinimumMinutes = "auto.minimumMinutes"

    static let hotKeyEnabled = "hotKey.enabled"
    static let hotKeyCode = "hotKey.keyCode"
    static let hotKeyModifiers = "hotKey.modifiers"
    static let hotKeyLabel = "hotKey.label"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showUsageInMenuBar: true,
            notifyAfterClean: true,
            flushWrites: true,
            pressureSignal: true,
            pressureStrength: PressureStrength.strong.rawValue,
            purgeDiskCache: true,
            autoCleanOnPressure: true,
            autoCleanBelowThreshold: false,
            autoCleanThreshold: 20,
            autoCleanMinimumMinutes: 10,
            hotKeyEnabled: true,
            hotKeyCode: kVK_ANSI_M,
            hotKeyModifiers: controlKey | optionKey | cmdKey,
            hotKeyLabel: "⌃⌥⌘M",
        ])
    }
}

extension UserDefaults {
    var cleanOptions: CleanOptions {
        CleanOptions(
            flushWrites: bool(forKey: Preference.flushWrites),
            pressureSignal: bool(forKey: Preference.pressureSignal) ? PressureStrength(rawValue: string(forKey: Preference.pressureStrength) ?? "") ?? .strong : nil,
            purgeDiskCache: bool(forKey: Preference.purgeDiskCache)
        )
    }
}
