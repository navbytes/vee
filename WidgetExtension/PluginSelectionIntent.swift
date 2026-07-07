import AppIntents
import WidgetKit
import VeeWidgetShared

/// A plugin the user can pick when configuring the Vee Plugins widget. Backed by
/// the shared snapshot the app publishes, so the picker lists exactly the
/// plugins currently running.
struct PluginEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plugin"
    static let defaultQuery = PluginEntityQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Resolves `PluginEntity` values for the widget configuration UI by reading the
/// snapshot file the app writes.
struct PluginEntityQuery: EntityQuery {
    private func currentPlugins() -> [PluginSnapshot] {
        (VeeWidgetSharing.shared.read() ?? .empty()).plugins
    }

    func entities(for identifiers: [PluginEntity.ID]) async throws -> [PluginEntity] {
        let byID = Dictionary(currentPlugins().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return identifiers.compactMap { id in byID[id].map { PluginEntity(id: $0.id, name: $0.name) } }
    }

    func suggestedEntities() async throws -> [PluginEntity] {
        currentPlugins()
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
            .map { PluginEntity(id: $0.id, name: $0.name) }
    }
}

/// The widget's configuration: which plugins to show. Empty/unset means "all",
/// so a freshly added widget is useful before the user configures it.
struct SelectPluginsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Plugins"
    static let description = IntentDescription("Pick which Vee plugins this widget shows. Leave empty to show them all.")

    @Parameter(title: "Plugins")
    var plugins: [PluginEntity]?

    init() {}
    init(plugins: [PluginEntity]?) { self.plugins = plugins }

    /// The selected ids, or `nil` only when the user hasn't configured the widget
    /// at all (→ show all). A configured-but-currently-empty selection stays an
    /// empty list, so a widget pinned to a plugin that later disappears shows the
    /// empty state rather than silently reverting to showing every plugin.
    var selectedIDs: [String]? {
        guard let plugins else { return nil }
        return plugins.map(\.id)
    }
}
