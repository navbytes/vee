import Foundation

/// A shell action attached to a menu item via `shell=`/`bash=` (+ `param1..N`
/// and `terminal=`).
public struct ShellCommand: Equatable, Sendable {
    public var launchPath: String
    public var arguments: [String]
    public var openInTerminal: Bool

    public init(launchPath: String, arguments: [String], openInTerminal: Bool) {
        self.launchPath = launchPath
        self.arguments = arguments
        self.openInTerminal = openInTerminal
    }
}

/// SwiftBar-specific menu parameters, grouped so their provenance (an extension
/// beyond the base xbar format) stays explicit.
public struct SwiftBarParams: Equatable, Sendable {
    public var sfimage: String?
    public var sfcolor: [VeeColor]?
    public var sfsize: Double?
    public var sfconfig: String?
    public var symbolize: Bool?
    public var tooltip: String?
    public var markdown: Bool?
    public var checked: Bool?
    public var badge: String?
    public var webview: URL?
    public var webviewWidth: Double?
    public var webviewHeight: Double?
    public var shortcut: String?

    // NOTE: `header`/`accessory`/`chart` below are Vee-native, not SwiftBar
    // params — they live in this struct as a workaround, not for provenance.
    // See the comment on `LineParams.swiftbar` for why.

    /// A first-class, non-interactive section-header row (`header=true`),
    /// rendered with AppKit's native `NSMenuItem.sectionHeader(title:)` — not a
    /// `disabled=true` line dressed up to look like one.
    public var header: Bool?

    /// Placement of the row's `progress=`/`sparkline=`/chart accessory
    /// (`accessory=`). `nil` (absent) means today's default: trailing.
    public var accessory: AccessoryPlacement?

    /// A categorical share chart (`pie=`/`donut=`/`stackedbar=`). When non-nil,
    /// the row draws the chart inline and opens a richer Swift Charts popover on
    /// click. Stored here — see the comment on `LineParams.swiftbar` for why.
    public var chart: ChartParams?

    public init() {}
}

/// A Vee-native interactive control attached to a menu item (`toggle=`/
/// `slider=`). When present, the item opens a Liquid Glass `NSPopover` with a
/// live control instead of firing immediately; committing a new value
/// re-invokes the item's `shell=`/`bash=` command with that value (see
/// `AppActionDispatcher`).
public enum PluginControl: Equatable, Sendable {
    /// An on/off switch. `on` is the current state.
    case toggle(on: Bool)
    /// A continuous slider bounded by `min...max` at the current `value`
    /// (clamped into range at parse time; `min < max` guaranteed).
    case slider(min: Double, max: Double, value: Double)
}

/// Where a row's visual accessory (`progress=`/`sparkline=`/`pie=`/`donut=`/
/// `stackedbar=`) sits relative to its label (`accessory=leading`/
/// `accessory=trailing`). Applies uniformly to all of them, since they share the
/// same in-row layout geometry (`ProgressBarLayout` in `VeeMenu`).
public enum AccessoryPlacement: String, Equatable, Sendable {
    case leading
    case trailing
}

/// A Vee-native inline progress gauge (`progress=`). Rendered as a real capsule
/// bar drawn in the menu row via a custom `NSMenuItem.view` — not block glyphs.
/// The fill uses the item's `color=`; `trackColor`/`width`/`height` are optional
/// overrides.
public struct ProgressParams: Equatable, Sendable {
    /// Completion, always clamped to `0...1` at parse time.
    public var fraction: Double
    /// Background track color (`trackcolor=`). Defaults applied at render time.
    public var trackColor: VeeColor?
    /// Bar width in points (`progressw=`). Default applied at render time.
    public var width: Double?
    /// Bar height in points (`progressh=`). Default applied at render time.
    public var height: Double?
    /// `progressw=full`: the bar stretches to whatever width the row actually
    /// has, instead of a fixed number of points — the same knob, and the same
    /// geometry, as `chartw=full` on a `stackedbar=` (`ProgressBarLayout.
    /// stretchedWidth`). A menu is as wide as its widest row, so a fixed width
    /// can't fill a menu whose width some *other* row decides; this can. The bar
    /// takes the row's content width, less the row's own text when it has any.
    public var isFullWidth: Bool

