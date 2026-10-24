import Carbon.HIToolbox
import SwiftUI

/// A UserDefaults key and its default value, so each default is written exactly once.
nonisolated struct PreferenceKey<Value: Sendable>: Sendable {
    let name: String
    let defaultValue: Value
}

/// Every setting the app stores. Views bind with `@AppStorage(Preference.someKey)`;
/// other code reads `UserDefaults.standard[Preference.someKey]`.
nonisolated enum Preference {
    static let showUsageInMenuBar = PreferenceKey(name: "showUsageInMenuBar", defaultValue: true)
    static let notifyAfterClean = PreferenceKey(name: "notifyAfterClean", defaultValue: true)
    static let setupCalloutDismissed = PreferenceKey(name: "panel.setupCalloutDismissed", defaultValue: false)

    static let flushWrites = PreferenceKey(name: "step.flushWrites", defaultValue: true)
    static let pressureSignal = PreferenceKey(name: "step.pressureSignal", defaultValue: true)
    static let pressureStrength = PreferenceKey(name: "step.pressureStrength", defaultValue: PressureStrength.strong)
    static let purgeDiskCache = PreferenceKey(name: "step.purgeDiskCache", defaultValue: true)

    static let autoCleanOnPressure = PreferenceKey(name: "auto.onPressure", defaultValue: true)
    static let autoCleanBelowThreshold = PreferenceKey(name: "auto.belowThreshold", defaultValue: false)
    static let autoCleanThreshold = PreferenceKey(name: "auto.thresholdPercent", defaultValue: 20)
    static let autoCleanMinimumMinutes = PreferenceKey(name: "auto.minimumMinutes", defaultValue: 10)

    static let hotKeyEnabled = PreferenceKey(name: "hotKey.enabled", defaultValue: true)
    static let hotKeyCode = PreferenceKey(name: "hotKey.keyCode", defaultValue: kVK_ANSI_M)
    static let hotKeyModifiers = PreferenceKey(name: "hotKey.modifiers", defaultValue: controlKey | optionKey | cmdKey)
    static let hotKeyLabel = PreferenceKey(name: "hotKey.label", defaultValue: "⌃⌥⌘M")

    /// Makes the defaults above visible to plain `UserDefaults` reads.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showUsageInMenuBar.name: showUsageInMenuBar.defaultValue,
            notifyAfterClean.name: notifyAfterClean.defaultValue,
            setupCalloutDismissed.name: setupCalloutDismissed.defaultValue,
            flushWrites.name: flushWrites.defaultValue,
            pressureSignal.name: pressureSignal.defaultValue,
            pressureStrength.name: pressureStrength.defaultValue.rawValue,
            purgeDiskCache.name: purgeDiskCache.defaultValue,
            autoCleanOnPressure.name: autoCleanOnPressure.defaultValue,
            autoCleanBelowThreshold.name: autoCleanBelowThreshold.defaultValue,
            autoCleanThreshold.name: autoCleanThreshold.defaultValue,
            autoCleanMinimumMinutes.name: autoCleanMinimumMinutes.defaultValue,
            hotKeyEnabled.name: hotKeyEnabled.defaultValue,
            hotKeyCode.name: hotKeyCode.defaultValue,
            hotKeyModifiers.name: hotKeyModifiers.defaultValue,
            hotKeyLabel.name: hotKeyLabel.defaultValue,
        ])
    }
}

nonisolated extension UserDefaults {
    subscript(key: PreferenceKey<Bool>) -> Bool { object(forKey: key.name) as? Bool ?? key.defaultValue }
    subscript(key: PreferenceKey<Int>) -> Int { object(forKey: key.name) as? Int ?? key.defaultValue }
    subscript(key: PreferenceKey<String>) -> String { string(forKey: key.name) ?? key.defaultValue }
    subscript(key: PreferenceKey<PressureStrength>) -> PressureStrength {
        string(forKey: key.name).flatMap(PressureStrength.init(rawValue:)) ?? key.defaultValue
    }

    /// The clean steps as chosen in Settings › Cleaning.
    var cleanOptions: CleanOptions {
        CleanOptions(
            flushWrites: self[Preference.flushWrites],
            pressureSignal: self[Preference.pressureSignal] ? self[Preference.pressureStrength] : nil,
            purgeDiskCache: self[Preference.purgeDiskCache]
        )
    }
}

extension AppStorage {
    init(_ key: PreferenceKey<Value>) where Value == Bool { self.init(wrappedValue: key.defaultValue, key.name) }
    init(_ key: PreferenceKey<Value>) where Value == Int { self.init(wrappedValue: key.defaultValue, key.name) }
    init(_ key: PreferenceKey<Value>) where Value == String { self.init(wrappedValue: key.defaultValue, key.name) }
    init(_ key: PreferenceKey<Value>) where Value: RawRepresentable, Value.RawValue == String {
        self.init(wrappedValue: key.defaultValue, key.name)
    }
}
