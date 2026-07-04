import Foundation

/// Fetches the plugin catalog and plugin sources. Behind a protocol so the UI
/// and tests can use a fake instead of hitting the network.
public protocol CatalogFetching: Sendable {
    func fetchIndex() async throws -> [CatalogEntry]
    func fetchSource(_ entry: CatalogEntry) async throws -> String
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
}
