import Foundation

/// Builds the concrete URLs a store client fetches, from a ``StoreConfig``. Pure
/// and testable — no network. For the built-in xbar store (``BuiltInStores/xbar``)
/// every URL here reproduces byte-for-byte the literal Vee used before custom
/// stores existed, which is the regression lock in `StoreEndpointsTests`.
public struct StoreEndpoints: Sendable {
    public let config: StoreConfig

    public init(_ config: StoreConfig) {
        self.config = config
    }

    /// A host's string form without a trailing slash, so path joins don't double
    /// up (`https://api.github.com/` and `https://api.github.com` behave alike).
    private static func trimmedHost(_ url: URL?) -> String? {
        guard let s = url?.absoluteString, !s.isEmpty else { return nil }
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    private var apiBase: String? {
        Self.trimmedHost(config.apiHost)
    }

    /// The raw-content base with a trailing slash, e.g.
    /// `https://raw.githubusercontent.com/matryer/xbar-plugins/main/` for xbar,
    /// or the `http`/`local` store's `baseURL` with a trailing slash. Plugin
    /// source URLs are this joined with a repo-relative path.
    public var rawBase: String? {
        switch config.kind {
        case .github, .githubEnterprise:
            guard let host = Self.trimmedHost(config.rawHost),
                  let owner = config.owner, let repo = config.repo
            else { return nil }
            return "\(host)/\(owner)/\(repo)/\(config.ref)/"
        case .http, .local:
            guard let host = Self.trimmedHost(config.baseURL) else { return nil }
            return "\(host)/"
        }
    }

    /// The Git-Trees index URL for `github`/`githubEnterprise`; `nil` for
    /// non-git stores (which are manifest-driven instead).
    public var treeURL: URL? {
        switch config.kind {
        case .github, .githubEnterprise:
            guard let apiBase, let owner = config.owner, let repo = config.repo else { return nil }
            return URL(string: "\(apiBase)/repos/\(owner)/\(repo)/git/trees/\(config.ref)?recursive=1")
        case .http, .local:
            return nil
        }
    }

    /// The commits URL for a single plugin's last-updated date; `nil` for
    /// non-git stores.
    public func commitsURL(path: String) -> URL? {
        switch config.kind {
        case .github, .githubEnterprise:
            guard let apiBase, let owner = config.owner, let repo = config.repo,
                  let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else { return nil }
            return URL(string: "\(apiBase)/repos/\(owner)/\(repo)/commits?path=\(encoded)&per_page=1")
        case .http, .local:
            return nil
        }
    }

    /// The raw source URL for a repo-relative plugin path.
    public func rawURL(path: String) -> URL? {
        guard let rawBase,
              let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: rawBase + encoded)
    }

    /// The optional curation manifest URL (`<root>/<manifestPath>`).
    public var manifestURL: URL? {
        guard let rawBase,
              let encoded = config.manifestPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: rawBase + encoded)
    }
}
