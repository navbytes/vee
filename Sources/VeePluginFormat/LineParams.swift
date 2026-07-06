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

    // SwiftBar extensions
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

    // Forward-compatibility: keys we didn't recognise.
    public var unknown: [String: String]

    public init() {
        self.swiftbar = SwiftBarParams()
        self.unknown = [:]
    }
}
