import Foundation

/// A parsed global-hotkey combination declared by a plugin via
/// `<vee.shortcut>cmd+shift+k</vee.shortcut>`. Holds the Carbon virtual key code
/// and modifier mask that `RegisterEventHotKey` needs — but this type is
/// Carbon-free (the constants are hard-coded, stable OS values) so parsing stays
/// pure and unit-testable. The app layer (`GlobalHotKeys`) consumes the numbers.
public struct HotKeySpec: Equatable, Sendable {
    /// Carbon virtual key code (`kVK_ANSI_*` / `kVK_*`).
    public let keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`/`shiftKey`/`optionKey`/`controlKey`).
    public let modifiers: UInt32
    /// A human-readable rendering, e.g. `⌘⇧K`, for logs / a future settings UI.
    public let display: String

    public init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    // Carbon modifier masks (from <Carbon/HIToolbox/Events.h>).
    static let cmdKey: UInt32 = 0x0100
    static let shiftKey: UInt32 = 0x0200
    static let optionKey: UInt32 = 0x0800
    static let controlKey: UInt32 = 0x1000

    /// Parses `"cmd+shift+k"` (order-independent, case-insensitive, `+`- or
    /// `-`-separated). Returns `nil` unless it names **at least one modifier** and
    /// exactly one known key — a global hotkey without a modifier is rejected as
    /// it would shadow a bare keypress system-wide.
    public static func parse(_ raw: String) -> HotKeySpec? {
        // Allow glued symbol modifiers as macOS displays them (`⌘⇧K`) by giving
        // each modifier symbol its own separator before tokenizing.
        var normalized = raw
        for symbol in ["⌘", "⌥", "⇧", "⌃"] {
            normalized = normalized.replacingOccurrences(of: symbol, with: symbol + "+")
        }
        let tokens = normalized
            .split(whereSeparator: { $0 == "+" || $0 == "-" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        var keyName: String?

        for token in tokens {
            if let mod = modifierMask[token] {
                modifiers |= mod
            } else if let code = keyCodes[token] {
                // Only one non-modifier key is allowed.
                guard keyCode == nil else { return nil }
                keyCode = code
                keyName = token
            } else {
                return nil   // unknown token → reject the whole spec
            }
        }

        guard modifiers != 0, let keyCode, let keyName else { return nil }
        return HotKeySpec(keyCode: keyCode, modifiers: modifiers, display: displayString(modifiers: modifiers, keyName: keyName))
    }

    private static let modifierMask: [String: UInt32] = [
        "cmd": cmdKey, "command": cmdKey, "⌘": cmdKey,
        "shift": shiftKey, "⇧": shiftKey,
        "opt": optionKey, "option": optionKey, "alt": optionKey, "⌥": optionKey,
        "ctrl": controlKey, "control": controlKey, "⌃": controlKey
    ]

    /// Symbol shown for each modifier, in the conventional ⌃⌥⇧⌘ order.
    private static func displayString(modifiers: UInt32, keyName: String) -> String {
        var out = ""
        if modifiers & controlKey != 0 { out += "⌃" }
        if modifiers & optionKey != 0 { out += "⌥" }
        if modifiers & shiftKey != 0 { out += "⇧" }
        if modifiers & cmdKey != 0 { out += "⌘" }
        return out + (keyDisplay[keyName] ?? keyName.uppercased())
    }

    private static let keyDisplay: [String: String] = [
        "space": "␣", "return": "↩", "enter": "↩", "tab": "⇥", "escape": "⎋", "esc": "⎋",
        "left": "←", "right": "→", "up": "↑", "down": "↓"
    ]

    /// Carbon virtual key codes (`kVK_*`). Layout-independent physical keys.
    private static let keyCodes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16,
        "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "space": 0x31, "return": 0x24, "enter": 0x24, "tab": 0x30, "escape": 0x35, "esc": 0x35,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
        "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F
    ]
}
