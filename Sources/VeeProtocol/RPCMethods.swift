import Foundation

/// The frozen host↔plugin method catalog. Direction is from the perspective of
/// the *caller*. Method-name strings are the wire contract; the param/result
/// structs below define each payload. All payload structs encode to/from
/// `JSONValue` via `JSONEncoder`/`JSONDecoder` and ride in `params`/`result`.
public enum RPCMethods {

    // MARK: Host → Plugin (lifecycle; requests unless noted)

    /// Host asks the plugin to activate a command. Params: `ActivateParams`.
    /// Result: empty (the plugin responds, then begins emitting `plugin.render`).
    public static let activate   = "plugin.activate"

    /// Host asks the plugin to deactivate the current command. Params: `DeactivateParams`.
    public static let deactivate = "plugin.deactivate"

    /// Host tells the plugin its bundle was rebuilt and re-evaluated; the plugin
    /// should rehydrate from `state` (if provided) and re-render.
    /// Params: `ReloadParams`. (Host re-evals the bundle; this notifies JS land.)
    public static let reload     = "plugin.reload"

    /// NOTIFICATION host → plugin: the user typed in the search field and the
    /// plugin opted into server-side filtering (declared `filtering:false` /
    /// registered a search listener). Params: `SearchTextChangeParams`.
    public static let onSearchTextChange = "host.onSearchTextChange"  // host-originated, sent TO plugin

    /// NOTIFICATION host → plugin: the user invoked an action emitted by the
    /// plugin (e.g. tapped a `<action>`). Params: `InvokeActionParams`.
    public static let invokeAction = "host.invokeAction"              // host-originated, sent TO plugin

    /// NOTIFICATION host → plugin: a form was submitted. Params: `SubmitFormParams`.
    public static let submitForm = "host.submitForm"

    // MARK: Plugin → Host

    /// NOTIFICATION plugin → host: a new render tree is ready, expressed as a
    /// JSON-Patch diff against the previously-rendered tree. Params: `RenderParams`.
    /// This is THE hot path. First render after activate sends a single
    /// `replace` at path `""` (whole tree); subsequent renders send minimal diffs.
    public static let render = "plugin.render"

    /// NOTIFICATION plugin → host: push the full candidate set for native
    /// fuzzy filtering (the "fetch once, filter natively" boundary).
    /// Params: `SetCandidatesParams`.
    public static let setCandidates = "plugin.setCandidates"

    /// NOTIFICATION plugin → host: a log line from `console.*`. Params: `LogParams`.
    public static let log = "plugin.log"

    /// NOTIFICATION plugin → host: show a transient toast (e.g. expected
    /// network error). Params: `ToastParams`.
    public static let toast = "plugin.showToast"

    // MARK: Plugin → Host (bridge requests — capability-gated; expect a response)

    /// `vee.http.fetch`. Params: `FetchParams`. Result: `FetchResult`.
    /// Host enforces the network-domain allowlist before dispatching.
    public static let httpFetch = "bridge.http.fetch"

    /// `vee.fs.readScoped` / write. Params: `FSReadParams` / `FSWriteParams`.
    public static let fsRead  = "bridge.fs.read"
    public static let fsWrite = "bridge.fs.write"

    /// `vee.fs.list(dir)`. Params: `FSListParams`. Result: `[FSDirEntry]` —
    /// the entries directly under `path` (basenames, not recursive).
    public static let fsList  = "bridge.fs.list"

    /// `vee.keychain.get/set/delete`. Params: `KeychainGetParams` etc.
    public static let keychainGet    = "bridge.keychain.get"
    public static let keychainSet    = "bridge.keychain.set"
    public static let keychainDelete = "bridge.keychain.delete"

    /// `vee.clipboard.history(query)` / `copy(item)`. Host-native service.
    public static let clipboardHistory = "bridge.clipboard.history"
    public static let clipboardCopy    = "bridge.clipboard.copy"

    /// `vee.calendar.upcoming()`. Host-native (TCC prompt lives in the app).
    public static let calendarUpcoming = "bridge.calendar.upcoming"

    /// `vee.storage.get/set` — the SWR-backed plugin key/value store.
    public static let storageGet = "bridge.storage.get"
    public static let storageSet = "bridge.storage.set"

