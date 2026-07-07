import WidgetKit
import SwiftUI
import VeeWidgetShared

/// The one view the always-visible menu bar structurally can't give you: an
/// *aggregate* health roll-up across every Vee plugin — "6 OK · 1 failing" —
/// with the failing plugins called out. Static (no per-instance config); it
/// always summarizes the whole snapshot.
struct PluginHealthEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PluginHealthProvider: TimelineProvider {
    private func currentSnapshot() -> WidgetSnapshot {
        VeeWidgetSharing.shared.read() ?? .empty()
    }

    func placeholder(in context: Context) -> PluginHealthEntry {
        PluginHealthEntry(date: Date(), snapshot: WidgetSnapshot(
            plugins: [
                PluginSnapshot(id: "a", name: "cpu", title: "38%", updated: Date()),
                PluginSnapshot(id: "b", name: "disk", title: "72%", updated: Date()),
                PluginSnapshot(id: "c", name: "build", title: "⚠︎ error", updated: Date(), isError: true),
            ],
            generated: Date()
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (PluginHealthEntry) -> Void) {
        completion(PluginHealthEntry(date: Date(), snapshot: currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PluginHealthEntry>) -> Void) {
        let entry = PluginHealthEntry(date: Date(), snapshot: currentSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct PluginHealthWidget: Widget {
    static let kind = "com.vee.app.PluginHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PluginHealthProvider()) { entry in
            PluginHealthView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Vee Health")
        .description("At-a-glance health across all your Vee plugins.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PluginHealthView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PluginHealthEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var allHealthy: Bool { snapshot.failingCount == 0 && !snapshot.plugins.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: headlineSymbol)
                    .font(.title3)
                    .foregroundStyle(headlineColor)
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }

            if snapshot.plugins.isEmpty {
                Text("No plugins running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(snapshot.okCount) OK · \(snapshot.failingCount) failing")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if family != .systemSmall, !snapshot.failing.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snapshot.failing.prefix(4)) { plugin in
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                Text(plugin.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        if snapshot.failingCount > 4 {
                            Text("+\(snapshot.failingCount - 4) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headline: String {
        if snapshot.plugins.isEmpty { return "Vee" }
        return allHealthy ? "All healthy" : "\(snapshot.failingCount) failing"
    }

    private var headlineSymbol: String {
        if snapshot.plugins.isEmpty { return "menubar.rectangle" }
        return allHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var headlineColor: Color {
        if snapshot.plugins.isEmpty { return .secondary }
        return allHealthy ? .green : .red
    }
}
