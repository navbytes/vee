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
}

/// Live client backed by the GitHub API + raw content host.
public struct GitHubCatalogClient: CatalogFetching {
    private static let treeURL = URL(string: "https://api.github.com/repos/matryer/xbar-plugins/git/trees/main?recursive=1")!

    // Response caps: the recursive tree JSON is a few MB; a single plugin source
    // and a one-commit response are small. Generous ceilings that still bound a
    // hostile/compromised upstream (or a redirect target) instead of buffering
    // an unbounded body into memory.
    private static let treeCap = 32 * 1024 * 1024
    private static let sourceCap = 8 * 1024 * 1024
    private static let commitsCap = 4 * 1024 * 1024

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchIndex() async throws -> [CatalogEntry] {
        var request = URLRequest(url: Self.treeURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data = try await boundedData(for: request, cap: Self.treeCap)
        return try CatalogParser.parse(treeJSON: data)
    }

    public func fetchSource(_ entry: CatalogEntry) async throws -> String {
        let data = try await boundedData(for: URLRequest(url: entry.rawURL), cap: Self.sourceCap)
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
        guard let encodedPath = entry.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.github.com/repos/matryer/xbar-plugins/commits?path=\(encodedPath)&per_page=1")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let data = try await boundedData(for: request, cap: Self.commitsCap)
        return CatalogParser.parseLastCommitDate(commitsJSON: data)
    }
}
