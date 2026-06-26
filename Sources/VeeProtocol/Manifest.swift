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
    /// Extension-level user preferences this plugin DECLARES (the Raycast model):
    /// the host renders a generic form from these and the plugin reads the resolved
    /// values at runtime via `getPreferenceValues()`. The application core hardcodes
    /// NO credential of its own — an API key/token exists only because some plugin
    /// declared a `.password` preference for it. A command may add its own
    /// ``PluginCommand/preferences``, merged over these (see ``mergedPreferences(forCommand:)``).
    public var preferences: [PluginPreference]

    public init(id: String,
                name: String,
                version: String,
                entrypoint: String,
                commands: [PluginCommand],
                capabilities: Capabilities = Capabilities(),
                preferences: [PluginPreference] = []) {
        self.id = id; self.name = name; self.version = version
        self.entrypoint = entrypoint; self.commands = commands; self.capabilities = capabilities
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, entrypoint, commands, capabilities, preferences
    }

    /// ADDITIVE / backward-compatible decode: a manifest written before
    /// `preferences` existed (no `preferences` key) decodes to `[]`, so old
    /// `vee.json` files and wire frames keep loading. The other fields keep their
    /// prior (required) strictness so nothing else changes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.version = try c.decode(String.self, forKey: .version)
        self.entrypoint = try c.decode(String.self, forKey: .entrypoint)
        self.commands = try c.decode([PluginCommand].self, forKey: .commands)
        self.capabilities = try c.decode(Capabilities.self, forKey: .capabilities)
        self.preferences = try c.decodeIfPresent([PluginPreference].self, forKey: .preferences) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encode(entrypoint, forKey: .entrypoint)
        try c.encode(commands, forKey: .commands)
        try c.encode(capabilities, forKey: .capabilities)
        // Omit when empty so a preference-less manifest's encoded form is byte-identical to before.
        if !preferences.isEmpty { try c.encode(preferences, forKey: .preferences) }
    }
}

public extension PluginManifest {
    /// The extension-level preferences merged with the named command's own
    /// (command preferences win on a name collision), preserving declaration
    /// order. This is the single source of truth for "what is configurable for
    /// this command" — the host gating, the resolver, and the Settings form all
    /// use it so they never disagree.
    func mergedPreferences(forCommand command: String) -> [PluginPreference] {
        let commandPrefs = commands.first { $0.name == command }?.preferences ?? []
        var byName: [String: PluginPreference] = [:]
        var order: [String] = []
        for pref in preferences + commandPrefs {
            if byName[pref.name] == nil { order.append(pref.name) }
            byName[pref.name] = pref
        }
        return order.compactMap { byName[$0] }
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
    /// Command-scoped preferences, merged over the extension-level
    /// ``PluginManifest/preferences`` for this command (Raycast allows both).
    public var preferences: [PluginPreference]

    public init(name: String,
                title: String,
                subtitle: String? = nil,
                mode: Mode,
                refreshIntervalSeconds: Double? = nil,
                hotkeyActions: [String] = [],
                preferences: [PluginPreference] = []) {
        self.name = name; self.title = title; self.subtitle = subtitle
        self.mode = mode; self.refreshIntervalSeconds = refreshIntervalSeconds
        self.hotkeyActions = hotkeyActions; self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, subtitle, mode, refreshIntervalSeconds, hotkeyActions, preferences
    }

    /// ADDITIVE decode: `preferences` defaults to `[]` when absent; the other
    /// keys keep their prior strictness (required ones stay required).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.title = try c.decode(String.self, forKey: .title)
        self.subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        self.mode = try c.decode(Mode.self, forKey: .mode)
        self.refreshIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds)
        self.hotkeyActions = try c.decode([String].self, forKey: .hotkeyActions)
        self.preferences = try c.decodeIfPresent([PluginPreference].self, forKey: .preferences) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(refreshIntervalSeconds, forKey: .refreshIntervalSeconds)
        try c.encode(hotkeyActions, forKey: .hotkeyActions)
        if !preferences.isEmpty { try c.encode(preferences, forKey: .preferences) }
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

// MARK: - Plugin-declared preferences (the Raycast configuration model)

/// One user-configurable setting an extension (or one of its commands) DECLARES
/// in its manifest. This is the heart of Vee's "the plugin author owns
/// configuration" model: the host renders a GENERIC form from these specs and the
/// plugin reads the resolved values at runtime via `getPreferenceValues()`. The
/// application has no built-in notion of GitHub tokens, API keys, sites, etc. —
/// a credential exists only because some plugin declared a `.password` preference
/// for it. So Vee can support unbounded, author-defined configuration without the
/// app ever enumerating "which API keys" up front.
public struct PluginPreference: Codable, Hashable, Sendable {
    /// The control the host renders for this preference.
    public enum Kind: String, Codable, Sendable {
        /// Single-line text (URLs, usernames, ids…).
        case textfield
        /// A secret. Stored in the Keychain and never echoed back into the form.
        case password
        /// A boolean, rendered as a switch/checkbox.
        case checkbox
        /// One of a fixed set of options (see ``PluginPreference/data``).
        case dropdown
        /// Parity placeholders with Raycast; rendered as a textfield for now, so
        /// adding richer pickers later is forward-compatible (no wire change).
        case appPicker = "app-picker"
        case file
        case directory
    }

