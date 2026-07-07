import Foundation
import VeePluginFormat
import VeeWidgetShared

/// The presentation distilled from a plugin's title (and, as a fallback, its
/// first dropdown item) for the WidgetKit snapshot: the color to tint the value,
/// an SF Symbol, and a headline gauge/sparkline. Built by
/// `PluginCoordinator.widgetFields`.
struct WidgetTitleFields: Equatable {
    var color: VeeColor?
    var symbolName: String?
    var symbolColors: [VeeColor]?
    var progress: Double?
    var sparkline: [Double]?
}

/// One publish event from a `PluginCoordinator` to the widget snapshot: the
/// current title text, its distilled presentation, and whether the run errored.
/// Replaces the bare `String` the coordinator used to hand back so the snapshot
/// can carry color/symbol/gauge and an error flag.
struct WidgetPublish: Equatable {
    var title: String
    var fields: WidgetTitleFields
    var isError: Bool

    init(title: String, fields: WidgetTitleFields = WidgetTitleFields(), isError: Bool = false) {
        self.title = title
        self.fields = fields
        self.isError = isError
    }
}

/// Bridges the parser's `VeeColor` to the Foundation-only `SnapshotColor` the
/// widget reads. Kept as a namespaced helper so it is unit-testable without the
/// AppKit-bound coordinator.
enum WidgetSnapshotMapping {
    static func snapshotColor(_ color: VeeColor) -> SnapshotColor {
        switch color {
        case .named(let name): return .named(name)
        case .rgb(let r, let g, let b, let a): return .rgba(r: r, g: g, b: b, a: a)
        }
    }

    static func snapshotColors(_ colors: [VeeColor]?) -> [SnapshotColor]? {
        colors.map { $0.map(snapshotColor) }
    }
}
