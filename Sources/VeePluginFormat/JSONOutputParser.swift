import Foundation

/// Decodes Vee's optional structured-JSON output format into a `ParsedOutput`.
/// A plugin opts in by printing a JSON object with a `"vee"` version key, e.g.
///
/// ```json
/// {"vee":1,"title":[{"text":"CPU 12%","color":"green"}],
///  "items":[{"text":"Details","href":"https://…"},{"separator":true}]}
/// ```
///
/// Returns `nil` when the text isn't our JSON, so callers fall back to the text
/// parser.
public enum JSONOutputParser {
    public static let version = 1

    public static func parse(_ text: String) -> ParsedOutput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        guard let menu = try? JSONDecoder().decode(JSONMenu.self, from: data) else { return nil }

        var diagnostics: [ParseDiagnostic] = []
        let titleLines = (menu.title ?? []).map {
            TitleLine(text: $0.text, params: lineParams(color: $0.color, sfimage: $0.sfimage, size: $0.size))
        }
        let body = (menu.items ?? []).map { node(from: $0, depth: 0, diagnostics: &diagnostics) }
        return ParsedOutput(titleLines: titleLines, body: body, diagnostics: diagnostics)
    }

    // MARK: - Mapping

    /// Guards the mapping recursion against pathologically-nested input. Foundation's
    /// `JSONDecoder` already rejects input past its own (~512-level) depth limit
    /// before we get here, but we don't rely on that undocumented behavior: the
    /// mapping caps its own depth so a deep `submenu`/`alternate` chain can never
    /// overflow the stack. Real menus are only a few levels deep.
    private static let maxDepth = 64

    private static func node(from item: JSONItem, depth: Int, diagnostics: inout [ParseDiagnostic]) -> MenuNode {
        if item.separator == true { return .separator }
        return .item(menuItem(from: item, depth: depth, diagnostics: &diagnostics))
    }

    private static func menuItem(from item: JSONItem, depth: Int, diagnostics: inout [ParseDiagnostic]) -> MenuItem {
        let children = depth >= maxDepth ? [] : (item.submenu ?? []).map { node(from: $0, depth: depth + 1, diagnostics: &diagnostics) }
        let itemParams = params(from: item, diagnostics: &diagnostics)
        let alternate = depth >= maxDepth ? nil : item.alternate.map { menuItem(from: $0, depth: depth + 1, diagnostics: &diagnostics) }
        return MenuItem(text: item.text ?? "", params: itemParams, submenu: children, alternate: alternate)
    }

    private static func params(from item: JSONItem, diagnostics: inout [ParseDiagnostic]) -> LineParams {
        var p = lineParams(color: item.color, sfimage: item.sfimage, size: item.size)
        p.href = item.href.flatMap(URL.init(string:)).flatMap { URLScheme.isSafeToOpen($0) ? $0 : nil }
        if let shell = item.shell {
            p.shell = ShellCommand(launchPath: shell, arguments: item.params ?? [], openInTerminal: item.terminal ?? false)
        }
        p.refresh = item.refresh
        p.disabled = item.disabled
        p.swiftbar.header = item.header
        p.swiftbar.checked = item.checked
        p.swiftbar.tooltip = item.tooltip
        applyRichParams(from: item, to: &p, diagnostics: &diagnostics)
        return p
    }

    /// Maps the structured-JSON rich params onto the same `LineParams` fields the
    /// text parser sets, with identical validation (non-finite values rejected,
    /// ranges clamped) so JSON and text produce the same model.
    private static func applyRichParams(from item: JSONItem, to p: inout LineParams, diagnostics: inout [ParseDiagnostic]) {
        if let series = item.sparkline?.filter(\.isFinite), !series.isEmpty {
            p.sparkline = series
        }
        if let on = item.toggle {
            p.control = .toggle(on: on)
        } else if let s = item.slider, s.min.isFinite, s.max.isFinite, s.value.isFinite, s.min < s.max {
            p.control = .slider(min: s.min, max: s.max, value: Swift.min(Swift.max(s.value, s.min), s.max))
        }
        if let raw = item.progress, raw.isFinite {
            p.progress = ProgressParams(
                fraction: Swift.min(Swift.max(raw, 0), 1),
                trackColor: item.trackColor.flatMap(VeeColor.parse),
                width: item.progressWidth.flatMap { $0.isFinite ? $0 : nil },
                height: item.progressHeight.flatMap { $0.isFinite ? $0 : nil }
            )
        }
        if let chart = item.chart {
            if let kind = ChartKind(rawValue: chart.kind.lowercased()) {
                p.swiftbar.chart = ChartParams.make(
                    kind: kind,
                    values: chart.values ?? [],
                    labels: chart.labels ?? [],
                    // Positional, like the text protocol's `chartcolors=`: an
                    // entry that doesn't parse stays a hole and takes the
                    // palette slot, rather than shifting later colors.
                    colors: (chart.colors ?? []).map(VeeColor.parse),
                    width: chart.w?.points.flatMap { $0.isFinite ? $0 : nil },
                    height: chart.h.flatMap { $0.isFinite ? $0 : nil },
                    isFullWidth: chart.w?.isFull ?? false,
                    diagnostics: &diagnostics
                )
            } else {
                diagnostics.append(.init(
                    severity: .warning,
                    message: "chart.kind expects 'pie', 'donut', or 'stackedbar'"
                ))
            }
        }
        if let raw = item.accessory {
            if let placement = AccessoryPlacement(rawValue: raw.lowercased()) {
                p.swiftbar.accessory = placement
            } else if !raw.isEmpty {
                // Parity with LineParser's accessory= diagnostic (was silent
                // here — defaulted with no feedback for the same bad input).
                diagnostics.append(.init(severity: .warning, message: "accessory= expects 'leading' or 'trailing'"))
            }
        }
    }

    private static func lineParams(color: String?, sfimage: String?, size: Double?) -> LineParams {
        var p = LineParams()
        p.color = color.flatMap(VeeColor.parse)
        p.size = size
        p.swiftbar.sfimage = sfimage
        return p
    }
}

