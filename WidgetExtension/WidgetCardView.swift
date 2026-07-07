import WidgetKit
import SwiftUI
import AppIntents
import VeeWidgetShared

/// Dispatches one plugin's rich `WidgetCard` to its native template (see
/// `docs/design/widget-surface-contract.md` §5 — stat/gauge/trend/list/board).
/// `PluginStatusView` renders this instead of the Tier-0 scrape
/// (`HeroPluginView`/`PluginListView`) whenever the plugin it's showing has a
/// card. Each template is itself `@Environment(\.widgetFamily)`-adaptive, so
/// this one view works across small/medium/large.
struct WidgetCardView: View {
    let pluginID: String
    let card: WidgetCard
    let updated: Date
    let stale: Bool

    var body: some View {
        switch card.template {
        case .stat: StatCardView(pluginID: pluginID, card: card, updated: updated, stale: stale)
        case .gauge: GaugeCardView(pluginID: pluginID, card: card, updated: updated, stale: stale)
        case .trend: TrendCardView(pluginID: pluginID, card: card, updated: updated, stale: stale)
        case .list: ListCardView(pluginID: pluginID, card: card, updated: updated, stale: stale)
        case .board: BoardCardView(pluginID: pluginID, card: card, updated: updated, stale: stale)
        }
    }
}

// MARK: - Shared building blocks

private extension WidgetCard {
    var tintColor: Color { tint?.swiftUIColor ?? .primary }

    /// The headline value's color: a plugin-reported `warning`/`error`
    /// status wins over the declared tint (mirrors `PluginSnapshot.failed`
    /// driving `HeroPluginView`'s red today).
    var valueColor: Color {
        switch status {
        case .error: return .red
        case .warning: return .orange
        case .ok, nil: return tintColor
        }
    }

    /// A status glyph color for the header, or `nil` when healthy/unset.
    var statusGlyphColor: Color? {
        switch status {
        case .error: return .red
        case .warning: return .orange
        case .ok, nil: return nil
        }
    }
}

/// The header row every template shares: glyph, title, and a status glyph
/// when the plugin reports `warning`/`error`.
private struct CardHeader: View {
    let card: WidgetCard

    var body: some View {
        HStack(spacing: 5) {
            if let symbol = card.symbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(card.tintColor)
            }
            Text(card.title ?? "")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let statusColor = card.statusGlyphColor {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
        }
    }
}

/// The headline value text every template shows (or falls back to `•` like
/// the Tier-0 scrape does for an empty title).
private struct CardValueText: View {
    let card: WidgetCard
    var lineLimit: Int = 1

    var body: some View {
        Text((card.value?.isEmpty == false ? card.value : nil) ?? "•")
            .font(.system(.title, design: .rounded)).fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(card.valueColor)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.6)
    }
}

/// The footer row every template shares: freshness, plus up to two action
/// buttons — `refresh`/`shortcut` as `Button(intent:)`, `href` as `Link`
/// (already scheme-filtered by `WidgetCardParser`, so this trusts `url`).
private struct CardFooter: View {
    let pluginID: String
    let card: WidgetCard
    let updated: Date
    let stale: Bool

    var body: some View {
        HStack(spacing: 8) {
            FreshnessLabel(updated: updated, stale: stale)
            Spacer(minLength: 0)
            if #available(macOS 26.0, *) {
                ForEach(Array((card.actions ?? []).prefix(2).enumerated()), id: \.offset) { index, action in
                    CardActionButton(pluginID: pluginID, action: action, index: index)
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private struct CardActionButton: View {
    let pluginID: String
    let action: WidgetCardAction
    let index: Int

    var body: some View {
        switch action.kind {
        case .refresh:
            Button(intent: RefreshPluginWidgetIntent(pluginID: pluginID)) {
                Image(systemName: "arrow.clockwise")
            }
            .font(.caption2)
        case .shortcut:
            Button(intent: RunPluginActionIntent(pluginID: pluginID, actionIndex: index)) {
                Text(action.label)
            }
            .font(.caption2)
        case .href:
            if let urlString = action.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    Text(action.label)
                }
                .font(.caption2)
            }
        }
    }
}

// MARK: - stat

/// Glyph, big `value` in `tint`, `title`/`caption`. The default template.
struct StatCardView: View {
    let pluginID: String
    let card: WidgetCard
    let updated: Date
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(card: card)
            Spacer(minLength: 0)
            CardValueText(card: card, lineLimit: 2)
            if let caption = card.caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            if let detail = card.detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            CardFooter(pluginID: pluginID, card: card, updated: updated, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - gauge

/// Stat + a native `Gauge` from `progress`.
struct GaugeCardView: View {
    let pluginID: String
    let card: WidgetCard
    let updated: Date
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(card: card)
            Spacer(minLength: 0)
            CardValueText(card: card)
            if let progress = card.progress {
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(card.tintColor)
            }
            if let caption = card.caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            CardFooter(pluginID: pluginID, card: card, updated: updated, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - trend

/// Stat + the dependency-free `Sparkline` from `trend`.
struct TrendCardView: View {
    let pluginID: String
    let card: WidgetCard
    let updated: Date
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(card: card)
            Spacer(minLength: 0)
            CardValueText(card: card)
            if let series = card.trend, series.count > 1 {
                Sparkline(values: series)
                    .stroke(card.tintColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(height: 24)
            }
            if let caption = card.caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            CardFooter(pluginID: pluginID, card: card, updated: updated, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - list

/// `title` header + `items` as rows (glyph · label · value), truncated per
/// family: small shows the headline `value`; medium ≤3; large ≤8.
struct ListCardView: View {
    @Environment(\.widgetFamily) private var family
    let pluginID: String
    let card: WidgetCard
    let updated: Date
    let stale: Bool

    private var limit: Int { family == .systemLarge ? 8 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(card: card)
            if family == .systemSmall {
                Spacer(minLength: 0)
                CardValueText(card: card)
            } else {
                let items = card.items ?? []
                ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in
                    CardItemRow(item: item)
                }
                if items.count > limit {
                    Text("+\(items.count - limit) more").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            CardFooter(pluginID: pluginID, card: card, updated: updated, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CardItemRow: View {
    let item: WidgetCardItem

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = item.symbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(item.tint?.swiftUIColor ?? .secondary)
                    .frame(width: 16)
            }
            Text(item.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let value = item.value {
                Text(value)
                    .font(.caption).fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(item.tint?.swiftUIColor ?? .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - board

/// A compact grid of `items` as stat cells (KPI board); small collapses to
/// the headline (open question #1 in the design doc — resolved: collapse).
struct BoardCardView: View {
    @Environment(\.widgetFamily) private var family
    let pluginID: String
    let card: WidgetCard
    let updated: Date
    let stale: Bool

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private var limit: Int { family == .systemLarge ? 8 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(card: card)
            if family == .systemSmall {
                Spacer(minLength: 0)
                CardValueText(card: card)
            } else {
                let cells = Array((card.items ?? []).prefix(limit))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, item in
                        BoardCell(item: item)
                    }
                }
            }
            Spacer(minLength: 0)
            CardFooter(pluginID: pluginID, card: card, updated: updated, stale: stale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct BoardCell: View {
    let item: WidgetCardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(item.tint?.swiftUIColor ?? .secondary)
                }
                Text(item.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text((item.value?.isEmpty == false ? item.value : nil) ?? "•")
                .font(.caption).fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(item.tint?.swiftUIColor ?? .primary)
                .lineLimit(1)
        }
    }
}
