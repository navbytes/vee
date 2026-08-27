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

/// Runs a `shortcut` the card names at `actionIndex` — one of its up-to-two
/// action buttons (`WidgetCard.actions`), or, when `isItem` is set, one of the
/// tappable `list`/`board` rows (`WidgetCard.items`).
///
/// One intent for both because they are the same path, not two: the sandboxed
/// extension knows only the tapped element's *position*, writes that as a
/// `WidgetActionRequest`, and the app resolves the Shortcut's name from the
/// snapshot it published itself. Keeping the name out of the request is the
/// point — the extension cannot name a Shortcut the plugin didn't.
///
/// `href` targets are deliberately not routed through an `AppIntent` at all:
/// the templates render them as `Link`/`widgetURL`, which the system opens
/// directly with no app round-trip. `shell` is never offered to a widget in the
/// first place (see the design doc §6).
@available(macOS 26.0, *)
struct RunPluginActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Plugin Action"
    static let description = IntentDescription("Runs a Vee widget card's shortcut action.")
    static let openAppWhenRun = true

    @Parameter(title: "Plugin ID")
    var pluginID: String
    @Parameter(title: "Action Index")
    var actionIndex: Int
    /// Whether `actionIndex` counts the card's `items` rather than its
    /// `actions`. Defaulted so existing call sites (and any already-installed
    /// tile whose stored intent predates this parameter) keep meaning "an
    /// action button".
    @Parameter(title: "Is Item Row", default: false)
    var isItem: Bool

    init() {}

    init(pluginID: String, actionIndex: Int, isItem: Bool = false) {
        self.pluginID = pluginID
        self.actionIndex = actionIndex
        self.isItem = isItem
    }

    func perform() async throws -> some IntentResult {
        VeeWidgetSharing.actionRequestStore.write(
            WidgetActionRequest(action: isItem ? .runItem : .run, pluginID: pluginID, actionIndex: actionIndex))
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
