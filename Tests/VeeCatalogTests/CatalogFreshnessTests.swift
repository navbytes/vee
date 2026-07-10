import XCTest
@testable import VeeCatalog

final class CatalogFreshnessStoreTests: XCTestCase {
    private func tempDir() -> String {
        NSTemporaryDirectory() + "vee-freshness-" + UUID().uuidString
    }

    func testRecordRoundTrips() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = CatalogFreshnessStore(directory: dir)
        let date = Date()

        try store.record(entryID: "xbar#System/CPU/cpu.5s.sh", date: date)

        let loaded = try XCTUnwrap(store.date(for: "xbar#System/CPU/cpu.5s.sh"))
        XCTAssertEqual(loaded.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMissingEntryIsNil() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertNil(CatalogFreshnessStore(directory: dir).date(for: "nope"))
    }

    func testMissingLedgerFileReturnsEmpty() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertEqual(CatalogFreshnessStore(directory: dir).all(), [:])
    }

    func testRecordOverwritesSameEntryID() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = CatalogFreshnessStore(directory: dir)

        try store.record(entryID: "x", date: Date(timeIntervalSince1970: 100))
        try store.record(entryID: "x", date: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.date(for: "x")?.timeIntervalSince1970, 200)
    }

    func testMultipleEntriesCoexist() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = CatalogFreshnessStore(directory: dir)

        try store.record(entryID: "a", date: Date(timeIntervalSince1970: 1))
        try store.record(entryID: "b", date: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(Set(store.all().keys), ["a", "b"])
    }

    // MARK: - TTL expiry

    func testFreshRecordIsServed() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = CatalogFreshnessStore(directory: dir)
        let now = Date(timeIntervalSince1970: 1_000_000)

        try store.record(entryID: "x", date: Date(timeIntervalSince1970: 1), fetchedAt: now)

        XCTAssertEqual(store.date(for: "x", now: now.addingTimeInterval(60)), Date(timeIntervalSince1970: 1),
                       "a record well within the TTL should still be served")
    }

    func testExpiredRecordReturnsNil() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = CatalogFreshnessStore(directory: dir)
        let fetchedAt = Date(timeIntervalSince1970: 1_000_000)

        try store.record(entryID: "x", date: Date(timeIntervalSince1970: 1), fetchedAt: fetchedAt)

        let expiredNow = fetchedAt.addingTimeInterval(CatalogFreshnessStore.ttl + 1)
        XCTAssertNil(store.date(for: "x", now: expiredNow),
                     "a record older than the TTL must be treated as a miss, not served forever")
    }

    func testAllReturnsRecordsWithFetchedAtEvenWhenExpired() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = CatalogFreshnessStore(directory: dir)
        let fetchedAt = Date(timeIntervalSince1970: 1_000_000)

        try store.record(entryID: "x", date: Date(timeIntervalSince1970: 1), fetchedAt: fetchedAt)

        // `all()` is TTL-agnostic — callers that seed an in-memory cache decide
        // staleness themselves against `Record.fetchedAt`.
        let record = try XCTUnwrap(store.all()["x"])
        XCTAssertEqual(record.fetchedAt.timeIntervalSince1970, fetchedAt.timeIntervalSince1970, accuracy: 0.001)
    }
}
