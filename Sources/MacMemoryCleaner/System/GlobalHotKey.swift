import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon's hot key API is still the only one that works
/// without Accessibility permission.
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The Carbon handler holds an unretained pointer to this object, so remove it first.
    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Returns false when another app already owns the same shortcut.
    @discardableResult
    func register(keyCode: Int, carbonModifiers: Int) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4D4D_434C), id: 1) // "MMCL"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(carbonModifiers), id, GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
