import WidgetKit
import SwiftUI
import VeeWidgetShared

/// A timeline entry carrying the whole current snapshot; the view decides how
/// many plugins to show for the family it's rendered at.
struct PluginStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the snapshot file the app publishes (via `VeeWidgetShared`). The app
/// drives timely updates by calling `WidgetCenter.reloadAllTimelines()` when
/// content changes (throttled), so the long timeline policy below is just the
/// in-budget fallback.
struct PluginStatusProvider: TimelineProvider {
    private func currentSnapshot() -> WidgetSnapshot {
        VeeWidgetSharing.shared.read() ?? .empty()
    }

    func placeholder(in context: Context) -> PluginStatusEntry {
        PluginStatusEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                plugins: [
                    PluginSnapshot(id: "cpu", name: "cpu", title: "38%", updated: Date()),
                    PluginSnapshot(id: "net", name: "net", title: "↓ 1.2 MB/s", updated: Date()),
                ],
                generated: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PluginStatusEntry) -> Void) {
        completion(PluginStatusEntry(date: Date(), snapshot: currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PluginStatusEntry>) -> Void) {
        let entry = PluginStatusEntry(date: Date(), snapshot: currentSnapshot())
        // Refresh-on-change is push-driven by the app; this is just a safety net.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct PluginStatusWidget: Widget {
    static let kind = "com.vee.app.PluginStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PluginStatusProvider()) { entry in
            PluginStatusView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Vee Plugins")
        .description("Live output from your Vee menu-bar plugins.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PluginStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PluginStatusEntry

    private var limit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 8
        }
    }

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

            if entry.snapshot.plugins.isEmpty {
                Spacer()
                Text("No plugins running")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.snapshot.plugins.prefix(limit)) { plugin in
                    HStack(spacing: 8) {
                        Text(plugin.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(plugin.title.isEmpty ? "•" : plugin.title)
                            .font(.caption).fontWeight(.medium)
                            .monospacedDigit()
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if entry.snapshot.plugins.count > limit {
                    Text("+\(entry.snapshot.plugins.count - limit) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
