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
            actions: raw.actions,
            refreshAfter: raw.refreshAfter,
            staleAfter: raw.staleAfter
        )
        return (card, diagnostics)
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

    enum CodingKeys: String, CodingKey {
        case template, title, symbol, tint, value, caption, detail, status, progress, trend, items, actions
        case refreshAfter = "refresh_after"
        case staleAfter = "stale_after"
    }
}
