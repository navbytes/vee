import AppKit
import Foundation
import UserNotifications
import VeeCatalog
import VeeCore
import VeePluginFormat

/// Tracks which plugin ids have been silenced for the current session, so a
/// monitor-style plugin the user has muted stops posting further alerts until
/// Vee restarts. Pure value type — unit-testable without the notification UI.
struct NotificationSuppressor: Sendable {
    private var silenced: Set<String> = []

    /// Suppresses future alerts from `pluginID` for the rest of the session.
    mutating func silence(_ pluginID: String) { silenced.insert(pluginID) }

    /// Whether `pluginID` has been silenced.
    func isSilenced(_ pluginID: String) -> Bool { silenced.contains(pluginID) }
}

/// The action Vee should take in response to a notification interaction. Derived
/// purely from the tapped action identifier and the notification's payload, so
/// the routing is unit-testable without the system notification UI.
enum NotificationAction: Equatable, Sendable {
    case rerun(pluginID: String)
    case silence(pluginID: String)
    case openLog(pluginID: String)
    case openHref(URL)
    /// Tapped a "N plugin updates available" catalog nudge — open Discover.
    /// Install itself is never triggered from here; the trust gate still owns
    /// it, same as any other Discover update.
    case openDiscover
    case none
}

/// Category and action identifiers for actionable, time-sensitive plugin alerts,
/// plus the pure mapping from a tapped action to a `NotificationAction`.
enum NotificationRouter {
    /// Category registered on the notification center for monitor-style alerts.
    static let categoryID = "VEE_PLUGIN_ALERT"
    static let rerunAction = "RERUN"
    static let silenceAction = "SILENCE"
    static let openLogAction = "OPEN_LOG"

    /// Category for a coalesced "N plugin updates available" catalog nudge —
    /// no custom actions, just a default tap that opens Discover.
    static let updateCategoryID = "VEE_CATALOG_UPDATE"

    /// Maps a tapped action identifier + payload to the work Vee should perform.
    /// The three custom actions require a plugin id; the default tap (the whole
    /// banner) opens Discover for a catalog-update nudge, else falls back to
    /// opening the `href`, preserving legacy behavior.
    static func route(actionIdentifier: String, pluginID: String?, href: URL?, isUpdateNudge: Bool = false) -> NotificationAction {
        switch actionIdentifier {
        case rerunAction:
            if let pluginID { return .rerun(pluginID: pluginID) }
            return .none
        case silenceAction:
            if let pluginID { return .silence(pluginID: pluginID) }
            return .none
        case openLogAction:
            if let pluginID { return .openLog(pluginID: pluginID) }
            return .none
        case UNNotificationDismissActionIdentifier:
            // Swiping the banner away must never open the href — only an explicit
            // tap does. (Delivered only if the category opts into it, but routed
            // correctly regardless.)
            return .none
        default:
            // The default tap (UNNotificationDefaultActionIdentifier) opens
            // Discover for a catalog-update nudge, else the click-through URL
            // when present, matching SwiftBar.
            if isUpdateNudge { return .openDiscover }
            if let href { return .openHref(href) }
            return .none
        }
    }
}

/// Posts user notifications (from `swiftbar://notify`). No-ops gracefully when
/// notifications aren't authorized. Plugin-originated alerts gain Re-run /
/// Silence / Open-log action buttons and a time-sensitive interruption level.
@MainActor
enum Notifier {
    nonisolated private static let log = VeeLog.make("notifier")

    /// userInfo key carrying the originating plugin's id on plugin alerts.
    /// Read from the nonisolated delegate, so it must be nonisolated.
    nonisolated static let pluginIDKey = "vee.pluginID"

    /// Retained delegate that routes notification interactions. `.delegate` is
    /// weak, so this must outlive setup.
    private static let delegate = NotifierDelegate()

    /// Per-session set of plugin ids whose alerts the user has silenced.
    private static var suppressor = NotificationSuppressor()

