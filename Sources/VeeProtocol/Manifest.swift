import Foundation

/// A plugin's `vee.json` manifest: identity, entrypoint, commands, and the
/// capabilities it requests. The host enforces `capabilities` at the bridge —
/// a `vee.http.fetch` to a domain not in `network` is rejected with
/// `JSONRPCError.capabilityDenied`, `vee.fs` only resolves under `filesystem`
/// roots, and clipboard/calendar/keychain/hotkeys are gated by these flags.
public struct PluginManifest: Codable, Hashable, Sendable {
    /// Reverse-DNS unique id, e.g. "com.vee.github". Namespaces keychain items,
    /// storage, and support folders.
    public var id: String
    public var name: String
    public var version: String
    /// Path to the built single-file JS bundle, relative to the plugin folder.
    public var entrypoint: String
    public var commands: [PluginCommand]
    public var capabilities: Capabilities

    public init(id: String,
                name: String,
                version: String,
                entrypoint: String,
                commands: [PluginCommand],
                capabilities: Capabilities = Capabilities()) {
        self.id = id; self.name = name; self.version = version
        self.entrypoint = entrypoint; self.commands = commands; self.capabilities = capabilities
    }
}

public struct PluginCommand: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// A searchable view rendered in the launcher window.
        case view
        /// A background/menubar command with no launcher view.
        case menuBar = "menu-bar"
        /// A one-shot command that performs an action and closes.
        case noView = "no-view"
    }
    /// Stable command identifier within the plugin (passed in `ActivateParams`).
    public var name: String
    public var title: String
    public var subtitle: String?
    public var mode: Mode
    /// Refresh interval (seconds) for menu-bar/background commands; nil = manual.
    public var refreshIntervalSeconds: Double?
    /// Hotkey action names this command exposes (bound by the host recorder).
    public var hotkeyActions: [String]

    public init(name: String,
                title: String,
                subtitle: String? = nil,
                mode: Mode,
                refreshIntervalSeconds: Double? = nil,
                hotkeyActions: [String] = []) {
        self.name = name; self.title = title; self.subtitle = subtitle
        self.mode = mode; self.refreshIntervalSeconds = refreshIntervalSeconds
        self.hotkeyActions = hotkeyActions
    }
}

/// Capability manifest — the security surface. Default-deny: an empty
/// `Capabilities()` grants nothing. The host checks every bridge call against
/// this. NOTE (see risk register): this is capability *gating at the bridge*,
/// a pragmatic layer for self-authored plugins — NOT a sandbox boundary
/// against hostile code.
public struct Capabilities: Codable, Hashable, Sendable {
    /// Allowed network hosts for `vee.http.fetch`. Exact host match or a
    /// leading-dot suffix wildcard (".github.com" matches "api.github.com").
    /// Empty = no network.
    public var network: [String]
    /// Filesystem roots the plugin may read/write under (absolute paths or
    /// `~`-relative; host canonicalizes and confines). Empty = no fs access.
    public var filesystem: [String]
    /// Whether `vee.clipboard.*` is permitted.
    public var clipboard: Bool
    /// Whether `vee.calendar.*` is permitted (TCC prompt handled by the app).
    public var calendar: Bool
    /// Keychain namespaces the plugin may use under its own id. Empty = none.
    /// Each entry becomes a `kSecAttrService` of `com.vee.<pluginId>.<namespace>`.
    public var keychainNamespaces: [String]
    /// Hotkey action names the plugin declares for host binding.
    public var hotkeyActions: [String]

    public init(network: [String] = [],
                filesystem: [String] = [],
                clipboard: Bool = false,
                calendar: Bool = false,
                keychainNamespaces: [String] = [],
                hotkeyActions: [String] = []) {
        self.network = network; self.filesystem = filesystem
        self.clipboard = clipboard; self.calendar = calendar
        self.keychainNamespaces = keychainNamespaces; self.hotkeyActions = hotkeyActions
    }

    /// Host-side check used by the bridge before dispatching a fetch.
    /// `host` is the URL host component. Matches exact entries or dot-suffix
    /// wildcards. Returns false for an empty allowlist.
    public func allowsNetworkHost(_ host: String) -> Bool {
        let h = host.lowercased()
        for entry in network {
            let e = entry.lowercased()
            if e == h { return true }
            if e.hasPrefix("."), h.hasSuffix(e) || h == String(e.dropFirst()) { return true }
        }
        return false
    }
}
