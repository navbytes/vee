import Foundation

// MARK: - Chord value type

/// A global-hotkey chord: a virtual key code + modifier flags. A value type so
/// it can key dictionaries and cross the seam without any Carbon dependency.
public struct HotkeyChord: Hashable, Sendable {
    /// Modifier flags (matches the common Cmd/Opt/Ctrl/Shift set).
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option  = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift   = Modifiers(rawValue: 1 << 3)
    }

    /// Virtual key code (e.g. 49 == Space).
    public var keyCode: Int
    public var modifiers: Modifiers
    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

// MARK: - Seam: OS hotkey registry

/// The OS seam over Carbon `RegisterEventHotKey`. The fake (tests) and a thin
/// real adapter conform; ALL bookkeeping/conflict logic lives in
/// `HotkeyDispatcher` above this seam.
///
/// `register` returns false if the OS refuses the chord (e.g. already claimed
/// system-wide). The registry just forwards the OS callback to `handler`.
public protocol HotkeyRegistry: AnyObject {
    func register(_ chord: HotkeyChord, handler: @escaping () -> Void) -> Bool
    func unregister(_ chord: HotkeyChord)
}

// MARK: - Dispatcher (above the seam)

/// Outcome of binding an action to a chord.
public enum HotkeyBindResult: Equatable {
    case registered
    /// Another action already owns this chord.
    case conflict(existingAction: String)
    /// The OS registry refused the chord.
    case osRejected
}

/// Owns chord→action bookkeeping and conflict detection on top of a
/// `HotkeyRegistry`. The host binds named actions to user-chosen chords here;
/// this centralizes the single global hotkey namespace (build plan §6).
///
/// Pure bookkeeping above the seam → fully unit-testable with a fake registry.
public final class HotkeyDispatcher {
    private let registry: HotkeyRegistry
    /// action → its currently bound chord.
    private var actionToChord: [String: HotkeyChord] = [:]
    /// chord → the action that owns it (for O(1) conflict detection).
    private var chordToAction: [HotkeyChord: String] = [:]

    public init(registry: HotkeyRegistry) {
        self.registry = registry
    }

    /// Bind `action` to `chord`, invoking `handler` when fired.
    ///
    /// - A chord already owned by a *different* action → `.conflict`.
    /// - Rebinding the *same* action to a new chord releases its old chord first.
    /// - If the OS registry refuses → `.osRejected` (and no state changes).
    @discardableResult
    public func bind(action: String,
                     chord: HotkeyChord,
                     handler: @escaping () -> Void) -> HotkeyBindResult {
        if let owner = chordToAction[chord], owner != action {
            return .conflict(existingAction: owner)
        }

        // Release this action's previous chord (if any & different) before claiming.
        if let old = actionToChord[action], old != chord {
            registry.unregister(old)
            chordToAction[old] = nil
        }

        guard registry.register(chord, handler: handler) else {
            return .osRejected
        }

        actionToChord[action] = chord
        chordToAction[chord] = action
        return .registered
    }

    /// Unbind an action and release its chord from the OS.
    public func unbind(action: String) {
        guard let chord = actionToChord[action] else { return }
        registry.unregister(chord)
        actionToChord[action] = nil
        chordToAction[chord] = nil
    }

    /// The chord currently bound to `action`, if any.
    public func chord(for action: String) -> HotkeyChord? {
        actionToChord[action]
    }

    /// The action currently owning `chord`, if any.
    public func action(for chord: HotkeyChord) -> String? {
        chordToAction[chord]
    }
}

// MARK: - Thin real adapter (NOT unit-tested; needs a desktop event loop)

#if canImport(Carbon)
import Carbon.HIToolbox

/// Thin Carbon `RegisterEventHotKey` adapter. Logic-free: it maps a
/// `HotkeyChord` to Carbon parameters, installs the handler, and forwards the OS
/// callback to the stored closure. The tested `HotkeyDispatcher` sits above it.
/// Not unit-tested — it needs a running Carbon event target.
public final class CarbonHotkeyRegistry: HotkeyRegistry {
    private final class Registration {
        var ref: EventHotKeyRef?
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }

    private var registrations: [HotkeyChord: Registration] = [:]
    private var nextID: UInt32 = 1
    private var idToChord: [UInt32: HotkeyChord] = [:]
    private var installed = false

    public init() {}

    private func carbonModifiers(_ mods: HotkeyChord.Modifiers) -> UInt32 {
        var flags: UInt32 = 0
        if mods.contains(.command) { flags |= UInt32(cmdKey) }
        if mods.contains(.option)  { flags |= UInt32(optionKey) }
        if mods.contains(.control) { flags |= UInt32(controlKey) }
        if mods.contains(.shift)   { flags |= UInt32(shiftKey) }
        return flags
    }

    public func register(_ chord: HotkeyChord, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let reg = Registration(handler: handler)
        let id = nextID; nextID += 1
        idToChord[id] = chord

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x56656548 /* 'VeeH' */), id: id)
        let status = RegisterEventHotKey(UInt32(chord.keyCode),
                                         carbonModifiers(chord.modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            idToChord[id] = nil
            return false
        }
        reg.ref = ref
        registrations[chord] = reg
        return true
    }

    public func unregister(_ chord: HotkeyChord) {
        guard let reg = registrations.removeValue(forKey: chord), let ref = reg.ref else { return }
        UnregisterEventHotKey(ref)
        idToChord = idToChord.filter { $0.value != chord }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<CarbonHotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let chord = me.idToChord[hkID.id], let reg = me.registrations[chord] {
                reg.handler()
            }
            return noErr
        }, 1, &spec, context, nil)
    }
}
#endif
