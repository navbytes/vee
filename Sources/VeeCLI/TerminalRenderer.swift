import Foundation
import VeePluginFormat

/// Renders a `ParsedOutput` as a terminal-native view of what a plugin's
/// menu-bar dropdown would show: the title line(s), a rule, then the indented
/// dropdown tree. Rich params are rendered the way a terminal *can* — `color=`
/// and ANSI runs as real SGR escapes, `progress=` as a Unicode block bar,
/// `sparkline=` as a block sparkline, `toggle=`/`slider=` as inline state — and
/// the things a terminal *can't* draw (SF Symbols, base64 images) are shown by
/// name so nothing silently disappears.
///
/// Pure and deterministic so the whole surface is unit-tested; the live loop
/// (`LiveView`) is the only part that touches the real terminal.
public enum TerminalRenderer {
    public struct Options: Sendable {
        /// Emit ANSI SGR escapes. Off for pipes / `--no-color` / `NO_COLOR` and
        /// in tests, so the output is plain and assertable.
        public var color: Bool
        /// Column budget, used for rule width.
        public var width: Int

        public init(color: Bool = true, width: Int = 80) {
            self.color = color
            self.width = max(20, width)
        }
    }

    /// Number of cells in a `progress=` bar. Fixed (not width-scaled) so output
    /// is deterministic and fits a narrow terminal.
    private static let progressCells = 12

    // MARK: - Entry point

