import CryptoKit
import Foundation

/// SHA-256 hex helper — pure, no I/O. `CryptoKit` is an Apple system framework,
/// so this adds zero third-party dependencies.
public enum PluginHash {
    /// Lowercase hex-encoded SHA-256 of `source`'s UTF-8 bytes.
    public static func sha256Hex(_ source: String) -> String {
        sha256Hex(Data(source.utf8))
    }

    /// Lowercase hex-encoded SHA-256 of arbitrary bytes.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Where a catalog-installed plugin came from and what its source hashed to at
/// install time. Persisted so a later silent change — a local edit or a
/// re-install from a different source — is detectable.
public struct PluginProvenance: Codable, Sendable, Equatable {
    /// The installed plugin's filename (the ledger key), e.g. `cpu.5s.sh`.
    public var filename: String
    /// The raw source URL the plugin was fetched from at install.
    public var sourceURL: URL
    /// Lowercase hex SHA-256 of the source that was written to disk.
    public var sha256: String
    /// When the record was written.
    public var installedAt: Date

    public init(filename: String, sourceURL: URL, sha256: String, installedAt: Date) {
        self.filename = filename
        self.sourceURL = sourceURL
        self.sha256 = sha256
        self.installedAt = installedAt
    }

    /// Builds a record for `source` fetched from `sourceURL`, hashing it now.
    public init(filename: String, sourceURL: URL, source: String, installedAt: Date = Date()) {
        self.init(
            filename: filename,
            sourceURL: sourceURL,
            sha256: PluginHash.sha256Hex(source),
            installedAt: installedAt
        )
    }
}

/// Whether an installed plugin's on-disk source still matches what was recorded
/// at install.
public enum ProvenanceStatus: Sendable, Equatable {
    /// The current source hashes to the recorded value — untouched since install.
    case verified
    /// The hash differs — edited locally or replaced from another source.
    case modified
    /// No provenance record (e.g. a hand-authored plugin, or one installed
    /// before provenance tracking existed).
    case unknown
    /// A provenance record exists for this filename, but it was recorded for
    /// a DIFFERENT source URL than the catalog entry being displayed — e.g.
    /// two stores publish a same-named plugin and the other store's copy is
    /// what's actually installed. Never conflate this with `.verified`:
    /// installing this entry would overwrite whatever is there now.
    case installedFromAnotherSource

    /// Classifies the current on-disk `currentSource` against a stored
    /// `record`, from the point of view of one specific catalog entry
    /// (`entrySourceURL` — its `rawURL`).
    ///
    /// - No record → ``unknown``.
    /// - A record recorded for a different source URL → ``installedFromAnotherSource``,
    ///   regardless of hash — matches by origin the same way
    ///   ``CatalogUpdateCheck/pendingUpdates(installed:catalog:lastUpdated:)``
    ///   already does, so a same-filename entry from another store can never
    ///   borrow this filename's badge. Origin is compared loosely
    ///   (`sameOrigin`, below) so a store migrating http→https, or a
    ///   trailing-slash difference in its raw base, doesn't itself read as
    ///   "another source" — only a genuinely different host or path does.
    /// - Same origin, but the source can't be read → ``modified`` (the
    ///   recorded bytes are no longer present).
    /// - Same origin and matching hash → ``verified``; otherwise ``modified``.
    public static func evaluate(record: PluginProvenance?, currentSource: String?, entrySourceURL: URL) -> ProvenanceStatus {
        guard let record else { return .unknown }
        guard sameOrigin(record.sourceURL, entrySourceURL) else { return .installedFromAnotherSource }
        guard let currentSource else { return .modified }
        return PluginHash.sha256Hex(currentSource) == record.sha256 ? .verified : .modified
    }

    /// Whether two source URLs represent "the same place a plugin came
    /// from" for provenance-attribution purposes: host compared
    /// case-insensitively, one trailing slash on the path ignored, and —
    /// deliberately — scheme ignored entirely, so a store's http→https
    /// migration doesn't make its own install history look foreign. A
    /// genuinely different host or path still counts as a different origin.
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        func normalized(_ url: URL) -> String {
            var path = url.path
            if path.hasSuffix("/") { path.removeLast() }
            return (url.host ?? "").lowercased() + path
        }
        return normalized(a) == normalized(b)
    }
}

/// Persists ``PluginProvenance`` records as a single JSON ledger keyed by plugin
/// filename, stored in the plugins directory alongside the plugins themselves
/// (matching the `.vars.json` sidecar convention). The base directory is
/// injected so tests can use a temporary directory.
public struct ProvenanceStore: Sendable {
    /// The directory the ledger lives in — the plugins directory in production.
    public let directory: String

    /// The ledger filename. The leading dot keeps it hidden in Finder and out of
    /// the plugin-discovery scan.
    static let ledgerName = ".vee-provenance.json"

    public init(directory: String) {
        self.directory = directory
    }

    private var ledgerPath: String {
        (directory as NSString).appendingPathComponent(Self.ledgerName)
    }

    /// All records keyed by filename, or empty if the ledger is missing/unreadable.
    public func all() -> [String: PluginProvenance] {
        guard let data = FileManager.default.contents(atPath: ledgerPath),
              let records = try? JSONDecoder().decode([String: PluginProvenance].self, from: data)
        else { return [:] }
        return records
    }

    /// The record for `filename`, if one exists.
    public func record(for filename: String) -> PluginProvenance? {
        all()[filename]
    }

    /// Inserts or replaces a record and rewrites the ledger.
    public func record(_ provenance: PluginProvenance) throws {
        var records = all()
        records[provenance.filename] = provenance
        try write(records)
    }

    /// Removes the record for `filename` (no-op if absent).
    public func remove(filename: String) throws {
        var records = all()
        guard records.removeValue(forKey: filename) != nil else { return }
        try write(records)
    }

    private func write(_ records: [String: PluginProvenance]) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(records)
        try data.write(to: URL(fileURLWithPath: ledgerPath), options: .atomic)
    }
}
