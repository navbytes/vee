import Foundation

/// Splits a raw menu line into its display text and typed parameters, and maps
/// the raw `key=value` pairs onto `LineParams`. Kept separate from tree building
/// so it is unit-testable in isolation.
enum LineParser {
    /// Splits a line into `(text, rawParams)`. The separator is the first
    /// top-level `|` that isn't escaped (`\|`) — a literal `|`/newline/backslash
    /// in the display text is written as `\|`/`\n`/`\\` (the bundled TS/Python/Go
    /// SDKs escape exactly these three characters when emitting user-supplied
    /// text), so it survives the split instead of truncating or corrupting the
    /// item. Everything before the delimiter is display text (unescaped here);
    /// everything after is parsed as parameters.
    static func splitTextAndParams(_ line: String) -> (text: String, rawParams: [(key: String, value: String)], diagnostics: [ParseDiagnostic]) {
        let chars = Array(line)
        var text = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, let unescaped = unescape(chars[i + 1]) {
                text.append(unescaped)
                i += 2
                continue
            }
            if chars[i] == "|" { break }
            text.append(chars[i])
            i += 1
        }
        guard i < chars.count else {
            // Ran off the end without finding an unescaped `|`: no params section.
            return (text, [], [])
        }
        let paramString = String(chars[(i + 1)...])
        let (pairs, diags) = parseParams(paramString)
        return (text, pairs, diags)
    }

    /// `\|` → `|`, `\n` → newline, `\\` → `\` — the three escapes honored
    /// identically by this tokenizer (here, and in the quoted-value scanner
    /// below) and by the bundled SDKs' serializers. Any other backslash
    /// sequence (including the per-quote-character `\"`/`\'` the value scanner
    /// handles itself) is left untouched — permissive, matching this parser's
    /// "never throw" stance.
    private static func unescape(_ c: Character) -> Character? {
        switch c {
        case "|": return "|"
        case "n": return "\n"
        case "\\": return "\\"
        default: return nil
        }
    }

    /// Parses a parameter string (`key=value key2="a b" …`) into ordered pairs.
    /// Handles single/double quotes, escaped quotes (`\"`), the shared `\|`/`\n`/
    /// `\\` escapes (see `unescape` above), and values that contain `=` or `|`.
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
                    if chars[i] == "\\", i + 1 < chars.count {
                        if chars[i + 1] == quote {
                            value.append(quote); i += 2; continue
                        }
                        if let unescaped = unescape(chars[i + 1]) {
                            value.append(unescaped); i += 2; continue
                        }
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
        var sparklineW: Double?
        var sparklineH: Double?
        var sparklineColor: VeeColor?
        var sparklineFullWidth = false
        var progressTrack: VeeColor?
        var progressW: Double?
        var progressH: Double?
        // Chart params are assembled after the loop: the shape (`pie=`/`donut=`/
        // `stackedbar=`) and its `chartlabels=`/`chartcolors=` may appear on the
        // line in any order, and a line naming more than one shape takes the
        // last (the established "last one wins" rule).
        var chartKind: ChartKind?
        var chartRaw = ""
        var chartLabels: [String] = []
        var chartColors: [VeeColor?] = []
        var chartW: Double?
        var chartH: Double?
        var chartFullWidth = false
        var progressFullWidth = false
        var seenKeys: Set<String> = []

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
            // A key repeated on one line silently let the last occurrence win
            // (still does — "last one wins" is the established rule elsewhere in
            // this parser, e.g. duplicate header tags) but gave no signal it
            // happened, hiding typos like a copy-pasted `color=red … color=blue`.
            if !seenKeys.insert(key).inserted {
                diagnostics.append(.init(severity: .warning, message: "duplicate parameter '\(key)'"))
            }
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
            case "href":
                if let url = URL(string: value), URLScheme.isSafeToOpen(url) {
                    p.href = url
                } else {
                    // Same gate/diagnostic shape as WidgetCardParser's href
                    // action filter: a missing/unparseable/scheme-blocked URL
                    // silently became `nil` with no signal it was dropped.
                    diagnostics.append(.init(severity: .warning, message: "href= has a missing or unsafe url; dropped"))
                }
            case "shell", "bash": shellPath = value
            case "terminal": terminal = bool(value)
            case "refresh": p.refresh = bool(value)
            case "dropdown": p.dropdown = bool(value)
            case "alternate": p.alternate = bool(value)
            case "disabled": p.disabled = bool(value)
            case "key": p.key = value
            case "image": p.image = validatedImage(value, param: "image", diagnostics: &diagnostics)
            case "templateimage": p.templateImage = validatedImage(value, param: "templateImage", diagnostics: &diagnostics)
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
            case "pie", "donut", "stackedbar":
                // Vee-native: a categorical share chart. All three shapes take
                // the same data — one series of non-negative numbers — so they
                // share a parse path and differ only in how they're drawn.
                chartKind = ChartKind(rawValue: key)
                chartRaw = value
            case "chartlabels":
                // Segment names, positional against the chart's values. Empty
                // entries are kept so a later label still lines up with its own
                // segment (`chartlabels=Docs,,Apps` labels segments 1 and 3).
                chartLabels = value.isEmpty ? [] : value
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            case "chartcolors":
                // Segment colors, positional like `chartlabels=`. Unlike
                // `sfcolor=` this keeps blank/malformed entries as holes
                // instead of compacting them out — dropping one would slide
                // every later color onto the wrong segment — and each hole falls
                // back to that segment's palette slot.
                let colorTokens = value.isEmpty
                    ? []
                    : value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                chartColors = colorTokens.map { VeeColor.parse($0) }
                let unparseable = colorTokens.enumerated().contains { entry in
                    chartColors[entry.offset] == nil
                        && !entry.element.trimmingCharacters(in: .whitespaces).isEmpty
                }
                if unparseable {
                    diagnostics.append(.init(
                        severity: .warning,
                        message: "chartcolors= has a malformed color; those segments use the default palette"
                    ))
                }
            case "chartw":
                // `full` is the one non-numeric value: stretch to the row's own
                // width rather than a fixed number of points.
                if value.lowercased() == "full" { chartFullWidth = true } else { chartW = finite(value) }
            case "charth": chartH = finite(value)
            case "progresstrackcolor", "trackcolor":
                // `trackcolor=` is the pre-v2 spelling, kept working for
                // plugins already published with it.
                progressTrack = VeeColor.parse(value)
            case "progressw":
                // `full` is the one non-numeric value, exactly as in `chartw=`:
                // stretch to the row's own width rather than a fixed number of
                // points.
                if value.lowercased() == "full" { progressFullWidth = true } else { progressW = finite(value) }
            case "progressh": progressH = finite(value)
            case "sparklinew":
                // `full` is the one non-numeric value, exactly as in `progressw=`
                // and `chartw=`: stretch to the row's own width.
                if value.lowercased() == "full" { sparklineFullWidth = true } else { sparklineW = finite(value) }
            case "sparklineh": sparklineH = finite(value)
            case "sparklinecolor": sparklineColor = VeeColor.parse(value)
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

        if sparklineW != nil || sparklineH != nil || sparklineColor != nil || sparklineFullWidth {
            p.swiftbar.sparklineStyle = SparklineStyle(
                width: sparklineW, height: sparklineH,
                color: sparklineColor, isFullWidth: sparklineFullWidth
            )
        }

        if let fraction = progressFraction {
            p.progress = ProgressParams(
                fraction: fraction, trackColor: progressTrack,
                width: progressW, height: progressH, isFullWidth: progressFullWidth
            )
        }

        if let kind = chartKind {
            // Require *every* comma token to be a finite number, the same
            // strictness `progress=` uses, so `pie=10,abc,30` is flagged rather
            // than quietly charting a two-segment series the author never wrote.
            let tokens = chartRaw.split(separator: ",").map(String.init)
            let nums = tokens.compactMap { finite($0) }
            if nums.count == tokens.count {
                p.swiftbar.chart = ChartParams.make(
                    kind: kind, values: nums, labels: chartLabels, colors: chartColors,
                    width: chartW, height: chartH, isFullWidth: chartFullWidth,
                    diagnostics: &diagnostics
                )
            } else {
                diagnostics.append(.init(
                    severity: .warning,
                    message: "\(kind.rawValue)= expects a comma-separated list of non-negative numbers"
                ))
            }
        } else if !chartLabels.isEmpty || !chartColors.isEmpty {
            // Labels/colors with nothing to attach them to: silently dropping
            // them looked exactly like a chart that failed to render.
            diagnostics.append(.init(
                severity: .warning,
                message: "chartlabels=/chartcolors= given without pie=/donut=/stackedbar="
            ))
        }

        return (p, diagnostics)
    }

    /// Decoded-byte cap for `image=`/`templateImage=` payloads. A menu-bar/status
    /// icon is tiny — this only guards against a pathologically large embed
    /// (memory blowup, an unresponsive menu); legitimate icons sit far under it.
    private static let maxImageBytes = 2 * 1024 * 1024

    /// Validates a base64 image payload: it must decode, and stay under
    /// `maxImageBytes` once decoded. Uses the same lenient
    /// `.ignoreUnknownCharacters` decode `SymbolImageFactory` renders with, so a
    /// value accepted here is guaranteed to decode there too. Drops (`nil`) with
    /// a diagnostic on failure instead of forwarding a payload the renderer
    /// would silently fail to draw.
    private static func validatedImage(_ value: String, param: String, diagnostics: inout [ParseDiagnostic]) -> String? {
        guard let data = Data(base64Encoded: value, options: .ignoreUnknownCharacters), !data.isEmpty else {
            diagnostics.append(.init(severity: .warning, message: "\(param)= is not valid base64; dropped"))
            return nil
        }
        guard data.count <= maxImageBytes else {
            diagnostics.append(.init(severity: .warning, message: "\(param)= decodes to over \(maxImageBytes) bytes; dropped"))
            return nil
        }
        return value
    }
}
