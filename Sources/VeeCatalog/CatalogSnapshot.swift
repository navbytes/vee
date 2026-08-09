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

    /// Whether a freshly-loaded (possibly partial) entry set should replace
    /// the on-disk snapshot.
    ///
    /// - No failure at all → always save, even an empty result: a store
    ///   being disabled/removed (or simply publishing zero plugins) is a
    ///   legitimate reconciliation, and the snapshot must shrink to match —
    ///   otherwise a removed store's entries linger forever and drive a
    ///   phantom "update available" nudge for a plugin no store can even
    ///   fetch anymore.
    /// - Some entries despite a failure elsewhere → save (a genuine, if
    ///   partial, refresh is still better than a stale snapshot).
    /// - Nothing came back AND something failed → don't save: indistinguishable
    ///   from a transient outage, and stomping the last-known-good snapshot on
    ///   a network hiccup would be worse than leaving it stale one more cycle.
    public static func shouldSave(entries: [CatalogEntry], hadFailure: Bool) -> Bool {
        !hadFailure || !entries.isEmpty
    }
}