    /// Wired from the app so notification actions can drive the live plugins.
    private static var onRerun: (@MainActor (String) -> Void)?
    private static var onOpenLog: (@MainActor (String) -> Void)?
    /// Wired from the app so tapping a catalog-update nudge opens Discover.
    /// Defaults to a no-op so `configure` callers that predate this feature
    /// still compile and simply do nothing on tap until they wire it up.
    private static var onOpenDiscover: (@MainActor () -> Void) = {}

    /// UNUserNotificationCenter requires a real app bundle; skip when running as
    /// a bare binary (e.g. `swift run vee` during development).
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// Connects the action buttons to the app: Re-run refreshes the plugin,
    /// Open-log opens its debug console. Silence is handled internally.
    /// `onOpenDiscover` defaults to a no-op — optional so existing call sites
    /// are unaffected until they wire up the Discover surface.
    static func configure(
        onRerun: @escaping @MainActor (String) -> Void,
        onOpenLog: @escaping @MainActor (String) -> Void,
        onOpenDiscover: @escaping @MainActor () -> Void = {}
    ) {
        Self.onRerun = onRerun
        Self.onOpenLog = onOpenLog
        Self.onOpenDiscover = onOpenDiscover
    }

    /// Whether we've already asked the system for notification permission this
    /// launch. The prompt is deferred until the first alert (see `post`).
    private static var didRequestAuthorization = false