    /// Stable key the plugin reads at runtime (`getPreferenceValues().<name>`).
    public var name: String
    /// Which control to render / how to store the value.
    public var type: Kind
    /// Human-readable label shown beside the control.
    public var title: String
    /// Longer help text shown under the control.
    public var description: String?
    /// Whether a command refuses to run until this preference is set — the host
    /// shows a "Setup required" form instead of activating the command.
    public var required: Bool
    /// Value used when the user has not set one (also offered as the form default).
    public var `default`: JSONValue?
    /// Placeholder shown in an empty text/password field.
    public var placeholder: String?
    /// For `.checkbox`: the inline label beside the box.
    public var label: String?
    /// For `.dropdown`: the selectable options, in display order.
    public var data: [PreferenceOption]

    public init(name: String,
                type: Kind,
                title: String,
                description: String? = nil,
                required: Bool = false,
                default: JSONValue? = nil,
                placeholder: String? = nil,
                label: String? = nil,
                data: [PreferenceOption] = []) {
        self.name = name; self.type = type; self.title = title
        self.description = description; self.required = required
        self.default = `default`; self.placeholder = placeholder
        self.label = label; self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, title, description, required, `default`, placeholder, label, data
    }

    /// Lenient decode: only `name`/`type`/`title` are required — a checkbox needs
    /// no `data`, a textfield no `default`, etc.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.type = try c.decode(Kind.self, forKey: .type)
        self.title = try c.decode(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        self.default = try c.decodeIfPresent(JSONValue.self, forKey: .default)
        self.placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.data = try c.decodeIfPresent([PreferenceOption].self, forKey: .data) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        if required { try c.encode(required, forKey: .required) }
        try c.encodeIfPresent(`default`, forKey: .default)
        try c.encodeIfPresent(placeholder, forKey: .placeholder)
        try c.encodeIfPresent(label, forKey: .label)
        if !data.isEmpty { try c.encode(data, forKey: .data) }
    }
}

public extension PluginPreference {
    /// Whether the value should be stored as a secret (Keychain) rather than in
    /// the plain preferences store. Only `.password` is secret today.
    var isSecret: Bool { type == .password }
}

/// One selectable option for a `.dropdown` preference.
public struct PreferenceOption: Codable, Hashable, Sendable {
    /// Shown to the user in the dropdown.
    public var title: String
    /// Returned to the plugin when this option is selected.
    public var value: String
    public init(title: String, value: String) { self.title = title; self.value = value }
}
