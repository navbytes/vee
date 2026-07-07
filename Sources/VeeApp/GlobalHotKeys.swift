import AppKit
import Carbon.HIToolbox
import VeePluginFormat

/// Registers process-global hotkeys via Carbon's `RegisterEventHotKey` — the
/// standard API for system-wide hotkeys that, unlike an `NSEvent` global monitor,
/// needs **no Accessibility permission** and keeps Vee dependency-free (no
/// third-party hotkey package). Each registered combo fires a main-actor action.
///
/// Carbon delivers hotkey events on the main run loop; the C handler is
/// capture-free (a requirement for `@convention(c)`) and dispatches to this
/// singleton on the main actor.
@MainActor
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// Four-char signature identifying Vee's hotkeys ('VEEH').
    private static let signature = OSType(0x5645_4548)

    /// Registers `spec`, invoking `action` on each press. Returns a token to pass
    /// to `unregister`, or `nil` if the combo couldn't be registered (e.g. it's
    /// already claimed system-wide) — the caller should log and move on.
    @discardableResult
    func register(_ spec: HotKeySpec, action: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        registrations[id] = Registration(ref: ref, action: action)
        return id
    }

    /// Unregisters a previously registered hotkey. Safe to call with a stale id.
    func unregister(_ id: UInt32) {
        guard let reg = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reg.ref)
    }

    /// Invoked (on the main actor) when a registered hotkey fires.
    fileprivate func fire(_ id: UInt32) {
        registrations[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                // Capture-free C callback: pull the hotkey id and hop to the actor.
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }
                let id = hotKeyID.id
                // Carbon delivers on the main thread, but assert isolation to
                // satisfy strict concurrency before touching the singleton.
                MainActor.assumeIsolated { GlobalHotKeys.shared.fire(id) }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}
