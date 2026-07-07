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
}
