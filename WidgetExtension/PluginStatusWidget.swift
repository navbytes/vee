import WidgetKit
import SwiftUI
import AppIntents
import VeeWidgetShared

/// A timeline entry carrying the whole current snapshot plus the widget's plugin
/// selection; the view filters and lays out per family.
struct PluginStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Selected plugin ids, or `nil` for "show all".
    let selection: [String]?
}

/// Reads the snapshot file the app publishes (via `VeeWidgetShared`). The app
/// drives timely updates by calling `WidgetCenter.reloadAllTimelines()` when
/// content changes (throttled), so the long timeline policy below is just the
/// in-budget fallback. `AppIntentTimelineProvider` gives each widget instance its
/// own `SelectPluginsIntent` configuration.
struct PluginStatusProvider: AppIntentTimelineProvider {
    typealias Entry = PluginStatusEntry
    typealias Intent = SelectPluginsIntent

    private func currentSnapshot() -> WidgetSnapshot {
        VeeWidgetSharing.shared.read() ?? .empty()
    }

    func placeholder(in context: Context) -> PluginStatusEntry {
        PluginStatusEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                plugins: [
                    PluginSnapshot(id: "disk", name: "disk", title: "72%", updated: Date(),
                                   color: .named("green"), symbolName: "internaldrive",
                                   progress: 0.72, interval: 30),
                    PluginSnapshot(id: "cpu", name: "cpu", title: "38%", updated: Date(),
                                   symbolName: "cpu", sparkline: [2, 3, 5, 4, 6, 5, 7], interval: 5),
                ],
                generated: Date()
            ),
            selection: nil
        )
    }

    func snapshot(for configuration: SelectPluginsIntent, in context: Context) async -> PluginStatusEntry {
        PluginStatusEntry(date: Date(), snapshot: currentSnapshot(), selection: configuration.selectedIDs)
    }

    func timeline(for configuration: SelectPluginsIntent, in context: Context) async -> Timeline<PluginStatusEntry> {
        let entry = PluginStatusEntry(date: Date(), snapshot: currentSnapshot(), selection: configuration.selectedIDs)
        // Refresh-on-change is push-driven by the app; this is just a safety net.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
    }
}

struct PluginStatusWidget: Widget {
    static let kind = "com.vee.app.PluginStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectPluginsIntent.self, provider: PluginStatusProvider()) { entry in
            PluginStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Vee Plugins")
        .description("Live output from your Vee menu-bar plugins. Choose which plugins to show.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PluginStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PluginStatusEntry

    /// The plugins to show: the configured selection (in the user's chosen order)
    /// or, when unset, all of them name-sorted.
    private var plugins: [PluginSnapshot] {
        let all = entry.snapshot.plugins
        guard let selection = entry.selection else {
            return all.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return selection.compactMap { byID[$0] }
    }

    private var listLimit: Int { family == .systemLarge ? 8 : 4 }

    var body: some View {
        if plugins.isEmpty {
            EmptyPluginsView()
        } else if plugins.count == 1, let card = plugins[0].card {
            // A widget dedicated to one rich-card plugin renders the native
            // template full-tile (itself family-adaptive) instead of the
            // Tier-0 scrape — see docs/design/widget-surface-contract.md §5.
            // A multi-plugin selection always keeps the scraped hero/list
            // below unchanged, even for plugins that have a card: a
            // list/board template doesn't fit inside one row of a roundup.
            WidgetCardView(pluginID: plugins[0].id, card: card, updated: plugins[0].updated, stale: plugins[0].isStale(asOf: Date()))
        } else if family == .systemSmall {
            HeroPluginView(plugin: plugins[0], extra: plugins.count - 1)
        } else {
            PluginListView(plugins: plugins, limit: listLimit)
        }
    }
}

/// Small family: one plugin as a dashboard tile — glyph, big value in its color,
/// a gauge or sparkline when the plugin publishes one, and a freshness caption.
struct HeroPluginView: View {
    let plugin: PluginSnapshot
    /// Count of other selected plugins not shown in the hero (for a subtle hint).
    var extra: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let symbol = plugin.symbolName {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(plugin.glyphColor)
                }
                Text(plugin.name)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            Text(plugin.title.isEmpty ? "•" : plugin.title)
                .font(.system(.title, design: .rounded)).fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(plugin.failed ? AnyShapeStyle(Color.red) : AnyShapeStyle(plugin.valueColor))
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            if let progress = plugin.progress {
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(plugin.valueColor)
            } else if let series = plugin.sparkline, series.count > 1 {
                Sparkline(values: series)
                    .stroke(plugin.valueColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(height: 24)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                FreshnessLabel(updated: plugin.updated, stale: plugin.isStale(asOf: Date()))
                Spacer(minLength: 0)
                if extra > 0 {
                    Text("+\(extra)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Medium/large: an enriched row per plugin — glyph, name, colored value, an
/// inline gauge when present, and per-plugin freshness.
struct PluginListView: View {
    let plugins: [PluginSnapshot]
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "menubar.rectangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Vee")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(plugins.prefix(limit)) { plugin in
                PluginRow(plugin: plugin)
            }
            if plugins.count > limit {
                Text("+\(plugins.count - limit) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PluginRow: View {
    let plugin: PluginSnapshot

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = plugin.symbolName {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(plugin.glyphColor)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(plugin.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                FreshnessLabel(updated: plugin.updated, stale: plugin.isStale(asOf: Date()))
            }
            Spacer(minLength: 6)
            if let progress = plugin.progress {
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(plugin.valueColor)
                    .frame(width: 44)
            }
            Text(plugin.title.isEmpty ? "•" : plugin.title)
                .font(.caption).fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(plugin.failed ? AnyShapeStyle(Color.red) : AnyShapeStyle(plugin.valueColor))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct EmptyPluginsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "menubar.rectangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Vee")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Spacer()
            Text("No plugins running")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
