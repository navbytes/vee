import AppKit
import Foundation
import VeePluginFormat

/// An action requested via the `vee://` or `swiftbar://` URL scheme.
public enum URLAction: Equatable, Sendable {
    case refreshAll
    case refreshPlugin(name: String)
    case enablePlugin(name: String)
    case disablePlugin(name: String)
    case togglePlugin(name: String)
    case addPlugin(src: URL)
    case setEphemeralPlugin(name: String, content: String, exitAfter: TimeInterval?)
    case notify(title: String, subtitle: String, body: String, href: URL?, pluginID: String?)
    case unknown
}

/// Parses `vee://` / `swiftbar://` URLs into actions. Pure and testable; the
/// app performs the resulting action.
public enum URLActionRouter {
    public static func parse(_ url: URL) -> URLAction {
        guard url.scheme == "vee" || url.scheme == "swiftbar" else { return .unknown }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        func param(_ key: String) -> String? { items.first { $0.name == key }?.value }

        // The action is the host (swiftbar://refreshplugin?...).
        let action = (url.host ?? "").lowercased()
        let name = param("name") ?? param("path") ?? ""

        switch action {
        case "refreshallplugins", "refreshall":
            return .refreshAll
        case "refreshplugin":
            return .refreshPlugin(name: name)
        case "enableplugin":
            return .enablePlugin(name: name)
        case "disableplugin":
            return .disablePlugin(name: name)
        case "toggleplugin":
            return .togglePlugin(name: name)
        case "addplugin":
            guard let src = (param("src") ?? param("url")).flatMap(URL.init(string:)) else { return .unknown }
            return .addPlugin(src: src)
        case "setephemeralplugin":
            return .setEphemeralPlugin(
                name: name,
                content: param("content") ?? "",
                // `exitafter` reaches a `UInt64(seconds * 1e9)` conversion at
                // the use site, which traps on overflow — any web page can
                // open this URL with e.g. `exitafter=1e40`. Reject non-finite
                // values (`inf`/`nan`) and clamp to a 24h ceiling; a deep link
                // that wants longer isn't really an ephemeral status item.
                exitAfter: param("exitafter").flatMap(Double.init).flatMap { $0.isFinite ? min(max($0, 0), 86_400) : nil }
            )
        case "notify":
            // `plugin=` names the originating plugin (SwiftBar-compatible); when
            // present the alert gains Re-run / Silence / Open-log actions.
            return .notify(
                title: param("title") ?? "",
                subtitle: param("subtitle") ?? "",
                body: param("body") ?? "",
                href: param("href").flatMap(URL.init(string:)).flatMap { URLScheme.isSafeToOpen($0) ? $0 : nil },
                pluginID: param("plugin").flatMap { $0.isEmpty ? nil : $0 }
            )
        default:
            return .unknown
        }
    }

    // MARK: - D8: confirmation gate for state-changing / spoofable deep links
    //
    // `parse(_:)` above stays pure and unconditional on purpose — it's the
    // parsing layer, and existing callers/tests key off it returning the
    // exact same `URLAction` for the same URL every time. `routeGated(_:)`
    // below is the actual entry point a deep link should go through: it
    // parses, then — for the handful of actions QA flagged as harmful
    // without the user ever seeing them coming — blocks on an explicit
    // confirmation (mirroring the "see it before it lands" gate
    // `AppController.confirmInstall` already applies to `addplugin`) before
    // handing the action back. A declined confirmation resolves to
    // `.unknown`, which the app's existing dispatch already no-ops on, so no
    // change is needed there.
    //
    // NOT YET WIRED IN: `AppController.application(_:open:)` still calls
    // `parse` directly. Switching that one call to `routeGated` is a
    // one-line change in a file this fix isn't allowed to touch — flagged in
    // the handoff instead of made here.

    /// Whether `action` is destructive/spoofable enough to need an explicit
    /// user confirmation before it's allowed to reach the app's existing
    /// dispatch. Scoped to the concretely harmful cases: silently disabling a
    /// plugin (`disableplugin`, and `toggleplugin` — toggling an already-
    /// enabled plugin has the identical effect, so it's the same bypass, not
    /// a separate risk) and a notification carrying a click-through `href`
    /// (phishing bait a spoofed "Vee" notification can carry). A title/body-
    /// only notification and turning a plugin ON stay frictionless.
    static func needsConfirmation(_ action: URLAction) -> Bool {
        switch action {
        case .disablePlugin, .togglePlugin:
            return true
        case .notify(_, _, _, let href, _):
            return href != nil
        default:
            return false
        }
    }

    /// A human-readable confirmation prompt for a gated action.
    static func confirmationPrompt(for action: URLAction) -> (message: String, info: String) {
        switch action {
        case .disablePlugin(let name):
            return ("Disable “\(name)”?", "A web page or app asked Vee to disable this plugin via a deep link.")
        case .togglePlugin(let name):
            return ("Change “\(name)”’s enabled state?", "A web page or app asked Vee to toggle this plugin via a deep link.")
        case .notify(let title, _, _, let href, _):
            let named = title.isEmpty ? "a notification" : "a notification titled “\(title)”"
            return ("Allow this notification?", "A web page or app asked Vee to post \(named) that opens \(href?.absoluteString ?? "a link") when clicked.")
        default:
            return ("Allow this action?", "")
        }
    }

    /// Confirms a gated action before `routeGated` hands it back — the seam a
    /// real `NSAlert` hangs off of in production (`defaultConfirm`); tests
    /// substitute a canned answer so verifying the gate never needs to pop a
    /// live modal dialog. `nonisolated(unsafe)`: only ever read/written from
    /// the main thread in practice (deep links arrive on main; tests run
    /// serially), the same external-synchronization carve-out
    /// `SymbolImageFactory`'s cache uses.
    nonisolated(unsafe) static var confirm: (_ message: String, _ info: String) -> Bool = defaultConfirm

    /// Parses `url`, then gates a destructive/spoofable action (D8) behind
    /// `confirm` before returning it. A declined confirmation resolves to
    /// `.unknown`; every other action (including a plain, href-less
    /// `notify`) passes through exactly like `parse(_:)`.
    public static func routeGated(_ url: URL) -> URLAction {
        let action = parse(url)
        guard needsConfirmation(action) else { return action }
        let (message, info) = confirmationPrompt(for: action)
        return confirm(message, info) ? action : .unknown
    }

    /// Production default: a real, blocking `NSAlert`. `MainActor.assumeIsolated`
    /// rather than marking this function itself `@MainActor` — it must stay
    /// assignable to `confirm`'s plain, non-isolated closure type, and its
    /// only caller (`routeGated`, in turn only ever called from
    /// `AppController.application(_:open:)`) already guarantees the main
    /// thread, the same trust `AppController`'s own Darwin-notification
    /// callbacks place in `MainActor.assumeIsolated`.
    private static func defaultConfirm(message: String, info: String) -> Bool {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = message
            alert.informativeText = info
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }
}
