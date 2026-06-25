import Foundation
import VeeServices

/// The launcher's persisted user settings — a PURE, testable model.
///
/// `SettingsModel` is the single owner of what the Settings window edits:
///   • the global launcher `HotkeyChord` (key code + modifiers),
///   • the clipboard history size (`Int`, default 200 — mirrors
///     `ClipboardMonitor`'s default cap),
///   • the clipboard UTI blocklist (`Set<String>` — user-added types layered on
///     top of `ClipboardPrivacyFilter`'s always-enforced conventions).
///
/// It persists to a `UserDefaults` suite ("com.vee.launcher") and exposes change
/// callbacks so the app can react (re-bind the hotkey, resize history, update the
/// privacy filter) without the model knowing about hotkeys/clipboard machinery.
/// No AppKit, no OS hotkey registry, no `NSPasteboard` — just value state +
/// persistence, so the encode/decode and persistence behavior are unit-tested
/// directly against a fresh suite.
///
/// `@MainActor` because the Settings window (AppKit) is its only mutator and the
/// change callbacks fire on the main thread; the state itself is plain values.
@MainActor
public final class SettingsModel {

    // MARK: Persistence keys

    /// UserDefaults keys, namespaced under the launcher suite. Stable strings —
    /// changing one silently orphans previously-saved values.
    enum Key {
        static let hotkeyKeyCode = "hotkey.keyCode"
        static let hotkeyModifiers = "hotkey.modifiers"
        static let clipboardHistorySize = "clipboard.historySize"
        static let clipboardBlocklist = "clipboard.blocklist"
    }

    /// The launcher suite name (shared by the app's other defaults).
    /// `nonisolated` so it's usable as a default-argument expression (a pure
    /// constant — no actor state involved).
    public nonisolated static let suiteName = "com.vee.launcher"

    // MARK: Defaults

    /// The shipped default launcher chord: ⌥Space (Option + Space, keyCode 49).
    /// A conservative default that rarely collides system-wide.
    public static let defaultHotkey = HotkeyChord(keyCode: 49, modifiers: .option)

    /// Default retained clipboard history (matches `ClipboardMonitor`'s default).
    public static let defaultHistorySize = 200

    // MARK: Backing store

    private let defaults: UserDefaults

    // MARK: Change callbacks

    /// Fired whenever the launcher chord changes (after it's persisted). The app
    /// re-binds the global hotkey here.
    public var onHotkeyChange: ((HotkeyChord) -> Void)?
    /// Fired whenever the history size changes (after persistence). The app
    /// re-sizes the clipboard history here.
    public var onHistorySizeChange: ((Int) -> Void)?
    /// Fired whenever the blocklist changes (after persistence). The app updates
    /// the `ClipboardPrivacyFilter` here.
    public var onBlocklistChange: ((Set<String>) -> Void)?

    // MARK: Live state (each setter persists + notifies)

    /// The launcher hotkey chord. Setting it persists both fields and fires
    /// `onHotkeyChange`.
    public var hotkey: HotkeyChord {
        didSet {
            guard hotkey != oldValue else { return }
            persistHotkey(hotkey)
            onHotkeyChange?(hotkey)
        }
    }

    /// Clipboard history size. Clamped to at least 1 (a zero/negative cap is
    /// meaningless and `ClipboardMonitor` itself floors at 1). Persists + notifies.
    public var historySize: Int {
        didSet {
            let clamped = max(1, historySize)
            if clamped != historySize {
                // Re-entrant assignment is guarded by the equality check below on
                // the next pass; assign the clamped value and fall through.
                historySize = clamped
                return
            }
            guard historySize != oldValue else { return }
            defaults.set(historySize, forKey: Key.clipboardHistorySize)
            onHistorySizeChange?(historySize)
        }
    }

