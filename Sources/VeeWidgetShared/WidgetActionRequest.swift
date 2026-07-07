import Foundation

/// A request the widget extension writes when the user taps a card action
/// button, so the app (a separate, un-sandboxed process) can service it — the
/// extension cannot exec a plugin or run a Shortcut itself. This generalizes
/// `VeeWidgetSharing.refreshRequestNotification` (which only ever means
/// "refresh everything") to carry a specific plugin id and, for `.run`, which
/// of that plugin's card actions was tapped.
public struct WidgetActionRequest: Codable, Equatable, Sendable {
    /// What to do.
    ///
    /// - `refresh`: re-run this plugin (its widget-mode cadence, immediately).
    ///   Needs no `actionIndex`.
    /// - `run`: invoke one of the plugin's card `actions`, resolved by
    ///   `actionIndex` against the plugin's *currently-published* card (the
    ///   sandboxed extension only knows the tapped button's position, not the
    ///   action's content — the app re-reads it from the snapshot it already
    ///   wrote). Only ever posted for a `.shortcut`-kind action: `.href` is
    ///   opened directly by the extension (`widgetURL`/`Link`, no app
    ///   round-trip needed), and `.refresh`-kind actions use `.refresh`
    ///   above directly.
    public enum Action: String, Codable, Equatable, Sendable {
        case refresh
        case run
    }

    public var action: Action
    public var pluginID: String
    public var actionIndex: Int?

    public init(action: Action, pluginID: String, actionIndex: Int? = nil) {
        self.action = action
        self.pluginID = pluginID
        self.actionIndex = actionIndex
    }
}

/// Reads and writes the one pending `WidgetActionRequest` under a directory —
/// mirrors `WidgetSnapshotStore`'s shape. The extension writes (one request
/// at a time is sufficient: card buttons are momentary taps, not a queue);
/// the app reads and clears, so a request is serviced exactly once even if
/// the app was launched cold by the same tap that wrote it.
public struct WidgetActionRequestStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent(VeeWidgetSharing.actionRequestFileName) }

    /// Writes the request atomically. Called by the widget extension's
    /// `AppIntent`. Silently no-ops on failure, matching
    /// `WidgetSnapshotStore.write` — a dropped request is a missed tap, not a
    /// crash.
    public func write(_ request: WidgetActionRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        // Owner-only, same posture as the snapshot file.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Reads the pending request, if any, and deletes the file so it's
    /// consumed exactly once. Called by the app after waking on the Darwin
    /// notify, and once at launch (to catch a request written while the app
    /// was closed, before `openAppWhenRun` finished launching it).
    public func readAndClear() -> WidgetActionRequest? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return try? JSONDecoder().decode(WidgetActionRequest.self, from: data)
    }
}