    /// `vee.open(url)` — open a URL/file in the default handler.
    /// `vee.openApp(bundleId)` — launch an app by bundle id.
    /// Both are capability-gated by `Capabilities.open` (SEC-1/SEC-2). Migrated
    /// here from the former VeeEngine-local `BridgeMethods` so the catalog is the
    /// single source of truth for every bridge method string.
    public static let open    = "bridge.open"
    public static let openApp = "bridge.openApp"

    /// `vee.notify(title, body?, subtitle?)` — post a system notification.
    /// Params: `NotifyParams`. Ungated (user-facing, like `plugin.showToast`);
    /// delivered to the injected host `NotificationProviding`, NOT routed through
    /// the launcher window.
    public static let notify = "bridge.notify"
}

// MARK: - Payload structs (typed, Codable, Sendable)

public struct ActivateParams: Codable, Hashable, Sendable {
    public var pluginId: String
    public var commandName: String
    /// Arguments passed from the launcher (e.g. a query argument). Optional.
    public var arguments: [String: JSONValue]
    /// Resolved preference values for this command — the host merges the plugin's
    /// declared ``PluginPreference`` specs (extension + command) with the user's
    /// stored values and declared defaults, and delivers the result here. The
    /// plugin reads it synchronously via `getPreferenceValues()`. Keyed by
    /// preference `name`. Additive: omitted on the wire when empty (older hosts /
    /// preference-less plugins decode to `[:]`).
    public var preferences: [String: JSONValue]
    public init(pluginId: String, commandName: String,
                arguments: [String: JSONValue] = [:],
                preferences: [String: JSONValue] = [:]) {
        self.pluginId = pluginId; self.commandName = commandName
        self.arguments = arguments; self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey {
        case pluginId, commandName, arguments, preferences
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.pluginId = try c.decode(String.self, forKey: .pluginId)
        self.commandName = try c.decode(String.self, forKey: .commandName)
        self.arguments = try c.decodeIfPresent([String: JSONValue].self, forKey: .arguments) ?? [:]
        self.preferences = try c.decodeIfPresent([String: JSONValue].self, forKey: .preferences) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pluginId, forKey: .pluginId)
        try c.encode(commandName, forKey: .commandName)
        if !arguments.isEmpty { try c.encode(arguments, forKey: .arguments) }
        if !preferences.isEmpty { try c.encode(preferences, forKey: .preferences) }
    }
}

public struct DeactivateParams: Codable, Hashable, Sendable {
    public var pluginId: String
    public var commandName: String
    public init(pluginId: String, commandName: String) {
        self.pluginId = pluginId; self.commandName = commandName
    }
}

public struct ReloadParams: Codable, Hashable, Sendable {
    public var pluginId: String
    /// Opaque JSON state the host preserved across the context swap (from a
    /// prior `plugin.storage` snapshot). Plugin rehydrates from this.
    public var state: JSONValue?
    public init(pluginId: String, state: JSONValue? = nil) {
        self.pluginId = pluginId; self.state = state
    }
}

public struct SearchTextChangeParams: Codable, Hashable, Sendable {
    public var pluginId: String
    public var query: String
    public init(pluginId: String, query: String) { self.pluginId = pluginId; self.query = query }
}

public struct InvokeActionParams: Codable, Hashable, Sendable {
    public var pluginId: String
    /// The `actionId` prop the plugin attached to the `<action>` node.
    public var actionId: String
    /// The `id` of the candidate/list-item the action was fired on, if any.
    public var targetId: String?
    public init(pluginId: String, actionId: String, targetId: String? = nil) {
        self.pluginId = pluginId; self.actionId = actionId; self.targetId = targetId
    }
}

public struct SubmitFormParams: Codable, Hashable, Sendable {
    public var pluginId: String
    public var actionId: String
    /// Field name → submitted value.
    public var values: [String: JSONValue]
    public init(pluginId: String, actionId: String, values: [String: JSONValue]) {
        self.pluginId = pluginId; self.actionId = actionId; self.values = values
    }
}

public struct RenderParams: Codable, Hashable, Sendable {
    public var pluginId: String
    /// Monotonic render sequence number; host ignores out-of-order frames.
    public var revision: Int
    /// JSON-Patch diff against the previously-rendered tree (RFC 6902).
    public var patch: JSONPatchDocument
    public init(pluginId: String, revision: Int, patch: JSONPatchDocument) {
        self.pluginId = pluginId; self.revision = revision; self.patch = patch
    }
}