    public static func render(_ output: ParsedOutput, options: Options = Options()) -> String {
        var lines: [String] = []

        for title in output.titleLines {
            lines.append(renderTitle(title, options))
        }

        if !output.body.isEmpty {
            lines.append(rule(count: min(options.width, 48), options))
            for node in output.body {
                renderNode(node, depth: 0, options: options, into: &lines)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Title

    private static func renderTitle(_ title: TitleLine, _ options: Options) -> String {
        let icon = iconTag(title.params, options)
        let text = title.text.isEmpty ? "(empty)" : title.text
        // Titles read as the bar's label: bold, with color/ANSI applied.
        let label = styledText(text, color: title.params.color, runs: title.ansiRuns, options: options, extra: [1])
        return icon + label
    }

    // MARK: - Nodes

    private static func renderNode(_ node: MenuNode, depth: Int, options: Options, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        switch node {
        case .separator:
            lines.append(indent + rule(count: 16, options))
        case .item(let item):
            lines.append(indent + renderItem(item, options))
            if let alt = item.alternate {
                lines.append(indent + dim("⌥ ", options) + renderItem(alt, options))
            }
            for child in item.submenu {
                renderNode(child, depth: depth + 1, options: options, into: &lines)
            }
        }
    }

    private static func renderItem(_ item: MenuItem, _ options: Options) -> String {
        let p = item.params
        let disabled = p.disabled == true
        let isHeader = p.swiftbar.header == true

        var leading = ""
        if p.swiftbar.checked == true { leading += style("✓ ", codes: fgCodes(.named("green")) ?? [], options) }
        leading += iconTag(p, options)

        // The label: header → bold; disabled → dim (color suppressed); else the
        // plugin's color=/ANSI. An empty label with no accessory falls back to a
        // visible placeholder so the row isn't a blank line.
        let hasAccessory = p.progress != nil || p.sparkline != nil || p.control != nil
        let rawText: String
        if item.text.isEmpty {
            rawText = (leading.isEmpty && !hasAccessory) ? "(empty)" : ""
        } else {
            rawText = item.text
        }
        let label: String
        if disabled {
            label = styledText(rawText, color: nil, runs: [], options: options, extra: [2])
        } else if isHeader {
            label = styledText(rawText, color: p.color, runs: item.ansiRuns, options: options, extra: [1])
        } else {
            label = styledText(rawText, color: p.color, runs: item.ansiRuns, options: options)
        }

        // Inline accessory (progress / sparkline / control), placed after the
        // label by default or before it when accessory=leading.
        let accessory = renderAccessory(p, options)
        let placeLeading = p.swiftbar.accessory == .leading

        var line = leading
        if placeLeading, !accessory.isEmpty { line += accessory + " " }
        line += label
        if !placeLeading, !accessory.isEmpty { line += (line.isEmpty ? "" : " ") + accessory }

        // Trailing hints: what Enter would do, and any key= equivalent. Skipped
        // for headers (non-interactive) and disabled rows.
        if !isHeader && !disabled {
            if let glyph = actionGlyph(p) { line += " " + dim(glyph, options) }
            if let key = p.key, !key.isEmpty { line += " " + dim("(" + key + ")", options) }
        }
        return line
    }

    // MARK: - Accessories

    private static func renderAccessory(_ p: LineParams, _ options: Options) -> String {
        if let progress = p.progress {
            return progressBar(progress.fraction, color: p.color, options: options)
        }
        if let series = p.sparkline, !series.isEmpty {
            return sparkline(series, color: p.color, options: options)
        }
        if let control = p.control {
            switch control {
            case .toggle(let on):
                return on
                    ? style("[on]", codes: fgCodes(.named("green")) ?? [], options)
                    : dim("[off]", options)
            case .slider(let mn, let mx, let value):
                return sliderTrack(min: mn, max: mx, value: value, color: p.color, options: options)
            }
        }
        return ""
    }

    /// A `progress=` gauge: full/partial `█` blocks for the filled fraction, `░`
    /// for the track, plus a percentage. Eighth-blocks give sub-cell resolution
    /// while staying deterministic.
    static func progressBar(_ fraction: Double, color: VeeColor?, options: Options) -> String {
        let f = max(0, min(1, fraction))
        let cells = progressCells
        let eighths = Int((f * Double(cells) * 8).rounded())
        let full = min(cells, eighths / 8)
        let rem = full < cells ? eighths % 8 : 0
        let partials = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

        var fill = String(repeating: "█", count: full)
        if rem > 0 { fill += partials[rem] }
        let used = full + (rem > 0 ? 1 : 0)
        let track = String(repeating: "░", count: max(0, cells - used))
        let pct = Int((f * 100).rounded())

        let fillStr = color.flatMap(fgCodes).map { style(fill, codes: $0, options) } ?? fill
        return fillStr + dim(track, options) + " " + dim("\(pct)%", options)
    }

    /// A `sparkline=` series as an 8-level block ramp, normalized over the
    /// series' own min…max (a flat series renders at mid-height).
    static func sparkline(_ series: [Double], color: VeeColor?, options: Options) -> String {
        let ramp = Array("▁▂▃▄▅▆▇█")
        guard let mn = series.min(), let mx = series.max() else { return "" }
        let span = mx - mn
        let glyphs = series.map { v -> Character in
            let level = span == 0 ? ramp.count / 2 : Int(((v - mn) / span * Double(ramp.count - 1)).rounded())
            return ramp[min(ramp.count - 1, max(0, level))]
        }
        let s = String(glyphs)
        return color.flatMap(fgCodes).map { style(s, codes: $0, options) } ?? s
    }

    /// A `slider=` as a 10-cell track with a knob at the current value.
    private static func sliderTrack(min lo: Double, max hi: Double, value: Double, color: VeeColor?, options: Options) -> String {
        let cells = 10
        let t = hi == lo ? 0 : max(0, min(1, (value - lo) / (hi - lo)))
        let pos = Int((t * Double(cells - 1)).rounded())
        let left = String(repeating: "─", count: pos)
        let right = String(repeating: "─", count: max(0, cells - 1 - pos))
        let knob = color.flatMap(fgCodes).map { style("●", codes: $0, options) } ?? "●"
        return "[" + dim(left, options) + knob + dim(right, options) + "] " + trim(value)
    }

    // MARK: - Icon / action surfacing

    /// SF Symbols and base64 images can't be drawn in a terminal, so surface
    /// them by name/marker rather than dropping them.
    private static func iconTag(_ p: LineParams, _ options: Options) -> String {
        if let sf = p.swiftbar.sfimage, !sf.isEmpty { return dim("[\(sf)] ", options) }
        if p.image != nil || p.templateImage != nil { return dim("[img] ", options) }
        return ""
    }

    /// A one-glyph hint of what activating the row would do, mirroring
    /// `AppActionDispatcher`'s dispatch order. `toggle`/`slider`/`sparkline`
    /// already show their state inline, so they get no extra glyph.
    private static func actionGlyph(_ p: LineParams) -> String? {
        if p.control != nil { return nil }
        if let shell = p.shell { return shell.openInTerminal ? "▸$" : "$" }
        if p.swiftbar.webview != nil { return "▤" }
        if p.href != nil { return "↗" }
        if let s = p.swiftbar.shortcut, !s.isEmpty { return "⌘" }
        if p.refresh == true { return "⟳" }
        return nil
    }

    // MARK: - ANSI SGR

    /// Styles `text` with the item's `color=` plus any ANSI runs, as real SGR
    /// escapes. When `options.color` is off, returns the text verbatim.
    static func styledText(_ text: String, color: VeeColor?, runs: [AnsiRun], options: Options, extra: [Int] = []) -> String {
        guard options.color else { return text }

        if runs.isEmpty {
            var codes = extra
            if let fg = color.flatMap(fgCodes) { codes += fg }
            return style(text, codes: codes, options)
        }

        // Per-character styling, coalesced into runs of identical SGR.
        let chars = Array(text)
        func codesFor(_ idx: Int) -> [Int] {
            var fg = color.flatMap(fgCodes)
            var bg: [Int]?
            var bold = false, italic = false, underline = false
            for r in runs where r.range.contains(idx) {
                if let f = r.foreground { fg = fgCodes(f) }
                if let b = r.background { bg = bgCodes(b) }
                bold = bold || r.bold
                italic = italic || r.italic
                underline = underline || r.underline
            }
            var c = extra
            if bold { c.append(1) }
            if italic { c.append(3) }
            if underline { c.append(4) }
            if let fg { c += fg }
            if let bg { c += bg }
            return c
        }

        var out = ""
        var i = 0
        while i < chars.count {
            let c = codesFor(i)
            var j = i + 1
            while j < chars.count && codesFor(j) == c { j += 1 }
            out += style(String(chars[i..<j]), codes: c, options)
            i = j
        }
        return out
    }

    private static func dim(_ s: String, _ options: Options) -> String { style(s, codes: [2], options) }

    /// Dims `s` (SGR 2) when `color` is on; returns it verbatim otherwise.
    /// Exposed for the status line and live-loop chrome.
    static func dimmed(_ s: String, color: Bool) -> String {
        color ? "\u{1B}[2m\(s)\u{1B}[0m" : s
    }

    /// Colors `s` with `vc`'s foreground when `color` is on. Exposed for the
    /// status line's health dot.
    static func colored(_ s: String, _ vc: VeeColor, color: Bool) -> String {
        guard color, let codes = fgCodes(vc), !codes.isEmpty else { return s }
        return "\u{1B}[" + codes.map({ String($0) }).joined(separator: ";") + "m" + s + "\u{1B}[0m"
    }

    private static func style(_ s: String, codes: [Int], _ options: Options) -> String {
        guard options.color, !codes.isEmpty, !s.isEmpty else { return s }
        return "\u{1B}[" + codes.map({ String($0) }).joined(separator: ";") + "m" + s + "\u{1B}[0m"
    }

    private static func rule(count: Int, _ options: Options) -> String {
        dim(String(repeating: "─", count: max(1, count)), options)
    }

    // MARK: - Color mapping

    static func fgCodes(_ c: VeeColor) -> [Int]? {
        switch c {
        case .rgb(let r, let g, let b, _): return [38, 2, Int(r), Int(g), Int(b)]
        case .named(let name): return namedForeground(name)
        }
    }

    private static func bgCodes(_ c: VeeColor) -> [Int]? {
        switch c {
        case .rgb(let r, let g, let b, _): return [48, 2, Int(r), Int(g), Int(b)]
        case .named(let name): return namedForeground(name).map(toBackground)
        }
    }

    /// Foreground SGR for a CSS/AppKit color name. Strips `system`/`color`
    /// affixes so `systemRed`/`labelColor` map sensibly; unknown names return
    /// `nil` (rendered in the terminal's default color).
    private static func namedForeground(_ raw: String) -> [Int]? {
        var n = raw.lowercased()
        n = n.replacingOccurrences(of: "system", with: "")
        if n.hasSuffix("color") { n = String(n.dropLast(5)) }
        switch n {
        case "black": return [30]
        case "red": return [31]
        case "green": return [32]
        case "yellow": return [33]
        case "blue": return [34]
        case "magenta": return [35]
        case "cyan", "teal": return [36]
        case "white": return [37]
        case "gray", "grey", "secondarylabel", "tertiarylabel", "quaternarylabel": return [90]
        case "brightred": return [91]
        case "brightgreen": return [92]
        case "brightyellow": return [93]
        case "brightblue": return [94]
        case "brightmagenta", "brightpurple": return [95]
        case "brightcyan": return [96]
        case "brightwhite": return [97]
        case "orange": return [38, 2, 255, 149, 0]
        case "purple", "indigo": return [38, 2, 175, 82, 222]
        case "pink": return [38, 2, 255, 45, 85]
        case "brown": return [38, 2, 162, 132, 94]
        case "mint": return [38, 2, 0, 199, 190]
        case "label", "": return nil
        default: return nil
        }
    }

    /// Converts foreground SGR codes to their background equivalents
    /// (30–37→40–47, 90–97→100–107, 38→48 for truecolor).
    private static func toBackground(_ codes: [Int]) -> [Int] {
        guard let first = codes.first else { return codes }
        if first == 38 { return [48] + codes.dropFirst() }
        if (30...37).contains(first) { return [first + 10] + codes.dropFirst() }
        if (90...97).contains(first) { return [first + 10] + codes.dropFirst() }
        return codes
    }

    /// Formats a Double without a trailing `.0`. `Int(exactly:)` guards the
    /// trap `Int(Double)` takes on |v| ≥ ~9.2e18 (values come from plugin input).
    private static func trim(_ v: Double) -> String {
        if v == v.rounded(), let whole = Int(exactly: v.rounded()) { return String(whole) }
        return String(v)
    }
}
