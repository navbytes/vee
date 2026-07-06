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

    /// Classifies the current on-disk `currentSource` against a stored `record`.
    ///
    /// - No record → ``unknown``.
    /// - Record but the source can't be read → ``modified`` (the recorded bytes
    ///   are no longer present).
    /// - Record and matching hash → ``verified``; otherwise ``modified``.
    public static func evaluate(record: PluginProvenance?, currentSource: String?) -> ProvenanceStatus {
        guard let record else { return .unknown }
        guard let currentSource else { return .modified }
        return PluginHash.sha256Hex(currentSource) == record.sha256 ? .verified : .modified
    }
}

/// Persists ``PluginProvenance`` records as a single JSON ledger keyed by plugin
/// filename, stored in the plugins directory alongside the plugins themselves
/// (matching the `.vars.json` sidecar convention). The base directory is
/// injected so tests can use a temporary directory.
public struct ProvenanceStore: Sendable {
    /// The directory the ledger lives in — the plugins directory in production.
    public let directory: String
    private let fileManager: FileManager

    /// The ledger filename. The leading dot keeps it hidden in Finder and out of
    /// the plugin-discovery scan.
    static let ledgerName = ".vee-provenance.json"

    public init(directory: String, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    private var ledgerPath: String {
        (directory as NSString).appendingPathComponent(Self.ledgerName)
    }

    /// All records keyed by filename, or empty if the ledger is missing/unreadable.
    public func all() -> [String: PluginProvenance] {
        guard let data = fileManager.contents(atPath: ledgerPath),
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
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(records)
        try data.write(to: URL(fileURLWithPath: ledgerPath), options: .atomic)
    }
}