    /// Registers the delegate and action categories so plugin-alert buttons work.
    /// Does *not* prompt for permission — that's deferred to the first alert.
    static func prepare() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([pluginAlertCategory()])
    }

    /// Prompts for notification permission, once per launch. Called lazily the
    /// first time a plugin posts an alert, so the system dialog appears in
    /// context (a plugin needs to notify you) rather than at a cold launch.
    static func requestAuthorization() {
        guard isAvailable, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { Self.log.error("auth failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// The `VEE_PLUGIN_ALERT` category with Re-run / Silence / Open-log actions.
    private static func pluginAlertCategory() -> UNNotificationCategory {
        let rerun = UNNotificationAction(identifier: NotificationRouter.rerunAction, title: "Re-run", options: [])
        let silence = UNNotificationAction(identifier: NotificationRouter.silenceAction, title: "Silence", options: [.destructive])
        let openLog = UNNotificationAction(identifier: NotificationRouter.openLogAction, title: "Open Log", options: [.foreground])
        return UNNotificationCategory(
            identifier: NotificationRouter.categoryID,
            actions: [rerun, silence, openLog],
            intentIdentifiers: [],
            options: []
        )
    }

    static func post(title: String, subtitle: String, body: String, href: URL? = nil, pluginID: String? = nil) {
        // Skip alerts the user silenced this session for this plugin.
        if let pluginID, suppressor.isSilenced(pluginID) {
            Self.log.info("notification suppressed for plugin \(pluginID, privacy: .public)")
            return
        }
        guard isAvailable else {
            Self.log.info("notification skipped (no bundle): \(title, privacy: .public)")
            return
        }
        // Ask for permission the first time a plugin actually needs it.
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Vee" : title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        content.body = body
        // Carry the click-through URL so the delegate can open it on tap.
        if let href { content.userInfo[NotifierDelegate.hrefKey] = href.absoluteString }
        // Plugin-originated alerts become actionable and time-sensitive.
        // NOTE: `.timeSensitive` only breaks through Focus when the app is signed
        // with the `com.apple.developer.usernotifications.time-sensitive`
        // entitlement; without it the system gracefully downgrades to `.active`.
        if let pluginID {
            content.categoryIdentifier = NotificationRouter.categoryID
            content.userInfo[pluginIDKey] = pluginID
            content.interruptionLevel = .timeSensitive
        }
        // Coalesce a monitor's repeated alerts: reuse the plugin id as the request
        // identifier so the newest replaces the prior one instead of stacking up
        // dozens of banners. Non-plugin notifications stay unique.
        let identifier = pluginID ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Self.log.error("post failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Performs a routed notification action. Runs on the main actor.
    static func handle(_ action: NotificationAction) {
        switch action {
        case .rerun(let id):
            onRerun?(id)
        case .silence(let id):
            suppressor.silence(id)
            Self.log.info("silenced notifications for plugin \(id, privacy: .public)")
        case .openLog(let id):
            onOpenLog?(id)
        case .openHref(let url):
            NSWorkspace.shared.open(url)
        case .openDiscover:
            onOpenDiscover()
        case .none:
            break
        }
    }

    // MARK: - Catalog update nudge

    /// Notifies about installed plugins with a newer version in the catalog:
    /// one coalesced banner ("2 plugin updates available"), de-duped against
    /// versions already surfaced (persisted in `store`). No-op if every
    /// candidate was already notified. Never installs anything — tapping the
    /// banner only opens Discover; the trust gate still owns the actual
    /// update, same as any other Discover install/update.
    /// `installedFilenames`, when provided, prunes ledger entries for plugins
    /// that are no longer installed before the de-dupe check.
    static func notifyCatalogUpdates(
        _ candidates: [PluginUpdateCandidate],
        installedFilenames: Set<String>? = nil,
        store: UpdateNotificationStore = UpdateNotificationStore()
    ) {
        if let installedFilenames { store.prune(keepingOnly: installedFilenames) }
        let unseen = unnotifiedCandidates(candidates, store: store)
        guard !unseen.isEmpty else { return }
        guard isAvailable else {
            Self.log.info("catalog-update notification skipped (no bundle): \(unseen.count, privacy: .public) plugin(s)")
            return
        }
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = "Vee"
        content.body = CatalogUpdateNudgeText.body(for: unseen.map(\.filename))
        content.categoryIdentifier = NotificationRouter.updateCategoryID
        // Stable identifier: a later scan replaces this banner instead of
        // stacking a new one alongside it, mirroring the plugin-alert
        // coalescing above.
        let request = UNNotificationRequest(identifier: "vee.catalog-updates", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                // Not marked as notified: a banner that never posted (e.g.
                // notifications denied) must not permanently suppress this
                // version — the next scan is free to try again.
                Self.log.error("catalog-update notification failed: \(error.localizedDescription, privacy: .public)")
            } else {
                store.markNotified(unseen)
            }
        }
    }

    /// The candidates not already notified about (same plugin *and* version
    /// already seen is skipped; a new version for a previously-seen plugin is
    /// not). Exposed separately from `notifyCatalogUpdates` so the de-dupe
    /// filter is testable without touching `UNUserNotificationCenter`.
    static func unnotifiedCandidates(_ candidates: [PluginUpdateCandidate], store: UpdateNotificationStore) -> [PluginUpdateCandidate] {
        candidates.filter { !store.hasNotified($0) }
    }
}

/// Handles notification interaction. Custom action buttons re-run / silence /
/// open the log for the originating plugin; tapping the banner opens its `href`,
/// matching SwiftBar's `notify?href=` behavior. Delegate callbacks are
/// nonisolated, so the Sendable routed action is dispatched onto the main actor.
private final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let hrefKey = "vee.href"

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let userInfo = content.userInfo
        let pluginID = userInfo[Notifier.pluginIDKey] as? String
        let href = (userInfo[Self.hrefKey] as? String).flatMap { URL(string: $0) }.flatMap { URLScheme.isSafeToOpen($0) ? $0 : nil }
        let isUpdateNudge = content.categoryIdentifier == NotificationRouter.updateCategoryID
        let action = NotificationRouter.route(actionIdentifier: response.actionIdentifier, pluginID: pluginID, href: href, isUpdateNudge: isUpdateNudge)
        // `action` is Sendable; capture no non-Sendable self in the hop.
        Task { @MainActor in Notifier.handle(action) }
        completionHandler()
    }

    // Still show banners while Vee is frontmost (e.g. a manager window is open),
    // and add to Notification Center (`.list`) so a foreground alert isn't lost
    // the moment its banner auto-dismisses.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