    public init(fraction: Double, trackColor: VeeColor? = nil, width: Double? = nil, height: Double? = nil, isFullWidth: Bool = false) {
        self.fraction = fraction
        self.trackColor = trackColor
        self.width = width
        self.height = height
        self.isFullWidth = isFullWidth
    }

    /// Bar dimensions when the plugin declares none. They live here, in the
    /// format layer, because more than one renderer applies them — the AppKit
    /// menu row (`VeeMenu`) and the SwiftUI window row (`VeeUI`), which cannot
    /// see each other's modules — and a gauge that measured differently on the
    /// two surfaces would be the drift this avoids by construction.
    public static let defaultWidth: Double = 120
    public static let defaultHeight: Double = 6

    /// The declared bar width/height, or the default.
    public var effectiveWidth: Double { width ?? Self.defaultWidth }
    public var effectiveHeight: Double { height ?? Self.defaultHeight }
}

/// Strongly-typed representation of a menu line's `|`-delimited parameters.
/// Unknown keys are preserved in `unknown` (and reported as diagnostics) rather
/// than silently dropped, so the format can evolve without data loss.
public struct LineParams: Equatable, Sendable {
    // Rendering
    public var color: VeeColor?
    public var font: String?
    public var size: Double?
    public var length: Int?
    public var trim: Bool?
    public var ansi: Bool?
    public var emojize: Bool?

    // Behavior
    public var href: URL?
    public var shell: ShellCommand?
    public var refresh: Bool?
    public var dropdown: Bool?
    public var alternate: Bool?
    public var disabled: Bool?
    public var key: String?

    // Images (base64 payloads or file references, resolved at render time)
    public var image: String?
    public var templateImage: String?

    // SwiftBar extensions.
    //
    // IMPORTANT — do not add new direct stored properties to `LineParams`
    // itself: this struct sits at a hard ceiling where one more top-level
    // field (of *any* type, regardless of Equatable being synthesized or
    // hand-written) deterministically SIGSEGVs any code path that builds a
    // *nested* `MenuNode`/`MenuItem` tree (a submenu) — e.g.
    // `VeeSearchTests.MenuFlattenerTests.testClickableParentEmittedAndRecursed`.
    // Verified empirically (bisected in an isolated worktree): growing this
    // struct's own direct field list crashes; growing a struct nested *inside*
    // one of its existing fields (like `swiftbar` below) does not. Root cause
    // looks like a Swift compiler/runtime metadata bug tied to this struct's
    // participation in the recursive `indirect enum MenuNode` — not something
    // fixable from call-site code. Until someone root-causes/files that bug
    // (or `MenuNode`/`MenuItem` are restructured), add new params inside an
    // existing nested struct (`swiftbar`, or a dedicated one of its own),
    // never as a new top-level `LineParams` field.
    public var swiftbar: SwiftBarParams

    // Vee-native extensions
    /// An inline data series (`sparkline=1,2,3,4,5`). When non-empty, the item
    /// opts into a native Liquid Glass `NSPopover` that renders the series as a
    /// Swift Charts sparkline — rich UI without a WebView. Malformed entries are
    /// skipped; an empty/all-malformed list parses to `nil`.
    public var sparkline: [Double]?

    /// An interactive control (`toggle=on` / `slider=min,max,value`). When
    /// non-nil, the item opens a native Liquid Glass popover whose control
    /// re-invokes the item's `shell=`/`bash=` command with the chosen value.
    public var control: PluginControl?

    /// An inline progress gauge (`progress=0.72` or `progress=value,max`). When
    /// non-nil, the item renders a real capsule bar in the menu row.
    public var progress: ProgressParams?

    // Forward-compatibility: keys we didn't recognise.
    public var unknown: [String: String]

    public init() {
        self.swiftbar = SwiftBarParams()
        self.unknown = [:]
    }
}
