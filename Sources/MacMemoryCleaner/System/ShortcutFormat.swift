import AppKit
import Carbon.HIToolbox

/// Converts between AppKit modifier flags, Carbon modifier masks, and the ⌃⌥⇧⌘ label.
enum ShortcutFormat {
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return result
    }

    static func label(carbonModifiers: Int, key: String) -> String {
        var label = ""
        if carbonModifiers & controlKey != 0 { label += "⌃" }
        if carbonModifiers & optionKey != 0 { label += "⌥" }
        if carbonModifiers & shiftKey != 0 { label += "⇧" }
        if carbonModifiers & cmdKey != 0 { label += "⌘" }
        return label + key
    }

    static func keyName(for event: NSEvent) -> String {
        let keyCode = Int(event.keyCode)
        if let index = functionKeys.firstIndex(of: keyCode) { return "F\(index + 1)" }
        switch keyCode {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    /// "⌃⌥⌘M" becomes "Control-Option-Command-M", for VoiceOver.
    static func spokenLabel(_ label: String) -> String {
        let names: [Character: String] = ["⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command"]
        let modifiers = label.prefix { names[$0] != nil }.compactMap { names[$0] }
        return (modifiers + [String(label.dropFirst(modifiers.count))]).joined(separator: "-")
    }

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys.contains(Int(keyCode))
    }

    private static let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]
}
