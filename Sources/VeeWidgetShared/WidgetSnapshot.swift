import Foundation

/// One plugin's current menu-bar state, as surfaced to the WidgetKit widget.
/// Deliberately small: the widget shows the plugin's name and its current
/// title line, not its whole dropdown.
public struct PluginSnapshot: Codable, Equatable, Identifiable, Sendable {
    /// The plugin's stable id (its filename, e.g. `cpu.5s.sh`).
    public let id: String
    /// Human-readable name (the filename without its interval/extension).
    public let name: String
    /// The current menu-bar title text (first title line), already stripped of
    /// parameters. May be an error marker like `⚠︎` when the plugin failed.
    public let title: String
    /// When this plugin last rendered.
    public let updated: Date

    public init(id: String, name: String, title: String, updated: Date) {
        self.id = id
        self.name = name
        self.title = title
        self.updated = updated
    }
}

/// The whole set of plugins the app is currently showing, written to the App
/// Group container so the widget/control extension (a separate process) can
/// read it. Versioned so the format can evolve without crashing an old widget.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var plugins: [PluginSnapshot]
    public var generated: Date

    public init(plugins: [PluginSnapshot], generated: Date, version: Int = WidgetSnapshot.currentVersion) {
        self.version = version
        self.plugins = plugins
        self.generated = generated
    }

    /// An empty snapshot, used as the widget's placeholder/fallback.
    public static func empty(generated: Date = Date(timeIntervalSince1970: 0)) -> WidgetSnapshot {
        WidgetSnapshot(plugins: [], generated: generated)
    }
}
