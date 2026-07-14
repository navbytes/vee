import Foundation
import VeePluginFormat

/// Pretty-prints a `ParsedOutput` as an indented text tree for `vee render`.
/// Pure and deterministic so it is unit-testable without any I/O.
public enum TreeRenderer {
    /// Renders the title lines followed by an indented dropdown tree.
    public static func render(_ output: ParsedOutput) -> String {
        var lines: [String] = []

        for title in output.titleLines {
            lines.append(renderTitle(title))
        }

        if !output.body.isEmpty {
            lines.append("---")
            for node in output.body {
                renderNode(node, depth: 0, into: &lines)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Title

    private static func renderTitle(_ title: TitleLine) -> String {
        var line = title.text.isEmpty ? "(empty)" : title.text
        let annotations = paramAnnotations(title.params)
        if !annotations.isEmpty {
            line += "  [" + annotations.joined(separator: " ") + "]"
        }
        return line
    }

    // MARK: - Nodes

    private static func renderNode(_ node: MenuNode, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        switch node {
        case .separator:
            lines.append(indent + "───")
        case .item(let item):
            lines.append(indent + renderItem(item))
            if let alt = item.alternate {
                lines.append(indent + "⌥ " + renderItem(alt))
            }
            for child in item.submenu {
                renderNode(child, depth: depth + 1, into: &lines)
            }
        }
    }

    private static func renderItem(_ item: MenuItem) -> String {
        var line = item.text.isEmpty ? "(empty)" : item.text
        let annotations = paramAnnotations(item.params)
        if !annotations.isEmpty {
            line += "  [" + annotations.joined(separator: " ") + "]"
        }
        return line
    }

    // MARK: - Parameter surfacing

    /// Surfaces the key params (href/shell/color/progress/toggle/slider/
    /// sparkline, …) as compact `key=value` annotations, in a stable order.
    private static func paramAnnotations(_ p: LineParams) -> [String] {
        var out: [String] = []

        if let href = p.href { out.append("href=\(href.absoluteString)") }
        if let shell = p.shell {
            var cmd = shell.launchPath
            if !shell.arguments.isEmpty { cmd += " " + shell.arguments.joined(separator: " ") }
            out.append("shell=\(cmd)")
            if shell.openInTerminal { out.append("terminal") }
        }
        if let color = p.color { out.append("color=\(describe(color))") }
        if let progress = p.progress {
            out.append(String(format: "progress=%.2f", progress.fraction))
        }
        if let control = p.control {
            switch control {
            case .toggle(let on):
                out.append("toggle=\(on ? "on" : "off")")
            case .slider(let min, let max, let value):
                out.append("slider=\(trim(min)),\(trim(max)),\(trim(value))")
            }
        }
        if let sparkline = p.sparkline {
            out.append("sparkline=[\(sparkline.map(trim).joined(separator: ","))]")
        }
        if let sfimage = p.swiftbar.sfimage { out.append("sfimage=\(sfimage)") }
        if p.refresh == true { out.append("refresh") }
        if p.disabled == true { out.append("disabled") }

        return out
    }

    private static func describe(_ color: VeeColor) -> String {
        switch color {
        case .named(let name): return name
        case .rgb(let r, let g, let b, let a):
            return a == 255
                ? String(format: "#%02x%02x%02x", r, g, b)
                : String(format: "#%02x%02x%02x%02x", r, g, b, a)
        }
    }

    /// Formats a Double without a trailing `.0` for whole numbers.
    /// `Int(exactly:)` because `Int.init(Double)` traps on |v| ≥ ~9.2e18 and
    /// the value comes from plugin output.
    private static func trim(_ v: Double) -> String {
        if v == v.rounded(), let whole = Int(exactly: v.rounded()) { return String(whole) }
        return String(v)
    }
}
