import Foundation

/// An action requested via the `vee://` or `swiftbar://` URL scheme.
public enum URLAction: Equatable, Sendable {
    case refreshAll
    case refreshPlugin(name: String)
    case enablePlugin(name: String)
    case disablePlugin(name: String)
    case togglePlugin(name: String)
    case notify(title: String, subtitle: String, body: String, href: URL?)
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
        case "notify":
            return .notify(
                title: param("title") ?? "",
                subtitle: param("subtitle") ?? "",
                body: param("body") ?? "",
                href: param("href").flatMap(URL.init(string:))
            )
        default:
            return .unknown
        }
    }
}
