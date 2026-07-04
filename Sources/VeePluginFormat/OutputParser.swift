import Foundation

/// Parses a plugin's stdout into a `ParsedOutput`. Never throws: malformed
/// input yields best-effort output plus diagnostics.
public enum OutputParser {
    public static func parse(_ stdout: String) -> ParsedOutput {
        var diagnostics: [ParseDiagnostic] = []
        let lines = splitLines(stdout)

        // Section split on the first top-level `---` (a line that is exactly
        // three dashes). Title above, body below.
        let separatorIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "---" }
        let titleRaw = separatorIndex.map { Array(lines[0..<$0]) } ?? lines
        let bodyRaw = separatorIndex.map { Array(lines[($0 + 1)...]) } ?? []

        let titleLines = titleRaw
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line -> TitleLine in
                let (text, pairs, d1) = LineParser.splitTextAndParams(line)
                let (params, d2) = LineParser.mapParams(pairs)
                diagnostics += d1 + d2
                let (display, runs) = renderText(text, params: params)
                return TitleLine(text: display, params: params, ansiRuns: runs)
            }

        let body = buildTree(bodyRaw, into: &diagnostics)

        return ParsedOutput(titleLines: titleLines, body: body, diagnostics: diagnostics)
    }

    // MARK: - Lines

    private static func splitLines(_ s: String) -> [String] {
        var lines = s.components(separatedBy: "\n")
        // Drop a single trailing empty line produced by a final newline.
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Applies emojize (default on) then ANSI parsing (default on) to a line's
    /// text, returning the display string and its style runs.
    private static func renderText(_ raw: String, params: LineParams) -> (String, [AnsiRun]) {
        var text = raw
        // Trim first (default on) so ANSI run offsets are computed against the
        // final text. Whitespace trimming never removes escape sequences.
        if params.trim != false { text = text.trimmingCharacters(in: .whitespaces) }
        if params.emojize != false { text = Emoji.replace(text) }
        if params.ansi != false {
            return Ansi.parse(text)
        }
        return (text, [])
    }

    // MARK: - Tree building

    private final class BuildItem {
        var text: String
        var params: LineParams
        var runs: [AnsiRun]
        var children: [BuildEntry] = []
        var alternate: BuildItem?
        init(text: String, params: LineParams, runs: [AnsiRun]) {
            self.text = text; self.params = params; self.runs = runs
        }
    }

    private enum BuildEntry {
        case item(BuildItem)
        case separator
    }

    private static func buildTree(_ rawLines: [String], into diagnostics: inout [ParseDiagnostic]) -> [MenuNode] {
        var root: [BuildEntry] = []
        var openItems: [BuildItem] = [] // openItems[d] = current parent at depth d

        func container(atDepth d: Int) -> (append: (BuildEntry) -> Void, lastItem: () -> BuildItem?) {
            if d == 0 {
                return ({ root.append($0) }, { if case .item(let it) = root.last { return it } else { return nil } })
            }
            let parent = openItems[d - 1]
            return ({ parent.children.append($0) }, { if case .item(let it) = parent.children.last { return it } else { return nil } })
        }

        for line in rawLines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let (rawDepth, isSeparator, content) = classify(line)
            let depth = min(rawDepth, openItems.count)
            if depth < rawDepth {
                diagnostics.append(.init(severity: .warning, message: "submenu depth jumped; clamped to \(depth)"))
            }

            let c = container(atDepth: depth)

            if isSeparator {
                c.append(.separator)
                openItems = Array(openItems.prefix(depth))
                continue
            }

            let (text, pairs, d1) = LineParser.splitTextAndParams(content)
            let (params, d2) = LineParser.mapParams(pairs)
            diagnostics += d1 + d2
            let (display, runs) = renderText(text, params: params)
            let item = BuildItem(text: display, params: params, runs: runs)

            if params.alternate == true {
                if let prev = c.lastItem() {
                    prev.alternate = item
                } else {
                    diagnostics.append(.init(severity: .warning, message: "alternate item has no preceding item"))
                    c.append(.item(item))
                    openItems = Array(openItems.prefix(depth)) + [item]
                }
            } else {
                c.append(.item(item))
                openItems = Array(openItems.prefix(depth)) + [item]
            }
        }

        return root.map(convert)
    }

    /// Classifies a body line: leading-dash depth, whether it's a separator, and
    /// the remaining content (for items).
    private static func classify(_ line: String) -> (depth: Int, isSeparator: Bool, content: String) {
        let dashCount = line.prefix { $0 == "-" }.count
        let rest = String(line.dropFirst(dashCount))
        let isAllDashes = rest.trimmingCharacters(in: .whitespaces).isEmpty && dashCount >= 3

        if isAllDashes {
            // `---` = depth 0, `-----` = depth 1, `-------` = depth 2, …
            let depth = max(0, (dashCount - 3) / 2)
            return (depth, true, "")
        }
        // Items are prefixed with `--` per submenu level.
        let depth = dashCount / 2
        let content = String(line.dropFirst(depth * 2))
        return (depth, false, content)
    }

    private static func convert(_ entry: BuildEntry) -> MenuNode {
        switch entry {
        case .separator:
            return .separator
        case .item(let bi):
            return .item(convertItem(bi))
        }
    }

    private static func convertItem(_ bi: BuildItem) -> MenuItem {
        MenuItem(
            text: bi.text,
            params: bi.params,
            ansiRuns: bi.runs,
            submenu: bi.children.map(convert),
            alternate: bi.alternate.map(convertItem)
        )
    }
}
