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

        func isSeparator(_ c: Character) -> Bool { c == " " || c == "\t" }
        func skipSpaces() { while i < chars.count, isSeparator(chars[i]) { i += 1 } }

        while true {
            skipSpaces()
            if i >= chars.count { break }

            // Read key up to '='.
            var key = ""
            while i < chars.count, chars[i] != "=", !isSeparator(chars[i]) {
                key.append(chars[i]); i += 1
            }
            guard i < chars.count, chars[i] == "=" else {
                if !key.isEmpty {
                    diagnostics.append(.init(severity: .warning, message: "parameter '\(key)' has no value"))
                }
                // Skip stray token.
                while i < chars.count, !isSeparator(chars[i]) { i += 1 }
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
                while i < chars.count, !isSeparator(chars[i]) {
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
        var progressFraction: Double?
        var progressTrack: VeeColor?
        var progressW: Double?
        var progressH: Double?

        func bool(_ v: String) -> Bool { v == "true" || v == "1" || v == "yes" }

        // Numeric params flow into layout/font geometry (bar widths, NSFont
        // sizes). `Double("nan")`/`Double("inf")` parse successfully and NaN
        // defeats `min/max` clamps (NaN propagates), producing NaN CGRects and
        // NSFont sizes from plugin output. Reject non-finite values at the source.
        func finite(_ v: String) -> Double? {
            guard let d = Double(v.trimmingCharacters(in: .whitespaces)), d.isFinite else { return nil }
            return d
        }

        for (key, value) in pairs {
            switch key {
            case "color": p.color = VeeColor.parse(value)
            case "font": p.font = value
            case "size": p.size = finite(value)
            // Clamp to >= 0: a negative length would reach `String.prefix(_:)`
            // downstream, which traps (crashing the app) on a negative argument.
            case "length": p.length = Int(value).map { Swift.max(0, $0) }
            case "trim": p.trim = bool(value)
            case "ansi": p.ansi = bool(value)
            case "emojize": p.emojize = bool(value)
            case "href": p.href = URL(string: value).flatMap { URLScheme.isSafeToOpen($0) ? $0 : nil }
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
            case "sfsize": p.swiftbar.sfsize = finite(value)
            case "sfconfig": p.swiftbar.sfconfig = value
            case "symbolize": p.swiftbar.symbolize = bool(value)
            case "tooltip": p.swiftbar.tooltip = value
            case "md", "markdown": p.swiftbar.markdown = bool(value)
            case "checked": p.swiftbar.checked = bool(value)
            case "badge": p.swiftbar.badge = value
            case "webview": p.swiftbar.webview = URL(string: value).flatMap { URLScheme.isWebURL($0) ? $0 : nil }
            case "webvieww": p.swiftbar.webviewWidth = finite(value)
            case "webviewh": p.swiftbar.webviewHeight = finite(value)
            case "shortcut": p.swiftbar.shortcut = value
            case "sparkline":
                // Vee-native: comma-separated Doubles for an inline chart popover.
                // Skip malformed entries; an empty result stays `nil`.
                let series = value.split(separator: ",").compactMap { finite(String($0)) }
                p.sparkline = series.isEmpty ? nil : series
            case "toggle":
                // Vee-native: an on/off switch. Accepts on/off as well as the
                // usual truthy tokens. Empty value is malformed → nil.
                if !value.isEmpty {
                    let on = bool(value) || value.lowercased() == "on"
                    p.control = .toggle(on: on)
                }
            case "slider":
                // Vee-native: `min,max,value`. Requires three Doubles with
                // min < max; the value is clamped into range. Anything else
                // stays `nil` and is reported.
                let nums = value.split(separator: ",").compactMap { finite(String($0)) }
                if nums.count == 3, nums[0] < nums[1] {
                    let clamped = Swift.min(Swift.max(nums[2], nums[0]), nums[1])
                    p.control = .slider(min: nums[0], max: nums[1], value: clamped)
                } else if !value.isEmpty {
                    diagnostics.append(.init(severity: .warning, message: "slider= expects 'min,max,value' with min < max"))
                }
            case "progress":
                // Vee-native: `0..1` (a single fraction) or `value,max`. Result is
                // always clamped to 0...1.
                // Require *every* comma token to be a finite number, so a
                // non-finite token (e.g. `nan,2`) is flagged malformed rather
                // than silently dropped into a misread single-value form.
                let tokens = value.split(separator: ",").map(String.init)
                let nums = tokens.compactMap { finite($0) }
                if nums.count == tokens.count, nums.count == 1 {
                    progressFraction = Swift.min(Swift.max(nums[0], 0), 1)
                } else if nums.count == tokens.count, nums.count == 2, nums[1] != 0 {
                    progressFraction = Swift.min(Swift.max(nums[0] / nums[1], 0), 1)
                } else if !value.isEmpty {
                    diagnostics.append(.init(severity: .warning, message: "progress= expects a fraction (0..1) or 'value,max'"))
                }
            case "trackcolor": progressTrack = VeeColor.parse(value)
            case "progressw": progressW = finite(value)
            case "progressh": progressH = finite(value)
            case "header":
                // Vee-native: a first-class, non-interactive section-header
                // row. Stored on `p.swiftbar` — see the doc comment on
                // `LineParams.swiftbar` for why it lives there.
                p.swiftbar.header = bool(value)
            case "accessory":
                // Vee-native: which edge a progress=/sparkline= accessory
                // anchors to. Default (absent/unrecognised) stays trailing —
                // today's rendering. Stored on `p.swiftbar` — see the doc
                // comment on `LineParams.swiftbar` for why it lives there.
                switch value.lowercased() {
                case "leading": p.swiftbar.accessory = .leading
                case "trailing": p.swiftbar.accessory = .trailing
                default:
                    if !value.isEmpty {
                        diagnostics.append(.init(severity: .warning, message: "accessory= expects 'leading' or 'trailing'"))
                    }
                }
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

        if let fraction = progressFraction {
            p.progress = ProgressParams(fraction: fraction, trackColor: progressTrack, width: progressW, height: progressH)
        }

        return (p, diagnostics)
    }
}
