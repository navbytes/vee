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

/// Live client backed by the GitHub API + raw content host.
public struct GitHubCatalogClient: CatalogFetching {
    private static let treeURL = URL(string: "https://api.github.com/repos/matryer/xbar-plugins/git/trees/main?recursive=1")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchIndex() async throws -> [CatalogEntry] {
        var request = URLRequest(url: Self.treeURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try CatalogParser.parse(treeJSON: data)
    }

    public func fetchSource(_ entry: CatalogEntry) async throws -> String {
        let (data, _) = try await session.data(from: entry.rawURL)
        return String(decoding: data, as: UTF8.self)
    }

    /// Fetches the last-commit date for `entry` from the GitHub commits API
    /// (`/commits?path=<path>&per_page=1`).
    ///
    /// - Important: One API call per plugin — call this lazily when a single
    ///   plugin is shown, never eagerly for the whole catalog, to stay under the
    ///   unauthenticated rate limit.
    public func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? {
        guard let encodedPath = entry.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.github.com/repos/matryer/xbar-plugins/commits?path=\(encodedPath)&per_page=1")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return CatalogParser.parseLastCommitDate(commitsJSON: data)
    }
}
