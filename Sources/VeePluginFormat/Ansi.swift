import Foundation

/// Minimal ANSI SGR parser: turns escape-styled text into plain text plus a set
/// of style runs (character-offset ranges). Supports reset, bold/italic/
/// underline, the 8 basic + 8 bright foreground colors, and 24-bit `38;2;r;g;b`.
enum Ansi {
    private struct State: Equatable {
        var fg: VeeColor?
        var bg: VeeColor?
        var bold = false
        var italic = false
        var underline = false

        var isStyled: Bool { fg != nil || bg != nil || bold || italic || underline }

        func run(_ range: Range<Int>) -> AnsiRun {
            AnsiRun(range: range, foreground: fg, background: bg, bold: bold, italic: italic, underline: underline)
        }
    }

    private static let baseColors: [Int: String] = [
        30: "black", 31: "red", 32: "green", 33: "yellow",
        34: "blue", 35: "magenta", 36: "cyan", 37: "white"
    ]

    /// Parses `text`, returning the escape-stripped string and its style runs.
    static func parse(_ text: String) -> (plain: String, runs: [AnsiRun]) {
        guard text.contains("\u{1B}") else { return (text, []) }

        let chars = Array(text)
        var plain: [Character] = []
        var runs: [AnsiRun] = []
        var state = State()
        var runStart = 0
        var i = 0

        func closeRun(at end: Int) {
            if state.isStyled && end > runStart {
                runs.append(state.run(runStart..<end))
            }
        }

        while i < chars.count {
            if chars[i] == "\u{1B}", i + 1 < chars.count, chars[i + 1] == "[" {
                // A CSI sequence is `ESC [` , parameter/intermediate bytes
                // (0x20–0x3F), then a single final byte (0x40–0x7E). Only `m`
                // (SGR) carries styling; any other final byte (cursor move, erase,
                // …) must be stripped without disturbing the current style state
                // or being mis-scanned as SGR parameters up to the next `m`.
                var j = i + 2
                var code = ""
                while j < chars.count, let v = chars[j].unicodeScalars.first?.value, (0x20...0x3F).contains(v) {
                    code.append(chars[j]); j += 1
                }
                if j < chars.count, let fv = chars[j].unicodeScalars.first?.value, (0x40...0x7E).contains(fv) {
                    if chars[j] == "m" {
                        closeRun(at: plain.count)
                        apply(code, to: &state)
                        runStart = plain.count
                    }
                    // Non-SGR final byte: strip the sequence, keep style state.
                    i = j + 1
                    continue
                }
                // Malformed / unterminated CSI: fall through and treat ESC as literal.
            }
            plain.append(chars[i]); i += 1
        }
        closeRun(at: plain.count)
        return (String(plain), runs)
    }

    /// Removes ANSI escape sequences without applying any styling.
    static func strip(_ text: String) -> String {
        parse(text).plain
    }

    private static func apply(_ code: String, to state: inout State) {
        // Per the SGR default-parameter rule, an omitted numeric parameter
        // means 0 (reset): `\e[m` is a full reset and `\e[;31m` is
        // reset-then-red — not a no-op — so an empty component must map to 0,
        // not be dropped. `omittingEmptySubsequences: false` keeps those empty
        // components (including the sole one when `code` itself is empty)
        // instead of collapsing them away.
        let parts = code.split(separator: ";", omittingEmptySubsequences: false).map { $0.isEmpty ? 0 : (Int($0) ?? -1) }
        var k = 0
        while k < parts.count {
            let c = parts[k]
            switch c {
            case 0: state = State()
            case 1: state.bold = true
            case 22: state.bold = false
            case 3: state.italic = true
            case 23: state.italic = false
            case 4: state.underline = true
            case 24: state.underline = false
            case 30...37: state.fg = baseColors[c].map { .named($0) }
            case 90...97: state.fg = baseColors[c - 60].map { .named($0) }
            case 39: state.fg = nil
            case 40...47: state.bg = baseColors[c - 10].map { .named($0) }
            case 100...107: state.bg = baseColors[c - 70].map { .named($0) }
            case 49: state.bg = nil
            case 38: k += consumeExtended(parts, at: k) { state.fg = $0 }
            case 48: k += consumeExtended(parts, at: k) { state.bg = $0 }
            default:
                break
            }
            k += 1
        }
    }

    /// Handles `{38|48};2;r;g;b` (truecolor) and `{38|48};5;n` (256-color),
    /// returning how many extra parts were consumed.
    private static func consumeExtended(_ parts: [Int], at k: Int, set: (VeeColor?) -> Void) -> Int {
        guard k + 1 < parts.count else { return 0 }
        if parts[k + 1] == 2, k + 4 < parts.count {
            set(.rgb(r: UInt8(clamping: parts[k + 2]), g: UInt8(clamping: parts[k + 3]), b: UInt8(clamping: parts[k + 4]), a: 255))
            return 4
        }
        if parts[k + 1] == 5, k + 2 < parts.count {
            set(xterm256(parts[k + 2]))
            return 2
        }
        return 0
    }

    /// Maps an xterm 256-color index to RGB (16 base + 6×6×6 cube + grayscale).
    private static func xterm256(_ n: Int) -> VeeColor? {
        guard (0...255).contains(n) else { return nil }
        if n < 16 {
            let base: [(UInt8, UInt8, UInt8)] = [
                (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
                (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
                (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
                (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)
            ]
            let (r, g, b) = base[n]
            return .rgb(r: r, g: g, b: b, a: 255)
        }
        if n < 232 {
            let c = n - 16
            func level(_ v: Int) -> UInt8 { v == 0 ? 0 : UInt8(55 + v * 40) }
            return .rgb(r: level((c / 36) % 6), g: level((c / 6) % 6), b: level(c % 6), a: 255)
        }
        let gray = UInt8(8 + (n - 232) * 10)
        return .rgb(r: gray, g: gray, b: gray, a: 255)
    }
}