public extension OutputParser {
    /// Parses a plugin's stdout: structured JSON when opted into (a `{"vee":…}`
    /// object), otherwise the xbar/SwiftBar text format.
    static func parseAuto(_ text: String) -> ParsedOutput {
        JSONOutputParser.parse(text) ?? parse(text)
    }
}

private struct JSONMenu: Decodable {
    let vee: Int
    let title: [JSONTitle]?
    let items: [JSONItem]?
}

private struct JSONTitle: Decodable {
    let text: String
    let color: String?
    let sfimage: String?
    let size: Double?
}

private final class JSONItem: Decodable {
    let text: String?
    let separator: Bool?
    let color: String?
    let href: String?
    let shell: String?
    let params: [String]?
    let terminal: Bool?
    let refresh: Bool?
    let sfimage: String?
    let size: Double?
    let disabled: Bool?
    let checked: Bool?
    let tooltip: String?
    let header: Bool?
    // Rich params (Vee-native inline controls), mirroring the text protocol.
    let sparkline: [Double]?
    let toggle: Bool?
    let slider: JSONSlider?
    let progress: Double?
    let trackColor: String?
    let progressWidth: Double?
    let progressHeight: Double?
    let accessory: String?
    let chart: JSONChart?
    let submenu: [JSONItem]?
    let alternate: JSONItem?
}

private struct JSONSlider: Decodable {
    let min: Double
    let max: Double
    let value: Double
}

/// The structured-JSON spelling of `pie=`/`donut=`/`stackedbar=`. One object
/// rather than three sibling keys, because the shape is a property of the same
/// data — mirroring `ChartParams`, which the text protocol also collapses to.
private struct JSONChart: Decodable {
    let kind: String
    let values: [Double]?
    let labels: [String]?
    let colors: [String]?
    /// Inline size in points, the JSON spelling of `chartw=`/`charth=`. `w`
    /// also accepts the string `"full"`, matching `chartw=full`.
    let w: JSONChartWidth?
    let h: Double?
}

/// `chart.w`: a number of points, or `"full"` to stretch to the row's width.
private enum JSONChartWidth: Decodable {
    case points(Double)
    case full

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .points(number)
            return
        }
        let text = try container.decode(String.self)
        guard text.lowercased() == "full" else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "chart.w expects a number or \"full\"")
        }
        self = .full
    }

    var points: Double? { if case .points(let value) = self { return value } else { return nil } }
    var isFull: Bool { if case .full = self { return true } else { return false } }
}