public struct SetCandidatesParams: Codable, Hashable, Sendable {
    public var pluginId: String
    public var candidates: [Candidate]
    public init(pluginId: String, candidates: [Candidate]) {
        self.pluginId = pluginId; self.candidates = candidates
    }
}

public struct LogParams: Codable, Hashable, Sendable {
    public enum Level: String, Codable, Sendable { case debug, info, warn, error }
    public var pluginId: String
    public var level: Level
    public var message: String
    public init(pluginId: String, level: Level, message: String) {
        self.pluginId = pluginId; self.level = level; self.message = message
    }
}

public struct ToastParams: Codable, Hashable, Sendable {
    public enum Style: String, Codable, Sendable { case success, failure, info }
    public var pluginId: String
    public var style: Style
    public var title: String
    public var message: String?
    public init(pluginId: String, style: Style, title: String, message: String? = nil) {
        self.pluginId = pluginId; self.style = style; self.title = title; self.message = message
    }
}

public struct NotifyParams: Codable, Hashable, Sendable {
    public var title: String
    public var body: String?
    public var subtitle: String?
    public init(title: String, body: String? = nil, subtitle: String? = nil) {
        self.title = title; self.body = body; self.subtitle = subtitle
    }
}

// MARK: Bridge payloads

public struct FetchParams: Codable, Hashable, Sendable {
    public var url: String
    public var method: String
    public var headers: [String: String]
    /// Base64-encoded body, or nil. Base64 keeps binary bodies JSON-safe.
    public var bodyBase64: String?
    public init(url: String, method: String = "GET",
                headers: [String: String] = [:], bodyBase64: String? = nil) {
        self.url = url; self.method = method; self.headers = headers; self.bodyBase64 = bodyBase64
    }
}

public struct FetchResult: Codable, Hashable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var bodyBase64: String
    public init(status: Int, headers: [String: String], bodyBase64: String) {
        self.status = status; self.headers = headers; self.bodyBase64 = bodyBase64
    }
}

public struct FSReadParams: Codable, Hashable, Sendable {
    /// Path relative to one of the plugin's declared fs roots.
    public var path: String
    public init(path: String) { self.path = path }
}
public struct FSWriteParams: Codable, Hashable, Sendable {
    public var path: String
    public var contentsBase64: String
    public init(path: String, contentsBase64: String) {
        self.path = path; self.contentsBase64 = contentsBase64
    }
}
public struct FSListParams: Codable, Hashable, Sendable {
    /// Directory to list. Subject to the same root-confinement gate as fs read/write.
    public var path: String
    public init(path: String) { self.path = path }
}
/// One entry directly under a listed directory. `name` is the basename (not a
/// full path); `isDirectory` distinguishes subdirectories from files.
public struct FSDirEntry: Codable, Hashable, Sendable {
    public var name: String
    public var isDirectory: Bool
    public init(name: String, isDirectory: Bool) {
        self.name = name; self.isDirectory = isDirectory
    }
}

public struct KeychainGetParams: Codable, Hashable, Sendable {
    public var key: String
    public init(key: String) { self.key = key }
}
public struct KeychainSetParams: Codable, Hashable, Sendable {
    public var key: String
    public var value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
}

public struct ClipboardHistoryParams: Codable, Hashable, Sendable {
    public var query: String
    public var limit: Int
    public init(query: String = "", limit: Int = 100) { self.query = query; self.limit = limit }
}
public struct ClipboardItem: Codable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var copiedAt: Date
    public init(id: String, text: String, copiedAt: Date) {
        self.id = id; self.text = text; self.copiedAt = copiedAt
    }
}

public struct CalendarEvent: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var meetingURL: String?
    public init(id: String, title: String, start: Date, end: Date, meetingURL: String? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.meetingURL = meetingURL
    }
}

public struct StorageGetParams: Codable, Hashable, Sendable {
    public var key: String
    public init(key: String) { self.key = key }
}
public struct StorageSetParams: Codable, Hashable, Sendable {
    public var key: String
    public var value: JSONValue
    public var ttlSeconds: Double?
    public init(key: String, value: JSONValue, ttlSeconds: Double? = nil) {
        self.key = key; self.value = value; self.ttlSeconds = ttlSeconds
    }
}
