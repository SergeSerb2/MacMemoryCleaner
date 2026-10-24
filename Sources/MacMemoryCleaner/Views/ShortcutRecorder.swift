import Carbon.HIToolbox
import SwiftUI

/// A button that records the next key combination you press.
struct ShortcutRecorder: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.hotKeyCode) private var keyCode: Int
    @AppStorage(Preference.hotKeyModifiers) private var modifiers: Int
    @AppStorage(Preference.hotKeyLabel) private var label: String
    @State private var isRecording = false
    @State private var monitor: Any?

    @State private var rejected = false

    private var isDefault: Bool {
        keyCode == Preference.hotKeyCode.defaultValue && modifiers == Preference.hotKeyModifiers.defaultValue
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(isRecording ? "Type a shortcut…" : label)
                        .monospaced(!isRecording)
                        .frame(minWidth: 120)
                }
                .help(isRecording ? "Press Escape to cancel." : "Click, then press the new shortcut.")
                .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut: \(ShortcutFormat.spokenLabel(label))")
                .accessibilityHint("Activate, then press the new shortcut.")
                if !isDefault && !isRecording {
                    Button("Reset", action: resetToDefault)
                        .help("Go back to \(Preference.hotKeyLabel.defaultValue).")
                }
            }
            if rejected {
                Text("Use ⌃ with another modifier, or ⌥⌘, so the shortcut can’t replace one you type or use in apps.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func resetToDefault() {
        rejected = false
        keyCode = Preference.hotKeyCode.defaultValue
        modifiers = Preference.hotKeyModifiers.defaultValue
        label = Preference.hotKeyLabel.defaultValue
        state.applyHotKeyPreference()
    }

    private func startRecording() {
        state.suspendHotKey()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                rejected = false
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            // A global shortcut takes the key combination from every app. ⌘ alone would take
            // standard shortcuts such as ⌘W; ⌥ or ⌃ alone can type characters or edit text.
            // ⌃ plus another modifier, or ⌥⌘, is safe. Function keys may stand alone.
            let controlCombo = flags.contains(.control) && flags.subtracting(.control) != []
            let optionCommand = flags.isSuperset(of: [.option, .command])
            guard controlCombo || optionCommand || ShortcutFormat.isFunctionKey(event.keyCode) else {
                rejected = true
                NSSound.beep()
                return nil
            }
            rejected = false
            keyCode = Int(event.keyCode)
            modifiers = ShortcutFormat.carbonModifiers(flags)
            label = ShortcutFormat.label(carbonModifiers: modifiers, key: ShortcutFormat.keyName(for: event))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        state.applyHotKeyPreference()
    }
}
