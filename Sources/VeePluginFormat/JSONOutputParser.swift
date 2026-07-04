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
        let body = (menu.items ?? []).map(node(from:))
        return ParsedOutput(titleLines: titleLines, body: body)
    }

    // MARK: - Mapping

    private static func node(from item: JSONItem) -> MenuNode {
        if item.separator == true { return .separator }
        return .item(menuItem(from: item))
    }

    private static func menuItem(from item: JSONItem) -> MenuItem {
        MenuItem(
            text: item.text ?? "",
            params: params(from: item),
            submenu: (item.submenu ?? []).map(node(from:)),
            alternate: item.alternate.map(menuItem(from:))
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
        return p
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
    let submenu: [JSONItem]?
    let alternate: JSONItem?
}
