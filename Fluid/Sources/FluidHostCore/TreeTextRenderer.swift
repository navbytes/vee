import FluidProtocol

/// Draws a view tree as plain text: for `fluidctl render`, for tests, and for
/// an agent that wants to read what a plugin shows without a screen.
///
/// Action ids are printed next to the controls that carry them, so the output
/// doubles as a list of what `fluidctl render --event <id>` can press.
public enum TreeTextRenderer {
    public static func render(_ node: ViewNode, showActions: Bool = true) -> String {
        lines(node, depth: 0, showActions: showActions).joined(separator: "\n")
    }

    static func lines(_ node: ViewNode, depth: Int, showActions: Bool) -> [String] {
        let pad = String(repeating: "  ", count: depth)
        func tag(_ id: ActionID) -> String { showActions ? "  {\(id)}" : "" }

        switch node {
        case .text(let string, let style, let role):
            let body = style == .title ? "# \(string)" : string
            return [pad + body + roleSuffix(role)]
        case .label(let title, let symbol, let role):
            return [pad + "[\(symbol)] \(title)" + roleSuffix(role)]
        case .stack(.horizontal, _, let children):
            let parts = children.map { lines($0, depth: 0, showActions: showActions).joined(separator: " ") }
            return [pad + parts.joined(separator: "  ")]
        case .stack(.vertical, _, let children):
            return children.flatMap { lines($0, depth: depth, showActions: showActions) }
        case .list(let searchable, let children):
            let header = pad + (searchable ? "List (searchable)" : "List")
            return [header] + children.flatMap { lines($0, depth: depth + 1, showActions: showActions) }
        case .section(let title, let children):
            let header = pad + "-- \(title ?? "") --"
            return [header] + children.flatMap { lines($0, depth: depth, showActions: showActions) }
        case .row(let row):
            var line = pad + "* " + row.title
            if let subtitle = row.subtitle { line += " - \(subtitle)" }
            for accessory in row.accessories {
                line += "  " + lines(accessory, depth: 0, showActions: showActions).joined(separator: " ")
            }
            if !row.actions.isEmpty {
                let actions = row.actions.map { action in
                    action.title + (action.shortcut.map { " (\($0))" } ?? "") + tag(action.id)
                }
                line += "  <" + actions.joined(separator: ", ") + ">"
            }
            return [line]
        case .badge(let text, let role):
            return [pad + "[\(text)]" + roleSuffix(role)]
        case .button(let title, _, let role, let action):
            return [pad + "(\(title))" + roleSuffix(role) + tag(action)]
        case .toggle(let title, let isOn, let action):
            return [pad + (isOn ? "[x] " : "[ ] ") + title + tag(action)]
        case .progress(let value, let total, let label, _):
            let fraction = total > 0 ? min(1, max(0, value / total)) : 0
            let filled = Int((fraction * 10).rounded())
            let bar = String(repeating: "#", count: filled) + String(repeating: ".", count: 10 - filled)
            return [pad + (label.map { "\($0) " } ?? "") + "[\(bar)] \(Int((fraction * 100).rounded()))%"]
        case .divider:
            return [pad + "----"]
        }
    }

    private static func roleSuffix(_ role: Role) -> String {
        switch role {
        case .primary, .secondary, .accent: return ""
        case .success, .warning, .critical: return " (\(role.rawValue))"
        }
    }
}
