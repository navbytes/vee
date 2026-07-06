import AppKit

/// Parses a SwiftBar/xbar `key=` value (e.g. `CMD+SHIFT+K`, `k`, `shift+F2`,
/// `⌘,`) into an `NSMenuItem` key equivalent and modifier mask. Pure and
/// testable; `MenuBuilder` applies the result.
///
/// Modifiers are `+`-separated and case-insensitive (`cmd`/`command`/`⌘`,
/// `opt`/`option`/`alt`/`⌥`, `ctrl`/`control`/`⌃`, `shift`/`⇧`). The remaining
/// token is the key: a single character, or a named key (`space`, `tab`,
/// `return`/`enter`, `delete`/`backspace`, `escape`, arrows, `home`/`end`,
/// `pageup`/`pagedown`, `f1`…`f12`).
enum KeyEquivalentParser {
    static func parse(_ raw: String) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        // Split on `+`, tolerating surrounding whitespace, but keep a lone `+`
        // (its own key) intact when it is the only token.
        let tokens = raw
            .split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            // A bare `+` value means the plus key with no modifiers.
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            return trimmed == "+" ? ("+", []) : nil
        }

        var modifiers: NSEvent.ModifierFlags = []
        var keyToken: String?
        for token in tokens {
            switch token.lowercased() {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "shift", "⇧": modifiers.insert(.shift)
            default:
                // The last non-modifier token wins (handles a stray modifier
                // synonym appearing after the key).
                keyToken = token
            }
        }
        guard let keyToken else { return nil }
        let lowered = keyToken.lowercased()
        if let named = named[lowered] { return (named, modifiers) }
        // Single characters use their lowercase form; Shift is expressed via the
        // modifier mask, matching AppKit's key-equivalent convention.
        return (lowered, modifiers)
    }

    private static func fnKey(_ code: Int) -> String { String(UnicodeScalar(UInt32(code))!) }

    private static let named: [String: String] = {
        var map: [String: String] = [
            "space": " ",
            "tab": "\t",
            "return": "\r",
            "enter": "\r",
            "delete": "\u{8}",       // backspace
            "backspace": "\u{8}",
            "forwarddelete": "\u{7F}",
            "escape": "\u{1B}",
            "esc": "\u{1B}",
            "up": fnKey(NSUpArrowFunctionKey),
            "down": fnKey(NSDownArrowFunctionKey),
            "left": fnKey(NSLeftArrowFunctionKey),
            "right": fnKey(NSRightArrowFunctionKey),
            "home": fnKey(NSHomeFunctionKey),
            "end": fnKey(NSEndFunctionKey),
            "pageup": fnKey(NSPageUpFunctionKey),
            "pagedown": fnKey(NSPageDownFunctionKey),
        ]
        for n in 1...12 { map["f\(n)"] = fnKey(NSF1FunctionKey + (n - 1)) }
        return map
    }()
}
