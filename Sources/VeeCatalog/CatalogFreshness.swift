import Foundation

/// Persists lazily-fetched "last updated" dates as a single JSON ledger keyed
/// by ``CatalogEntry/id``, stored in the plugins directory alongside the
/// plugins themselves (mirrors ``ProvenanceStore`` exactly — same shape, same
/// atomic-write convention). Without this, `PluginBrowserModel.lastUpdated`
/// resets every app launch and every `refresh()`, re-paying one commits-API
/// call per plugin each time. The base directory is injected so tests can use
/// a temporary directory.
///
/// Each entry also records when it was fetched (``Record/fetchedAt``), so a
/// record older than ``ttl`` is treated as a cache miss — otherwise a date
/// cached once would be served forever, and pressing Refresh could never
/// correct a stale freshness badge.
public struct CatalogFreshnessStore: Sendable {
    /// The directory the ledger lives in — the plugins directory in production.
    public let directory: String

    /// The ledger filename. The leading dot keeps it hidden in Finder and out
    /// of the plugin-discovery scan.
    static let ledgerName = ".vee-catalog-freshness.json"

    /// How long a cached record is served before it's treated as a miss and
    /// re-fetched from the network. 24h: long enough that normal browsing
    /// never re-pays the commits-API call, short enough that a stale badge
    /// self-corrects within a day of the upstream date actually moving.
    public static let ttl: TimeInterval = 24 * 60 * 60

    /// A cached "last updated" date plus when it was fetched, so staleness
    /// can be judged against ``ttl``.
    public struct Record: Codable, Equatable, Sendable {
        public let date: Date
        public let fetchedAt: Date

        public init(date: Date, fetchedAt: Date) {
            self.date = date
            self.fetchedAt = fetchedAt
        }
    }

    public init(directory: String) {
        self.directory = directory
    }

    private var ledgerPath: String {
        (directory as NSString).appendingPathComponent(Self.ledgerName)
    }

    /// All ledger records keyed by catalog entry id, or empty if the ledger is
    /// missing/unreadable. Unlike ``date(for:)`` this does not filter by TTL —
    /// callers that need to judge staleness themselves (e.g. seeding an
    /// in-memory cache once at startup) should check `Record.fetchedAt`.
    public func all() -> [String: Record] {
        guard let data = FileManager.default.contents(atPath: ledgerPath),
              let records = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return records
    }

    /// The date for `entryID`, or `nil` if there's no record or the record is
    /// older than ``ttl`` (a cache miss that should fall through to network).
    public func date(for entryID: String, now: Date = Date()) -> Date? {
        guard let record = all()[entryID], now.timeIntervalSince(record.fetchedAt) < Self.ttl else { return nil }
        return record.date
    }

    /// Inserts or replaces a record and rewrites the ledger.
    public func record(entryID: String, date: Date, fetchedAt: Date = Date()) throws {
        var records = all()
        records[entryID] = Record(date: date, fetchedAt: fetchedAt)
        try write(records)
    }

    private func write(_ records: [String: Record]) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(records)
        try data.write(to: URL(fileURLWithPath: ledgerPath), options: .atomic)
    }
}
