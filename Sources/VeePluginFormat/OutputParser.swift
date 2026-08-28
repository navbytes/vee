import Foundation

/// Parses a plugin's stdout into a `ParsedOutput`. Never throws: malformed
/// input yields best-effort output plus diagnostics.
public enum OutputParser {
    public static func parse(_ stdout: String) -> ParsedOutput {
        var diagnostics: [ParseDiagnostic] = []
        var lines = splitLines(stdout)
        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
            diagnostics.append(.init(
                severity: .warning,
                message: "output truncated at \(maxLines) lines; a menu this long can't be used"))
        }

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
        // Tolerate CRLF line endings (Windows-authored scripts): strip exactly
        // one trailing "\r" per line so `---\r`/`--\r`/`~~~\r` still match their
        // separators. `.whitespaces` trimming elsewhere doesn't catch "\r", and
        // this is deliberately not a blanket trim — trailing spaces are
        // significant for param parsing.
        return lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
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
        // Dedup flag: a pathologically deep input re-hits the maxDepth ceiling on
        // every remaining line (thousands, for a 20000-line submenu chain) — one
        // diagnostic says it as well as thousands would.
        var depthCapped = false

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
            // Also clamp by maxDepth here, not only in convert/convertItem below:
            // openItems nests one BuildItem *class instance* inside another per
            // level, so without this an unbounded submenu chain builds an
            // unbounded reference graph — which recursively deinitializes itself
            // when `root` goes out of scope, a stack-overflow risk independent of
            // (and in addition to) the convert-recursion one those two guard.
            let depth = min(rawDepth, openItems.count, maxDepth)
            if depth < rawDepth {
                if depth >= maxDepth {
                    if !depthCapped {
                        depthCapped = true
                        diagnostics.append(.init(severity: .warning, message: "submenu depth exceeded; truncated"))
                    }
                } else {
                    diagnostics.append(.init(severity: .warning, message: "submenu depth jumped; clamped to \(depth)"))
                }
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

        return root.map { convert($0, depth: 0, into: &diagnostics) }
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

    /// Caps how many lines of plugin output become menu rows.
    ///
    /// Submenu *depth* has been capped at `maxDepth` since the recursion could
    /// overflow the stack; breadth had no limit at all. The 8 MB capture cap in
    /// `SystemProcessRunner` bounds it only at around 400,000 rows — every one
    /// of which becomes a real `NSMenuItem` with a real view, so a plugin stuck
    /// in a loop takes the UI down long before it runs out of output.
    ///
    /// 2000 is far past usable: an `NSMenu` is a scrolling column, and nobody
    /// finds anything in the two-thousandth row of one. Set generously on
    /// purpose — the point is to bound a runaway, not to second-guess an author
    /// who legitimately lists a lot of things — and truncation is always
    /// reported rather than silent.
    private static let maxLines = 2000

    /// Guards the recursive `BuildEntry` → `MenuNode` conversion against
    /// pathologically deep submenu chains — a plugin emitting thousands of
    /// progressively-deeper `--` lines would otherwise recurse without limit and
    /// overflow the stack (SIGSEGV). Mirrors `JSONOutputParser`'s identical
    /// `maxDepth` cap on its own tree mapping.
    private static let maxDepth = 64

    private static func convert(_ entry: BuildEntry, depth: Int, into diagnostics: inout [ParseDiagnostic]) -> MenuNode {
        switch entry {
        case .separator:
            return .separator
        case .item(let bi):
            return .item(convertItem(bi, depth: depth, into: &diagnostics))
        }
    }

    private static func convertItem(_ bi: BuildItem, depth: Int, into diagnostics: inout [ParseDiagnostic]) -> MenuItem {
        guard depth < maxDepth else {
            if !bi.children.isEmpty || bi.alternate != nil {
                diagnostics.append(.init(severity: .warning, message: "submenu depth exceeded; truncated"))
            }
            return MenuItem(text: bi.text, params: bi.params, ansiRuns: bi.runs)
        }
        return MenuItem(
            text: bi.text,
            params: bi.params,
            ansiRuns: bi.runs,
            submenu: bi.children.map { convert($0, depth: depth + 1, into: &diagnostics) },
            alternate: bi.alternate.map { convertItem($0, depth: depth + 1, into: &diagnostics) }
        )
    }
}
