import Foundation

/// A single user-facing feature a plugin opts into, ready to render as a row
/// (SF Symbol + title + one-line detail). Kept UI-framework-free so the same
/// wording is reused everywhere a plugin's footprint is shown.
public struct PluginFeatureItem: Equatable, Sendable {
    public let symbol: String
    public let title: String
    public let detail: String

    public init(symbol: String, title: String, detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// The Vee-native *features* a plugin declares via `<vee.*>` tags — as opposed to
/// its security trust footprint (network/files/secrets/exec, in `VeeTrust`).
/// These are behaviors the user should see and that deserve disclosure (a global
/// hotkey grabs a system-wide key), surfaced consistently in the menu's
/// capabilities area, the plugin's settings window, and the install sheet.
public struct PluginFeatures: Equatable, Sendable {
    /// The plugin opted into the searchable filter panel (`<vee.filter>`).
    public var searchPanel: Bool
    /// The display form of the plugin's global search hotkey (`<vee.shortcut>`),
    /// e.g. `⌘⇧K`; `nil` when none is declared.
    public var hotkey: String?

    public init(searchPanel: Bool = false, hotkey: String? = nil) {
        self.searchPanel = searchPanel
        self.hotkey = hotkey
    }

    /// Derives the features from a plugin's parsed header.
    public init(header: HeaderMetadata) {
        self.searchPanel = header.filter
        self.hotkey = header.shortcut?.display
    }

    public var isEmpty: Bool { !searchPanel && hotkey == nil }

    /// One row per declared feature, in a stable order, with shared wording.
    public var items: [PluginFeatureItem] {
        var rows: [PluginFeatureItem] = []
        if searchPanel {
            rows.append(PluginFeatureItem(
                symbol: "magnifyingglass",
                title: "Searchable menu",
                detail: "Filter this plugin's items from a search panel (⌘F)."
            ))
        }
        if let hotkey {
            rows.append(PluginFeatureItem(
                symbol: "keyboard",
                title: "Global hotkey",
                detail: "Opens the search panel from anywhere with \(hotkey)."
            ))
        }
        return rows
    }
}
