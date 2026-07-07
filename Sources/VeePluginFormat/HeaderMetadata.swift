import Foundation

/// A typed preference a plugin declares via `<xbar.var>` / `<swiftbar.var>`.
/// Example: `<xbar.var>string(API_TOKEN=): Your API token</xbar.var>`
public struct VarDeclaration: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case string, number, boolean, select
    }

    public var name: String
    public var kind: Kind
    public var defaultValue: String
    public var summary: String
    public var options: [String]
    /// Heuristic: treat token/secret/password/key vars as secrets (Keychain).
    public var isSecret: Bool

    public init(name: String, kind: Kind, defaultValue: String, summary: String, options: [String], isSecret: Bool) {
        self.name = name
        self.kind = kind
        self.defaultValue = defaultValue
        self.summary = summary
        self.options = options
        self.isSecret = isSecret
    }
}

/// Metadata parsed from a plugin's comment header (`<xbar.*>` / `<swiftbar.*>`).
public struct HeaderMetadata: Equatable, Sendable {
    public var title: String?
    public var version: String?
    public var author: String?
    public var authorGithub: String?
    public var summary: String?
    public var image: String?
    public var dependencies: [String] = []
    public var aboutURL: URL?

    // SwiftBar options
    public var schedule: [String] = []
    public var runInBash: Bool?
    public var refreshOnOpen: Bool?
    public var streamable: Bool = false
    public var environment: [String: String] = [:]
    public var persistentWebView: Bool?
    public var hideAbout: Bool = false
    public var hideRunInTerminal: Bool = false
    public var hideLastUpdated: Bool = false
    public var hideDisablePlugin: Bool = false
    public var hideSwiftBar: Bool = false

    public var vars: [VarDeclaration] = []

    // Vee-native options
    /// `<vee.filter>true</vee.filter>`: opt this plugin's dropdown into the
    /// searchable filter panel instead of a plain `NSMenu`. Advisory hint for the
    /// app layer; parsing it here keeps the format one source of truth.
    public var filter: Bool = false

    /// `<vee.shortcut>cmd+shift+k</vee.shortcut>`: a global hotkey that opens this
    /// plugin's search panel from anywhere. `nil` (the default) means no hotkey —
    /// the feature is strictly opt-in and only registered when the tag parses.
    public var shortcut: HotKeySpec?

    public init() {}
}
