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
    /// Allowlist gating `vee.open(url)` and `vee.openApp(bundleId)` (SEC-1/SEC-2).
    /// Default-deny: an empty list permits nothing. Two entry conventions share
    /// this one list:
    ///   • a bare **URL scheme** ("https", "mailto", "file") grants `vee.open`
    ///     for URLs of that scheme — case-insensitive, the `:` is omitted;
    ///   • a **"bundleId:" prefix** ("bundleId:com.apple.Safari") grants
    ///     `vee.openApp` for exactly that bundle id, and "bundleId:*" grants
    ///     `vee.openApp` for any app.
    /// `file:` / custom schemes are denied unless their scheme is listed
    /// explicitly. `vee.open` of `http`/`https` additionally requires the
    /// target host to satisfy ``allowsNetworkHost(_:)`` (so an open cannot be
    /// used to exfiltrate to a host outside the network allowlist — closes the
    /// SEC-1 bypass) UNLESS the catch-all `"*"` scheme entry is present.
    public var open: [String]
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
                open: [String] = [],
                filesystem: [String] = [],
                clipboard: Bool = false,
                calendar: Bool = false,
                keychainNamespaces: [String] = [],
                hotkeyActions: [String] = []) {
        self.network = network; self.open = open; self.filesystem = filesystem
        self.clipboard = clipboard; self.calendar = calendar
        self.keychainNamespaces = keychainNamespaces; self.hotkeyActions = hotkeyActions
    }

    private enum CodingKeys: String, CodingKey {
        case network, open, filesystem, clipboard, calendar, keychainNamespaces, hotkeyActions
    }

    /// ADDITIVE / backward-compatible decode: a manifest written before `open`
    /// existed (no `open` key) decodes to the default-deny `[]`, so old
    /// `vee.json` files keep loading. All other fields likewise tolerate absence.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.network = try c.decodeIfPresent([String].self, forKey: .network) ?? []
        self.open = try c.decodeIfPresent([String].self, forKey: .open) ?? []
        self.filesystem = try c.decodeIfPresent([String].self, forKey: .filesystem) ?? []
        self.clipboard = try c.decodeIfPresent(Bool.self, forKey: .clipboard) ?? false
        self.calendar = try c.decodeIfPresent(Bool.self, forKey: .calendar) ?? false
        self.keychainNamespaces = try c.decodeIfPresent([String].self, forKey: .keychainNamespaces) ?? []
        self.hotkeyActions = try c.decodeIfPresent([String].self, forKey: .hotkeyActions) ?? []
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

    // MARK: - open / openApp gating (SEC-1 / SEC-2)

    /// Whether the `open` allowlist contains the wildcard `"*"` scheme entry,
    /// which grants every scheme for `vee.open` (and, with `"bundleId:*"`, apps).
    /// `"*"` also waives the host re-check on `http(s)` opens.
    private var openAllowsAnyScheme: Bool {
        open.contains { $0.lowercased() == "*" }
    }

    /// Gate for `vee.open(url)` (SEC-1). `scheme` is the URL's scheme component
    /// (no `:`), `host` its host (empty if none). An entry is allowed when:
    ///   • the bare scheme is listed (or `"*"`), AND
    ///   • for `http`/`https`, the host also passes ``allowsNetworkHost(_:)``
    ///     (so `vee.open` cannot exfiltrate to a host outside `network`). This
    ///     re-check is UNCONDITIONAL: even a `"*"` scheme grant cannot open a web
    ///     URL to a non-allowlisted host (R2-MED-1).
    /// Returns false for an empty `open` list (default-deny).
    public func allowsOpen(scheme: String, host: String) -> Bool {
        let s = scheme.lowercased()
        guard !s.isEmpty else { return false }
        let schemeListed = openAllowsAnyScheme || open.contains { $0.lowercased() == s }
        guard schemeListed else { return false }
        if s == "http" || s == "https" {
            return allowsNetworkHost(host)
        }
        return true
    }

    /// Gate for `vee.openApp(bundleId)` (SEC-2). Allowed when the list contains
    /// `"bundleId:<id>"` for this exact id, or the catch-all `"bundleId:*"`.
    /// Returns false for an empty `open` list (default-deny).
    public func allowsOpenApp(bundleId: String) -> Bool {
        let id = bundleId.lowercased()
        for entry in open {
            let e = entry.lowercased()
            guard e.hasPrefix("bundleid:") else { continue }
            let allowed = String(e.dropFirst("bundleid:".count))
            if allowed == "*" || allowed == id { return true }
        }
        return false
    }
}
