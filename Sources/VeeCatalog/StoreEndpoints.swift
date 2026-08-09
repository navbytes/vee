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

    /// The raw source URL for a repo-relative plugin path. `nil` if `path`
    /// isn't safe to join onto `rawBase` (see
    /// ``CatalogManifestParser/isSafeRelativePath(_:)``) or would resolve
    /// outside it.
    public func rawURL(path: String) -> URL? {
        guard let rawBase, let url = Self.joined(rawBase, path) else { return nil }
        return url
    }

    /// The optional curation manifest URL (`<root>/<manifestPath>`).
    public var manifestURL: URL? {
        guard let rawBase else { return nil }
        return Self.joined(rawBase, config.manifestPath)
    }

    /// Percent-encodes `path` and joins it onto `base` (a store root with a
    /// trailing slash), rejecting a `path` that escapes `base` — either
    /// syntactically (`..`, a leading `/`, or an embedded scheme), or, as a
    /// second and independent check, once `.standardized` resolves any
    /// `..`/`.` segments in the joined URL. Shared by `rawURL(path:)` and
    /// `manifestURL`, which join a path the same way `CatalogManifestParser`
    /// does.
    private static func joined(_ base: String, _ path: String) -> URL? {
        guard CatalogManifestParser.isSafeRelativePath(path),
              let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: base + encoded),
              url.standardized.absoluteString.hasPrefix(base)
        else { return nil }
        return url
    }
}
