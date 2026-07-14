import Foundation

/// Whether an installed plugin's catalog entry is ahead of what's on disk.
/// Pure and unit-testable — mirrors ``ProvenanceStatus`` (which compares
/// installed vs. *local* changes) but compares installed vs. the *catalog*.
public enum CatalogUpdateStatus: Sendable, Equatable {
    /// The catalog has nothing newer than what's installed (same or older).
    case upToDate
    /// The catalog's copy is newer than the one installed.
    case updateAvailable
    /// The installed plugin's filename isn't in the fresh catalog at all
    /// (removed/renamed upstream, or never came from a catalog) — nothing to
    /// compare against.
    case notInCatalog
}

/// One installed plugin with a newer version available, identified by an
/// opaque token for the *specific* version found — the unit
/// ``CatalogUpdateCheck/pendingUpdates(installed:catalog:lastUpdated:)``
/// collects and the app de-dupes/coalesces into a single nudge.
public struct PluginUpdateCandidate: Sendable, Equatable {
    /// The installed plugin's filename (the ledger key, matching
    /// ``PluginProvenance/filename`` and ``ProvenanceStore``).
    public let filename: String
    /// Identifies which upstream version this is: the manifest-pinned hash
    /// when the store publishes one, else the upstream last-touched date
    /// (ISO-8601). Opaque — used only to tell "the same version already
    /// surfaced" from "a newer one since," never compared for ordering.
    public let versionToken: String

    public init(filename: String, versionToken: String) {
        self.filename = filename
        self.versionToken = versionToken
    }
}

/// Diffs installed plugins against a freshly-fetched catalog to find the ones
/// with a newer version upstream. No I/O: callers resolve `CatalogEntry` and
/// its "last touched upstream" date however they already do (a fetched index,
/// a ``CatalogFreshnessStore`` cache, `fetchLastUpdated`, …) and pass the
/// result in.
public enum CatalogUpdateCheck {
    /// Compares one installed plugin's provenance against its current catalog
    /// `entry` (already matched by origin — see `pendingUpdates`) to decide
    /// whether a newer version is available.
    ///
    /// - `entry == nil` → ``CatalogUpdateStatus/notInCatalog``.
    /// - A manifest-pinned ``CatalogEntry/declaredSHA256`` is authoritative
    ///   when present: any difference from the hash recorded at install is an
    ///   update, a match is up to date — no date needed.
    /// - Otherwise falls back to `catalogLastUpdated` (the upstream "last
    ///   touched" date) vs. ``PluginProvenance/installedAt``: strictly newer
    ///   is an update; equal, older, or unknown is not — a missing signal
    ///   must never be guessed into a false "update available".
    public static func status(installed: PluginProvenance, entry: CatalogEntry?, catalogLastUpdated: Date?) -> CatalogUpdateStatus {
        guard let entry else { return .notInCatalog }
        if let declared = entry.declaredSHA256 {
            return declared == installed.sha256 ? .upToDate : .updateAvailable
        }
        guard let catalogLastUpdated, catalogLastUpdated > installed.installedAt else { return .upToDate }
        return .updateAvailable
    }

    /// The opaque de-dupe token for `entry`'s current version — the same
    /// signal `status` compares, so "newer" and "the version we'd remember
    /// notifying about" always agree. `nil` when there's no signal to key on
    /// (in which case `status` can never have returned `.updateAvailable`
    /// either).
    public static func versionToken(entry: CatalogEntry, catalogLastUpdated: Date?) -> String? {
        entry.declaredSHA256 ?? catalogLastUpdated.map { ISO8601DateFormatter().string(from: $0) }
    }

    /// Scans every `installed` provenance record against the fresh `catalog`,
    /// returning the ones with an update available.
    ///
    /// Matching is by ORIGIN, not filename: an entry is only compared against
    /// the installed plugin whose ``PluginProvenance/sourceURL`` equals the
    /// entry's ``CatalogEntry/rawURL`` (the exact URL ``PluginInstaller``
    /// records at install time). With several stores configured, a same-named
    /// entry in a *different* store can therefore never forge an "update
    /// available" for a plugin installed from elsewhere. A store that moves a
    /// plugin to a new path stops matching — conservative by design: a missing
    /// signal is never guessed into an update.
    /// `lastUpdated` resolves a catalog entry's upstream "last touched" date.
    public static func pendingUpdates(
        installed: [PluginProvenance],
        catalog: [CatalogEntry],
        lastUpdated: (CatalogEntry) -> Date?
    ) -> [PluginUpdateCandidate] {
        let byOrigin = Dictionary(catalog.map { ($0.rawURL, $0) }, uniquingKeysWith: { first, _ in first })
        return installed
            .compactMap { record -> PluginUpdateCandidate? in
                let entry = byOrigin[record.sourceURL]
                let date = entry.flatMap(lastUpdated)
                guard status(installed: record, entry: entry, catalogLastUpdated: date) == .updateAvailable,
                      let entry, let token = versionToken(entry: entry, catalogLastUpdated: date)
                else { return nil }
                return PluginUpdateCandidate(filename: record.filename, versionToken: token)
            }
            .sorted { $0.filename < $1.filename }
    }
}
