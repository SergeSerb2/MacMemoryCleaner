import Carbon.HIToolbox
import SwiftUI

/// A button that records the next key combination you press.
struct ShortcutRecorder: View {
    @Environment(AppState.self) private var state
    @AppStorage(Preference.hotKeyCode) private var keyCode = kVK_ANSI_M
    @AppStorage(Preference.hotKeyModifiers) private var modifiers = controlKey | optionKey | cmdKey
    @AppStorage(Preference.hotKeyLabel) private var label = "⌃⌥⌘M"
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Type a shortcut…" : label)
                .monospaced(!isRecording)
                .frame(minWidth: 120)
        }
        .help(isRecording ? "Press Escape to cancel." : "Click, then press the new shortcut.")
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        state.suspendHotKey()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            // A shortcut without ⌃, ⌥, or ⌘ would steal normal typing everywhere.
            guard !flags.subtracting(.shift).isEmpty || ShortcutFormat.isFunctionKey(event.keyCode) else {
                NSSound.beep()
                return nil
            }
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
