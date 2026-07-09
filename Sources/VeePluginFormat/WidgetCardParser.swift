import Foundation
import VeeWidgetShared

/// Decodes a plugin's `VEE_TARGET=widget` stdout (a single JSON card object,
/// see `docs/design/widget-surface-contract.md` §4) into a `WidgetCard`.
///
/// Never throws: malformed/partial input degrades to `nil` plus a diagnostic
/// (surfaced in the Debug console), exactly like `JSONOutputParser` degrades
/// to the text parser rather than crashing the plugin.
public enum WidgetCardParser {
    /// Parses `stdout`. Returns `(nil, [])` for empty/whitespace-only output
    /// (no card printed — the caller falls back to the Tier-0 scrape) and
    /// `(nil, [diagnostic])` when non-empty output isn't a JSON object.
    public static func parse(_ stdout: String) -> (card: WidgetCard?, diagnostics: [ParseDiagnostic]) {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, []) }
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else {
            return (nil, [ParseDiagnostic(severity: .error, message: "widget output is not a JSON object")])
        }

        let raw: RawWidgetCard
        do {
            raw = try JSONDecoder().decode(RawWidgetCard.self, from: data)
        } catch {
            return (nil, [ParseDiagnostic(severity: .error, message: "widget output is not a JSON object")])
        }

        var diagnostics: [ParseDiagnostic] = []

        var template = WidgetTemplate.stat
        if let rawTemplate = raw.template {
            if let known = WidgetTemplate(rawValue: rawTemplate) {
                template = known
            } else {
                diagnostics.append(.init(severity: .warning, message: "unknown widget template \"\(rawTemplate)\"; using stat"))
            }
        }

        var status: WidgetStatus?
        if let rawStatus = raw.status {
            if let known = WidgetStatus(rawValue: rawStatus) {
                status = known
            } else {
                diagnostics.append(.init(severity: .warning, message: "unknown widget status \"\(rawStatus)\"; ignored"))
            }
        }

        let progress = clampProgress(raw.progress, diagnostics: &diagnostics)
        let trend = finiteTrend(raw.trend, diagnostics: &diagnostics)
        let actions = sanitizedActions(raw.actions, diagnostics: &diagnostics)
        let layout = sanitizedLayout(raw.layout, diagnostics: &diagnostics)

        let card = WidgetCard(
            template: template,
            title: raw.title,
            symbol: raw.symbol,
            tint: raw.tint,
            value: raw.value,
            caption: raw.caption,
            detail: raw.detail,
            status: status,
            progress: progress,
            trend: trend,
            items: raw.items,
            actions: actions,
            refreshAfter: raw.refreshAfter,
            staleAfter: raw.staleAfter,
            layout: layout
        )
        return (card, diagnostics)
    }

    /// Sanitizes an optional layout tree: bounds it (depth/node/text/sparkline
    /// caps) and clamps every numeric field, so the tree the app writes into
    /// the widget snapshot is already safe for the sandboxed extension to walk.
    /// A hostile payload degrades to a bounded tree + diagnostics — never a
    /// throw. Runs app-side by design (the extension only renders).
    private static func sanitizedLayout(_ raw: WidgetNode?, diagnostics: inout [ParseDiagnostic]) -> WidgetNode? {
        guard let raw else { return nil }
        let sanitizer = LayoutSanitizer()
        let result = sanitizer.sanitize(raw)
        diagnostics.append(contentsOf: sanitizer.diagnostics)
        return result
    }

    /// Clamps `progress` to `0...1`; a non-finite value is dropped entirely
    /// (mirrors `JSONOutputParser.applyRichParams`'s finite check), each with
    /// a diagnostic so the drop/clamp is visible in the Debug console.
    private static func clampProgress(_ raw: Double?, diagnostics: inout [ParseDiagnostic]) -> Double? {
        guard let raw else { return nil }
        guard raw.isFinite else {
            diagnostics.append(.init(severity: .warning, message: "progress is not a finite number; dropped"))
            return nil
        }
        let clamped = min(max(raw, 0), 1)
        if clamped != raw {
            diagnostics.append(.init(severity: .warning, message: "progress \(raw) outside 0...1; clamped"))
        }
        return clamped
    }

    /// Drops non-finite entries from `trend`, with a diagnostic if any were
    /// dropped.
    private static func finiteTrend(_ raw: [Double]?, diagnostics: inout [ParseDiagnostic]) -> [Double]? {
        guard let raw else { return nil }
        let finite = raw.filter(\.isFinite)
        if finite.count != raw.count {
            diagnostics.append(.init(severity: .warning, message: "trend contained non-finite values; dropped"))
        }
        return finite
    }

    /// Drops any `href` action whose `url` is missing, unparseable, or
    /// scheme-unsafe — the same scheme filter menu `href=`/`<xbar.abouturl>`
    /// use (`URLScheme.isSafeToOpen`), so a widget button can't be made to
    /// open `file://`/`javascript:`/etc. `refresh`/`shortcut` actions are
    /// untouched (they carry no URL to validate).
    private static func sanitizedActions(_ raw: [WidgetCardAction]?, diagnostics: inout [ParseDiagnostic]) -> [WidgetCardAction]? {
        guard let raw else { return nil }
        return raw.compactMap { action in
            guard action.kind == .href else { return action }
            guard let urlString = action.url, let url = URL(string: urlString), URLScheme.isSafeToOpen(url) else {
                diagnostics.append(.init(severity: .warning, message: "href action \"\(action.label)\" has a missing or unsafe url; dropped"))
                return nil
            }
            return action
        }
    }
}

