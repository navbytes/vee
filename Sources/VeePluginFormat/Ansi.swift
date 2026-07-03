import Foundation

/// Minimal ANSI SGR parser: turns escape-styled text into plain text plus a set
/// of style runs (character-offset ranges). Supports reset, bold/italic/
/// underline, the 8 basic + 8 bright foreground colors, and 24-bit `38;2;r;g;b`.
enum Ansi {
    private struct State: Equatable {
        var fg: VeeColor?
        var bold = false
        var italic = false
        var underline = false

        var isStyled: Bool { fg != nil || bold || italic || underline }

        func run(_ range: Range<Int>) -> AnsiRun {
            AnsiRun(range: range, foreground: fg, bold: bold, italic: italic, underline: underline)
        }
    }

    private static let baseColors: [Int: String] = [
        30: "black", 31: "red", 32: "green", 33: "yellow",
        34: "blue", 35: "magenta", 36: "cyan", 37: "white",
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
                var j = i + 2
                var code = ""
                while j < chars.count, chars[j] != "m" {
                    code.append(chars[j]); j += 1
                }
                if j < chars.count {
                    closeRun(at: plain.count)
                    apply(code, to: &state)
                    runStart = plain.count
                    i = j + 1
                    continue
                }
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
        let parts = code.split(separator: ";").map { Int($0) ?? -1 }
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
            case 38:
                // Extended color: 38;2;r;g;b (truecolor) or 38;5;n (256; skipped).
                if k + 1 < parts.count, parts[k + 1] == 2, k + 4 < parts.count {
                    let r = UInt8(clamping: parts[k + 2])
                    let g = UInt8(clamping: parts[k + 3])
                    let b = UInt8(clamping: parts[k + 4])
                    state.fg = .rgb(r: r, g: g, b: b, a: 255)
                    k += 4
                } else if k + 1 < parts.count, parts[k + 1] == 5, k + 2 < parts.count {
                    k += 2 // 256-color index not mapped
                }
            default:
                break
            }
            k += 1
        }
    }
}
