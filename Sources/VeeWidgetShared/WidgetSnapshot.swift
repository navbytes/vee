import Foundation

/// One plugin's current menu-bar state, as surfaced to the WidgetKit widget.
///
/// v1 carried only the plugin's name and title line. v2 additionally carries the
/// *presentation* the app already computed — color, SF Symbol, a `progress=`
/// fraction, a `sparkline=` series, an error flag, and the refresh interval — so
/// the widget can render a real dashboard tile (a colored gauge / trend) instead
/// of a monospaced copy of the menu-bar text. Every enriched field is optional
/// so a v1 snapshot still decodes.
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

    // MARK: v2 — presentation the app already computed

    /// The title's color (`color=` / first ANSI run), used to tint the value.
    public let color: SnapshotColor?
    /// The title's SF Symbol name (`sfimage=`), rendered as the tile's glyph.
    public let symbolName: String?
    /// Palette for a multicolor/hierarchical SF Symbol (`sfcolor=`).
    public let symbolColors: [SnapshotColor]?
    /// A headline completion fraction (`progress=`), drawn as a gauge. `0...1`.
    public let progress: Double?
    /// A headline data series (`sparkline=`), drawn as a trend chart.
    public let sparkline: [Double]?
    /// Whether the plugin's last run errored (drives health roll-up + styling).
    /// Absent (nil) in v1 snapshots and treated as healthy — see `failed`.
    public let isError: Bool?
    /// The plugin's refresh interval in seconds, if it has one. Lets the widget
    /// flag genuinely stale data without guessing.
    public let interval: TimeInterval?

    public init(
        id: String,
        name: String,
        title: String,
        updated: Date,
        color: SnapshotColor? = nil,
        symbolName: String? = nil,
        symbolColors: [SnapshotColor]? = nil,
        progress: Double? = nil,
        sparkline: [Double]? = nil,
        isError: Bool? = nil,
        interval: TimeInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.updated = updated
        self.color = color
        self.symbolName = symbolName
        self.symbolColors = symbolColors
        self.progress = progress
        self.sparkline = sparkline
        self.isError = isError
        self.interval = interval
    }

    /// Whether this plugin is in an error state (`isError == true`). A v1
    /// snapshot with no error field reads as healthy.
    public var failed: Bool { isError == true }

    /// Below this age a plugin is never considered stale, even for a fast
    /// interval — WidgetKit meters reloads to roughly this cadence, so flagging
    /// "stale" sooner would just blame the widget's own refresh budget.
    public static let staleFloor: TimeInterval = 300

    /// Whether the data is old enough to warrant a "stale" treatment. Uses the
    /// plugin's own interval (two missed cycles), floored at `staleFloor`. An
    /// unknown interval is never flagged — we can't tell.
    public func isStale(asOf now: Date) -> Bool {
        guard let interval else { return false }
        let threshold = max(interval * 2, Self.staleFloor)
        return now.timeIntervalSince(updated) > threshold
    }
}

/// The whole set of plugins the app is currently showing, written to the shared
/// support directory so the widget/control extension (a separate process) can
/// read it. Versioned so the format can evolve without crashing an old widget.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 2

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

    // MARK: Roll-up (health widget)

    /// Plugins whose last run errored.
    public var failing: [PluginSnapshot] { plugins.filter(\.failed) }
    /// Count of plugins in an error state.
    public var failingCount: Int { failing.count }
    /// Count of plugins running cleanly.
    public var okCount: Int { plugins.count - failingCount }
}
