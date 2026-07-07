import Foundation

/// The live state of a plugin's global search hotkey, shown in the plugin's
/// Settings so the user can see (and fix) what actually happened — a declared
/// hotkey may be off, taken by another app, or mistyped after a rebind.
public enum HotkeyStatus: Equatable, Sendable {
    /// The plugin declares no hotkey and none is user-set — nothing to control.
    case none
    /// The user turned the hotkey off.
    case disabled
    /// Registered and live; the associated value is its display form (e.g. `⌘⇧K`).
    case active(String)
    /// The combination is already claimed system-wide; display form included.
    case unavailable(String)
    /// The user-entered combination doesn't parse into a valid shortcut.
    case invalid
}