/// The wire shape of the card payload, decoded loosely so an unknown
/// `template`/`status` string degrades to a diagnostic instead of failing the
/// whole decode (`WidgetTemplate`/`WidgetStatus` themselves stay strict —
/// see `WidgetCard.swift`).
private struct RawWidgetCard: Decodable {
    let template: String?
    let title: String?
    let symbol: String?
    let tint: SnapshotColor?
    let value: String?
    let caption: String?
    let detail: String?
    let status: String?
    let progress: Double?
    let trend: [Double]?
    let items: [WidgetCardItem]?
    let actions: [WidgetCardAction]?
    let refreshAfter: TimeInterval?
    let staleAfter: TimeInterval?
    let layout: WidgetNode?

    enum CodingKeys: String, CodingKey {
        case template, title, symbol, tint, value, caption, detail, status, progress, trend, items, actions, layout
        case refreshAfter = "refresh_after"
        case staleAfter = "stale_after"
    }
}

/// Walks a decoded `WidgetNode` tree once, enforcing the layout guardrails and
/// collecting a diagnostic per kind of violation (deduped so a pathological
/// payload can't spam the Debug console). Mirrors the depth-cap discipline in
/// `JSONOutputParser` — a bounded, total pass that can't overflow the stack or
/// bloat the snapshot the widget extension re-reads on every timeline build.
private final class LayoutSanitizer {
    /// Real layouts are a handful of levels deep (a preset desugars to ~3);
    /// `stat`/`gauge`/`trend`/`list`/`board` all fit well under this.
    static let maxDepth = 8
    /// Total nodes across the whole tree — keeps the snapshot small.
    static let maxNodes = 64
    static let maxTextLength = 512
    static let maxSparklineValues = 256
    static let knownTypes: Set<String> = [
        "vstack", "hstack", "zstack", "grid",
        "text", "image", "gauge", "sparkline", "spacer", "divider"
    ]

    private(set) var diagnostics: [ParseDiagnostic] = []
    private var nodeCount = 0
    private var depthCapped = false
    private var nodeCapped = false
    private var textTruncated = false
    private var sparkTruncated = false
    private var unknownTypes: Set<String> = []

    func sanitize(_ node: WidgetNode) -> WidgetNode? {
        sanitizeNode(node, depth: 0)
    }

    private func sanitizeNode(_ node: WidgetNode, depth: Int) -> WidgetNode? {
        guard nodeCount < Self.maxNodes else {
            if !nodeCapped {
                nodeCapped = true
                warn("layout has more than \(Self.maxNodes) nodes; extra nodes dropped")
            }
            return nil
        }
        nodeCount += 1

        var out = node

        if !Self.knownTypes.contains(node.type), !unknownTypes.contains(node.type) {
            unknownTypes.insert(node.type)
            warn("unknown layout node type \"\(node.type)\"; ignored")
        }

        if let text = out.text, text.count > Self.maxTextLength {
            out.text = String(text.prefix(Self.maxTextLength))
            if !textTruncated {
                textTruncated = true
                warn("layout text longer than \(Self.maxTextLength) characters; truncated")
            }
        }

        if let value = out.value {
            if value.isFinite {
                out.value = min(max(value, 0), 1)
            } else {
                out.value = nil
                warn("layout gauge value is not finite; dropped")
            }
        }

        if let values = out.values {
            var finite = values.filter(\.isFinite)
            if finite.count != values.count {
                warn("layout sparkline contained non-finite values; dropped")
            }
            if finite.count > Self.maxSparklineValues {
                finite = Array(finite.prefix(Self.maxSparklineValues))
                if !sparkTruncated {
                    sparkTruncated = true
                    warn("layout sparkline longer than \(Self.maxSparklineValues) points; truncated")
                }
            }
            out.values = finite
        }

        out.spacing = clampFinite(out.spacing, lo: 0, hi: 64)
        out.minLength = clampFinite(out.minLength, lo: 0, hi: 4096)
        if let columns = out.columns { out.columns = min(max(columns, 1), 4) }
        out.style = sanitizeStyle(out.style)

        if let children = out.children {
            if depth >= Self.maxDepth {
                out.children = []
                if !depthCapped {
                    depthCapped = true
                    warn("layout nested deeper than \(Self.maxDepth) levels; inner nodes dropped")
                }
            } else {
                out.children = children.compactMap { sanitizeNode($0, depth: depth + 1) }
            }
        }

        return out
    }

    private func sanitizeStyle(_ style: WidgetNodeStyle?) -> WidgetNodeStyle? {
        guard var style else { return nil }
        if var font = style.font {
            if let pointSize = font.pointSize {
                font.pointSize = pointSize.isFinite ? min(max(pointSize, 8), 96) : nil
            }
            style.font = font
        }
        style.padding = clampFinite(style.padding, lo: 0, hi: 64)
        if let lineLimit = style.lineLimit { style.lineLimit = min(max(lineLimit, 1), 20) }
        if let minScale = style.minScale {
            style.minScale = minScale.isFinite ? min(max(minScale, 0.3), 1) : nil
        }
        return style
    }

    private func clampFinite(_ value: Double?, lo: Double, hi: Double) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, lo), hi)
    }

    private func warn(_ message: String) {
        diagnostics.append(.init(severity: .warning, message: message))
    }
}