    /// User-added clipboard UTI blocklist. Persisted as a sorted array; exposed
    /// as a `Set`. Persists + notifies on change.
    public var blocklist: Set<String> {
        didSet {
            guard blocklist != oldValue else { return }
            defaults.set(blocklist.sorted(), forKey: Key.clipboardBlocklist)
            onBlocklistChange?(blocklist)
        }
    }

    // MARK: Init / load

    /// Load settings from `defaults` (the launcher suite by default), falling
    /// back to shipped defaults for any missing/!corrupt value.
    public init(defaults: UserDefaults? = UserDefaults(suiteName: SettingsModel.suiteName)) {
        // `UserDefaults(suiteName:)` is non-nil for any valid suite name; fall
        // back to `.standard` defensively so the model is always usable.
        let store = defaults ?? .standard
        self.defaults = store
        self.hotkey = SettingsModel.loadHotkey(from: store) ?? SettingsModel.defaultHotkey
        self.historySize = SettingsModel.loadHistorySize(from: store)
        self.blocklist = SettingsModel.loadBlocklist(from: store)
    }

    // MARK: Mutators (UI-friendly intents)

    /// Replace the launcher chord (equivalent to setting `hotkey`).
    public func updateHotkey(_ chord: HotkeyChord) { hotkey = chord }

    /// Add a UTI to the blocklist (no-op if blank or already present).
    public func addToBlocklist(_ type: String) {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        blocklist.insert(trimmed)
    }

    /// Remove a UTI from the blocklist (no-op if absent).
    public func removeFromBlocklist(_ type: String) {
        blocklist.remove(type)
    }

    /// Persist all current values explicitly. Setters already persist on change,
    /// so this is mainly useful to force-write the shipped defaults the first
    /// time (so a fresh suite has concrete stored values).
    public func save() {
        persistHotkey(hotkey)
        defaults.set(historySize, forKey: Key.clipboardHistorySize)
        defaults.set(blocklist.sorted(), forKey: Key.clipboardBlocklist)
    }

    // MARK: - Pure encode/decode (unit-tested directly)

    /// Persist a chord as two scalar defaults (keyCode + modifiers rawValue).
    /// Split into two plain integers rather than an archived blob so the stored
    /// representation is transparent and forward-stable.
    private func persistHotkey(_ chord: HotkeyChord) {
        defaults.set(chord.keyCode, forKey: Key.hotkeyKeyCode)
        defaults.set(chord.modifiers.rawValue, forKey: Key.hotkeyModifiers)
    }

    /// Decode a chord from a defaults store, or `nil` if the keyCode key is
    /// absent (→ caller uses the shipped default). The modifiers default to none
    /// if only the keyCode was written.
    static func loadHotkey(from defaults: UserDefaults) -> HotkeyChord? {
        // `object(forKey:)` distinguishes "absent" from a stored 0.
        guard defaults.object(forKey: Key.hotkeyKeyCode) != nil else { return nil }
        let keyCode = defaults.integer(forKey: Key.hotkeyKeyCode)
        let rawModifiers = defaults.integer(forKey: Key.hotkeyModifiers)
        return HotkeyChord(keyCode: keyCode,
                           modifiers: HotkeyChord.Modifiers(rawValue: rawModifiers))
    }

    /// Decode the history size, falling back to the default when absent or
    /// non-positive (a stored 0 is treated as "unset / invalid").
    static func loadHistorySize(from defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: Key.clipboardHistorySize) != nil else {
            return defaultHistorySize
        }
        let stored = defaults.integer(forKey: Key.clipboardHistorySize)
        return stored > 0 ? stored : defaultHistorySize
    }

    /// Decode the blocklist (stored as an array of strings) into a `Set`. Absent
    /// or wrong-typed → empty set.
    static func loadBlocklist(from defaults: UserDefaults) -> Set<String> {
        guard let array = defaults.array(forKey: Key.clipboardBlocklist) as? [String] else {
            return []
        }
        return Set(array)
    }
}
