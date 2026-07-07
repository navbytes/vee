import Foundation

/// A store's optional curation manifest (`vee-catalog.json`). When present it is
/// authoritative: entries carry their own metadata, an integrity hash, and an
/// optional signature, so Vee needn't download every file to build the grid.
public struct CatalogManifest: Codable, Sendable, Equatable {
    /// Schema version (`vee_catalog`). Vee rejects a major it doesn't understand.
    public var version: Int
    public var name: String?
    public var homepage: String?
    /// ISO-8601 timestamp of the last catalog change, if the author sets it.
    public var updated: String?
    /// Base64 Ed25519 public key the store signs entries with. A policy-pinned
    /// key (`StoreConfig.pinnedSigningKey`) overrides this.
    public var signingKey: String?
    public var plugins: [ManifestPlugin]

    enum CodingKeys: String, CodingKey {
        case version = "vee_catalog"
        case name, homepage, updated
        case signingKey = "signing_key"
        case plugins
    }

    /// The parsed `updated` timestamp, if present and well-formed.
    public var updatedDate: Date? {
        updated.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

/// One plugin entry in a ``CatalogManifest``.
public struct ManifestPlugin: Codable, Sendable, Equatable {
    /// Repo-relative path, e.g. `Oncall/pager.1m.py`.
    public var path: String
    public var title: String?
    public var category: String?
    public var summary: String?
    public var author: String?
    /// Minimum macOS version (e.g. `26.0`).
    public var minMacOS: String?
    /// Lowercase-hex SHA-256 the source must match at install.
    public var sha256: String?
    /// Base64 Ed25519 signature over the source's SHA-256 digest.
    public var signature: String?
    public var deprecated: Bool?
    public var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case path, title, category, summary, author
        case minMacOS = "min_macos"
        case sha256, signature, deprecated, tags
    }
}

/// Parses a `vee-catalog.json` manifest into catalog entries. Pure and testable.
public enum CatalogManifestParser {
    /// The manifest schema version Vee implements.
    public static let currentVersion = 1
    /// Cap on entries so a hostile manifest can't blow up memory.
    static let maxPlugins = 5000

    public enum ManifestError: Error, Equatable, Sendable {
        case unsupportedVersion(Int)
        case tooManyPlugins(Int)
        case malformed
    }

    /// Decodes the raw manifest object.
    public static func parseManifest(_ data: Data) throws -> CatalogManifest {
        do {
            return try JSONDecoder().decode(CatalogManifest.self, from: data)
        } catch {
            throw ManifestError.malformed
        }
    }

    /// Decodes a manifest and maps it to catalog entries for `storeID`, resolving
    /// each source URL against `rawBase` (a store root with a trailing slash).
    public static func parse(_ data: Data, storeID: StoreID, rawBase: String) throws -> [CatalogEntry] {
        let manifest = try parseManifest(data)
        guard manifest.version == currentVersion else {
            throw ManifestError.unsupportedVersion(manifest.version)
        }
        guard manifest.plugins.count <= maxPlugins else {
            throw ManifestError.tooManyPlugins(manifest.plugins.count)
        }

        let lastUpdated = manifest.updatedDate
        return manifest.plugins.compactMap { plugin -> CatalogEntry? in
            let components = plugin.path.split(separator: "/").map(String.init)
            guard let filename = components.last, !filename.isEmpty else { return nil }
            let category = plugin.category ?? (components.count >= 2 ? components[0] : "Plugins")
            guard let encoded = plugin.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let rawURL = URL(string: rawBase + encoded)
            else { return nil }

            return CatalogEntry(
                storeID: storeID,
                path: plugin.path,
                category: category,
                filename: filename,
                rawURL: rawURL,
                lastUpdated: lastUpdated,
                manifestTitle: plugin.title,
                manifestSummary: plugin.summary,
                declaredSHA256: plugin.sha256,
                signature: plugin.signature,
                manifestSigningKey: manifest.signingKey,
                minMacOS: plugin.minMacOS,
                deprecated: plugin.deprecated ?? false
            )
        }
        .sorted { $0.path < $1.path }
    }
}
