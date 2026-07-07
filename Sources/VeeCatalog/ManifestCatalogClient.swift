import Foundation

/// A catalog client for manifest-driven stores — a static HTTP host or a local
/// `file://` mirror. These have no Git-tree API, so a `vee-catalog.json`
/// manifest is required. Source fetches also work over `file://` for air-gapped
/// installs.
public struct ManifestCatalogClient: CatalogFetching {
    private static let manifestCap = 8 * 1024 * 1024
    private static let sourceCap = 8 * 1024 * 1024

    private let endpoints: StoreEndpoints
    private let tokenProvider: StoreTokenProviding?
    private let session: URLSession

    public init(config: StoreConfig, tokenProvider: StoreTokenProviding? = nil, session: URLSession = .shared) {
        self.endpoints = StoreEndpoints(config)
        self.tokenProvider = tokenProvider
        self.session = session
    }

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if endpoints.config.authMode == .token, let token = tokenProvider?.token(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func fetchIndex() async throws -> [CatalogEntry] {
        guard let manifestURL = endpoints.manifestURL, let rawBase = endpoints.rawBase else {
            throw CatalogError.unsupported
        }
        let data = try await load(manifestURL, cap: Self.manifestCap)
        return try CatalogManifestParser.parse(data, storeID: endpoints.config.id, rawBase: rawBase)
    }

    public func fetchSource(_ entry: CatalogEntry) async throws -> String {
        let data = try await load(entry.rawURL, cap: Self.sourceCap)
        return String(decoding: data, as: UTF8.self)
    }

    /// The manifest carries the catalog's last-updated date; entries inherit it,
    /// so no per-plugin call is needed.
    public func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? {
        entry.lastUpdated
    }

    /// Reads a URL with a hard byte cap. `file://` URLs are read directly (the
    /// URL loading system doesn't stream local files the way it does HTTP).
    private func load(_ url: URL, cap: Int) async throws -> Data {
        if url.isFileURL {
            let data = try Data(contentsOf: url)
            guard data.count <= cap else { throw CatalogError.responseTooLarge(limit: cap) }
            return data
        }
        let (bytes, response) = try await session.bytes(for: authorizedRequest(url))
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
}

/// Chooses the right ``CatalogFetching`` for a store: the GitHub client (which
/// auto-detects a manifest and falls back to the tree convention) for git
/// stores, and the manifest client for static HTTP / local mirrors.
public enum CatalogClientFactory {
    public static func make(
        for config: StoreConfig,
        tokenProvider: StoreTokenProviding? = nil,
        session: URLSession = .shared
    ) -> CatalogFetching {
        switch config.kind {
        case .github, .githubEnterprise:
            return GitHubCatalogClient(config: config, tokenProvider: tokenProvider, session: session)
        case .http, .local:
            return ManifestCatalogClient(config: config, tokenProvider: tokenProvider, session: session)
        }
    }
}
