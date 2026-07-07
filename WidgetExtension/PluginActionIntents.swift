import AppIntents
import VeeWidgetShared

/// Backs a widget card's action buttons (up to two — see
/// `docs/design/widget-surface-contract.md` §6). Named `…Widget…` (not
/// `RefreshPluginIntent`, despite the design doc's working name) to avoid
/// colliding with the existing Shortcuts-facing `RefreshPluginIntent` in the
/// app target (`Sources/VeeApp/VeeAppIntents.swift`) — that one runs
/// in-process against a live `AppController`; this one runs in the sandboxed
/// extension and can only signal the app via the request-file channel.
///
/// Because the extension runs in a different process (and is sandboxed), it
/// cannot exec a plugin or run a Shortcut itself: it writes a
/// `WidgetActionRequest` to the shared support directory (a narrowly-scoped
/// read-write entitlement, see `WidgetExtension.entitlements`), then posts
/// the same kind of Darwin notify `RefreshAllControlIntent` uses, and sets
/// `openAppWhenRun` so a closed Vee is launched to service it.
@available(macOS 26.0, *)
struct RefreshPluginWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Plugin"
    static let description = IntentDescription("Re-runs one Vee plugin from its widget.")
    static let openAppWhenRun = true

    @Parameter(title: "Plugin ID")
    var pluginID: String

    init() {}

    init(pluginID: String) {
        self.pluginID = pluginID
    }

    func perform() async throws -> some IntentResult {
        VeeWidgetSharing.actionRequestStore.write(WidgetActionRequest(action: .refresh, pluginID: pluginID))
        WidgetActionSignal.post()
        return .result()
    }
}

/// Runs one of a card's `shortcut`-kind actions (up to two — see
/// `WidgetCard.actions`). `href` actions are deliberately not routed through
/// an `AppIntent` at all: the template renders them as `Link`/`widgetURL`,
/// which the system opens directly with no app round-trip. `shell` actions
/// are never offered to widgets in the first place (see the design doc §6).
@available(macOS 26.0, *)
struct RunPluginActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Plugin Action"
    static let description = IntentDescription("Runs a Vee widget card's shortcut action.")
    static let openAppWhenRun = true

    @Parameter(title: "Plugin ID")
    var pluginID: String
    @Parameter(title: "Action Index")
    var actionIndex: Int

    init() {}

    init(pluginID: String, actionIndex: Int) {
        self.pluginID = pluginID
        self.actionIndex = actionIndex
    }

    func perform() async throws -> some IntentResult {
        VeeWidgetSharing.actionRequestStore.write(WidgetActionRequest(action: .run, pluginID: pluginID, actionIndex: actionIndex))
        WidgetActionSignal.post()
        return .result()
    }
}

/// Posts the Darwin notify that wakes an already-running app's
/// `widgetActionRequestFired()`. Shared by both intents above.
enum WidgetActionSignal {
    static func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue: VeeWidgetSharing.actionRequestNotification as CFString),
            nil,
            nil,
            true
        )
    }
}
