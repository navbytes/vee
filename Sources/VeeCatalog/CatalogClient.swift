import Foundation

/// Fetches the plugin catalog and plugin sources. Behind a protocol so the UI
/// and tests can use a fake instead of hitting the network.
public protocol CatalogFetching: Sendable {
    func fetchIndex() async throws -> [CatalogEntry]
    func fetchSource(_ entry: CatalogEntry) async throws -> String
    /// The date of the last commit that touched `entry.path`, or `nil` if it
    /// can't be determined.
    ///
    /// - Important: This is **one GitHub API call per plugin**, so it must be
    ///   used *lazily* — fetch it when a single plugin's card/detail appears,
    ///   never eagerly across the whole grid — to avoid the unauthenticated
    ///   rate limit.
    func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date?
}

/// A failed catalog fetch (non-success HTTP status or an over-large response).
public enum CatalogError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case responseTooLarge(limit: Int)
    /// The operation isn't available for this store kind (e.g. a Git-tree index
    /// on a manifest-only static host).
    case unsupported
}

/// Supplies a store's bearer token, sourced from the Keychain in production.
/// Kept as a protocol so `VeeCatalog` never links `Security` and tests inject a
/// fake. The token is an app credential — it is never placed in a plugin's
/// environment.
public protocol StoreTokenProviding: Sendable {
    /// The current token for the store, or `nil` if none is stored.
    func token() -> String?
}

/// Live client backed by a GitHub (or GitHub Enterprise) repo: the Git-Trees
/// index API + a raw-content host. Configured by a ``StoreConfig`` so the same
/// client serves the public xbar catalog and an enterprise's internal repo.
public struct GitHubCatalogClient: CatalogFetching {
    // Response caps: the recursive tree JSON is a few MB; a single plugin source
    // and a one-commit response are small. Generous ceilings that still bound a
    // hostile/compromised upstream (or a redirect target) instead of buffering
    // an unbounded body into memory.
    private static let treeCap = 32 * 1024 * 1024
    private static let sourceCap = 8 * 1024 * 1024
    private static let commitsCap = 4 * 1024 * 1024

    private let endpoints: StoreEndpoints
    private let tokenProvider: StoreTokenProviding?
    private let session: URLSession

    /// The public xbar catalog — the original behavior. Kept so existing call
    /// sites (`GitHubCatalogClient()`) are unchanged.
    public init(session: URLSession = .shared) {
        self.init(config: BuiltInStores.xbar, tokenProvider: nil, session: session)
    }

    /// A client for an arbitrary configured store.
    public init(config: StoreConfig, tokenProvider: StoreTokenProviding? = nil, session: URLSession = .shared) {
        self.endpoints = StoreEndpoints(config)
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Sets `Accept` and, when the store uses token auth, an `Authorization`
    /// bearer header sourced from the token provider.
    private func authorized(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if endpoints.config.authMode == .token, let token = tokenProvider?.token(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func fetchIndex() async throws -> [CatalogEntry] {
        guard let treeURL = endpoints.treeURL, let repoBase = endpoints.rawBase else {
            throw CatalogError.unsupported
        }
        let data = try await boundedData(for: authorized(treeURL), cap: Self.treeCap)
        return try CatalogParser.parse(treeJSON: data, repoBase: repoBase, storeID: endpoints.config.id)
    }

    public func fetchSource(_ entry: CatalogEntry) async throws -> String {
        let data = try await boundedData(for: authorized(entry.rawURL), cap: Self.sourceCap)
        return String(decoding: data, as: UTF8.self)
    }

    /// Performs a request, rejecting a non-success HTTP status (so an error body
    /// isn't parsed as data) and streaming the body with a hard byte cap (so an
    /// oversized response can't exhaust memory). Redirects are still followed by
    /// URLSession, but the status + size checks apply to the final response.
    private func boundedData(for request: URLRequest, cap: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CatalogError.httpStatus(http.statusCode)
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > cap { throw CatalogError.responseTooLarge(limit: cap) }
        }
        return data
    }

    /// Fetches the last-commit date for `entry` from the GitHub commits API
    /// (`/commits?path=<path>&per_page=1`).
    ///
    /// - Important: One API call per plugin — call this lazily when a single
    ///   plugin is shown, never eagerly for the whole catalog, to stay under the
    ///   unauthenticated rate limit.
    public func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? {
        guard let url = endpoints.commitsURL(path: entry.path) else { return nil }
        let data = try await boundedData(for: authorized(url), cap: Self.commitsCap)
        return CatalogParser.parseLastCommitDate(commitsJSON: data)
    }
}
