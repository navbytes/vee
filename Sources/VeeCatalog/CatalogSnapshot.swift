import Foundation

/// Persists the last successfully loaded catalog index to disk so the app can
/// run an update scan at the next launch without any network fetch. The
/// snapshot is written only when the user themselves loads Discover — Vee
/// makes no unexplained network calls at launch (the exact complaint that
/// dogged xbar, matryer/xbar#859).
///
/// Lives beside the other per-directory ledgers (`.vee-provenance.json`,
/// `.vee-catalog-freshness.json`); the leading dot keeps it hidden in Finder
/// and out of the plugin-discovery scan.
/// ponytail: launch nudges lag until the user next opens Discover; a scheduled
/// background catalog refresh is the upgrade path if product ever wants one.
public struct CatalogSnapshotStore: Sendable {
    /// The directory the snapshot lives in — the plugins directory in production.
    public let directory: String

    static let snapshotName = ".vee-catalog-snapshot.json"

    public init(directory: String) {
        self.directory = directory
    }

    private var path: String {
        (directory as NSString).appendingPathComponent(Self.snapshotName)
    }

    /// The snapshotted entries, or empty if the snapshot is missing/unreadable —
    /// a corrupt snapshot just means no launch scan, never an error.
    public func load() -> [CatalogEntry] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return (try? JSONDecoder().decode([CatalogEntry].self, from: data)) ?? []
    }

    /// Replaces the snapshot with `entries`.
    public func save(_ entries: [CatalogEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
