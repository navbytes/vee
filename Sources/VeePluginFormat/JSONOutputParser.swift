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

        let titleLines = (menu.title ?? []).map {
            TitleLine(text: $0.text, params: lineParams(color: $0.color, sfimage: $0.sfimage, size: $0.size))
        }
        let body = (menu.items ?? []).map { node(from: $0, depth: 0) }
        return ParsedOutput(titleLines: titleLines, body: body)
    }

    // MARK: - Mapping

    /// Guards the mapping recursion against pathologically-nested input. Foundation's
    /// `JSONDecoder` already rejects input past its own (~512-level) depth limit
    /// before we get here, but we don't rely on that undocumented behavior: the
    /// mapping caps its own depth so a deep `submenu`/`alternate` chain can never
    /// overflow the stack. Real menus are only a few levels deep.
    private static let maxDepth = 64

    private static func node(from item: JSONItem, depth: Int) -> MenuNode {
        if item.separator == true { return .separator }
        return .item(menuItem(from: item, depth: depth))
    }

    private static func menuItem(from item: JSONItem, depth: Int) -> MenuItem {
        let children = depth >= maxDepth ? [] : (item.submenu ?? []).map { node(from: $0, depth: depth + 1) }
        return MenuItem(
            text: item.text ?? "",
            params: params(from: item),
            submenu: children,
            alternate: depth >= maxDepth ? nil : item.alternate.map { menuItem(from: $0, depth: depth + 1) }
        )
    }

    private static func params(from item: JSONItem) -> LineParams {
        var p = lineParams(color: item.color, sfimage: item.sfimage, size: item.size)
        p.href = item.href.flatMap(URL.init(string:))
        if let shell = item.shell {
            p.shell = ShellCommand(launchPath: shell, arguments: item.params ?? [], openInTerminal: item.terminal ?? false)
        }
        p.refresh = item.refresh
        p.disabled = item.disabled
        p.swiftbar.checked = item.checked
        p.swiftbar.tooltip = item.tooltip
        applyRichParams(from: item, to: &p)
        return p
    }

    /// Maps the structured-JSON rich params onto the same `LineParams` fields the
    /// text parser sets, with identical validation (non-finite values rejected,
    /// ranges clamped) so JSON and text produce the same model.
    private static func applyRichParams(from item: JSONItem, to p: inout LineParams) {
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
    // Rich params (Vee-native inline controls), mirroring the text protocol.
    let sparkline: [Double]?
    let toggle: Bool?
    let slider: JSONSlider?
    let progress: Double?
    let trackColor: String?
    let progressWidth: Double?
    let progressHeight: Double?
    let submenu: [JSONItem]?
    let alternate: JSONItem?
}

private struct JSONSlider: Decodable {
    let min: Double
    let max: Double
    let value: Double
}
