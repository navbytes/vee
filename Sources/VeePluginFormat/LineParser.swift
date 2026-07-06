import Foundation

/// Splits a raw menu line into its display text and typed parameters, and maps
/// the raw `key=value` pairs onto `LineParams`. Kept separate from tree building
/// so it is unit-testable in isolation.
enum LineParser {
    /// Splits a line into `(text, rawParams)`. The separator is the first
    /// top-level `|` that is not inside a quoted parameter value. Everything
    /// before it is display text; everything after is parsed as parameters.
    static func splitTextAndParams(_ line: String) -> (text: String, rawParams: [(key: String, value: String)], diagnostics: [ParseDiagnostic]) {
        // The title never contains quotes in practice, so the first `|` is the
        // separator. (Params values may contain `|`, but those come after it.)
        guard let pipe = line.firstIndex(of: "|") else {
            return (line, [], [])
        }
        let text = String(line[line.startIndex..<pipe])
        let paramString = String(line[line.index(after: pipe)...])
        let (pairs, diags) = parseParams(paramString)
        return (text, pairs, diags)
    }

    /// Parses a parameter string (`key=value key2="a b" …`) into ordered pairs.
    /// Handles single/double quotes, escaped quotes (`\"`), and values that
    /// contain `=` or `|`.
    static func parseParams(_ string: String) -> (pairs: [(key: String, value: String)], diagnostics: [ParseDiagnostic]) {
        var pairs: [(String, String)] = []
        var diagnostics: [ParseDiagnostic] = []
        let chars = Array(string)
        var i = 0

        func skipSpaces() { while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 } }

        while true {
            skipSpaces()
            if i >= chars.count { break }

            // Read key up to '='.
            var key = ""
            while i < chars.count, chars[i] != "=", chars[i] != " " {
                key.append(chars[i]); i += 1
            }
            guard i < chars.count, chars[i] == "=" else {
                if !key.isEmpty {
                    diagnostics.append(.init(severity: .warning, message: "parameter '\(key)' has no value"))
                }
                // Skip stray token.
                while i < chars.count, chars[i] != " " { i += 1 }
                continue
            }
            i += 1 // consume '='

            // Read value: quoted or bare.
            var value = ""
            if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                let quote = chars[i]; i += 1
                while i < chars.count {
                    if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == quote {
                        value.append(quote); i += 2; continue
                    }
                    if chars[i] == quote { i += 1; break }
                    value.append(chars[i]); i += 1
                }
            } else {
                while i < chars.count, chars[i] != " " {
                    value.append(chars[i]); i += 1
                }
            }
            pairs.append((key.lowercased(), value))
        }
        return (pairs, diagnostics)
    }

    /// Maps raw pairs onto `LineParams`, collecting positional `paramN` values
    /// into the shell command and preserving unrecognised keys.
    static func mapParams(_ pairs: [(key: String, value: String)]) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        var p = LineParams()
        var diagnostics: [ParseDiagnostic] = []
        var shellPath: String?
        var terminal: Bool?
        var positional: [Int: String] = [:]

        func bool(_ v: String) -> Bool { v == "true" || v == "1" || v == "yes" }

        for (key, value) in pairs {
            switch key {
            case "color": p.color = VeeColor.parse(value)
            case "font": p.font = value
            case "size": p.size = Double(value)
            case "length": p.length = Int(value)
            case "trim": p.trim = bool(value)
            case "ansi": p.ansi = bool(value)
            case "emojize": p.emojize = bool(value)
            case "href": p.href = URL(string: value)
            case "shell", "bash": shellPath = value
            case "terminal": terminal = bool(value)
            case "refresh": p.refresh = bool(value)
            case "dropdown": p.dropdown = bool(value)
            case "alternate": p.alternate = bool(value)
            case "disabled": p.disabled = bool(value)
            case "key": p.key = value
            case "image": p.image = value
            case "templateimage": p.templateImage = value
            case "sfimage": p.swiftbar.sfimage = value
            case "sfcolor": p.swiftbar.sfcolor = value.split(separator: ",").compactMap { VeeColor.parse(String($0)) }
            case "sfsize": p.swiftbar.sfsize = Double(value)
            case "sfconfig": p.swiftbar.sfconfig = value
            case "symbolize": p.swiftbar.symbolize = bool(value)
            case "tooltip": p.swiftbar.tooltip = value
            case "md", "markdown": p.swiftbar.markdown = bool(value)
            case "checked": p.swiftbar.checked = bool(value)
            case "badge": p.swiftbar.badge = value
            case "webview": p.swiftbar.webview = URL(string: value)
            case "webvieww": p.swiftbar.webviewWidth = Double(value)
            case "webviewh": p.swiftbar.webviewHeight = Double(value)
            case "shortcut": p.swiftbar.shortcut = value
            case "sparkline":
                // Vee-native: comma-separated Doubles for an inline chart popover.
                // Skip malformed entries; an empty result stays `nil`.
                let series = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                p.sparkline = series.isEmpty ? nil : series
            default:
                if key.hasPrefix("param"), let n = Int(key.dropFirst(5)) {
                    positional[n] = value
                } else {
                    p.unknown[key] = value
                    diagnostics.append(.init(severity: .warning, message: "unknown parameter '\(key)'"))
                }
            }
        }

        if let path = shellPath {
            let args = positional.sorted { $0.key < $1.key }.map(\.value)
            p.shell = ShellCommand(launchPath: path, arguments: args, openInTerminal: terminal ?? false)
        } else if !positional.isEmpty {
            diagnostics.append(.init(severity: .warning, message: "paramN given without shell=/bash="))
        }

        return (p, diagnostics)
    }
}
