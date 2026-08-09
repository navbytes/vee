import XCTest
@testable import VeeCatalog

final class CatalogSnapshotStoreTests: XCTestCase {
    private var directory: String!

    override func setUpWithError() throws {
        directory = NSTemporaryDirectory() + "vee-snapshot-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: directory)
    }

    private func entry(filename: String) -> CatalogEntry {
        CatalogEntry(
            path: "System/\(filename)",
            category: "System",
            filename: filename,
            rawURL: URL(string: "https://example.com/\(filename)")!,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            declaredSHA256: "abc123"
        )
    }

    func testRoundTripPreservesEntries() throws {
        let store = CatalogSnapshotStore(directory: directory)
        let entries = [entry(filename: "a.sh"), entry(filename: "b.sh")]
        try store.save(entries)
        XCTAssertEqual(store.load(), entries)
    }

    func testMissingSnapshotLoadsEmpty() {
        XCTAssertEqual(CatalogSnapshotStore(directory: directory).load(), [])
    }

    func testCorruptSnapshotLoadsEmpty() throws {
        let path = (directory as NSString).appendingPathComponent(CatalogSnapshotStore.snapshotName)
        try Data("not json{{{".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(CatalogSnapshotStore(directory: directory).load(), [])
    }

    func testSaveReplacesPriorSnapshot() throws {
        let store = CatalogSnapshotStore(directory: directory)
        try store.save([entry(filename: "a.sh"), entry(filename: "b.sh")])
        try store.save([entry(filename: "c.sh")])
        XCTAssertEqual(store.load().map(\.filename), ["c.sh"])
    }

    /// The snapshot lives beside the other dot-prefixed ledgers and must stay
    /// out of plugin discovery (discovery skips dotfiles).
    func testSnapshotFilenameIsDotPrefixed() {
        XCTAssertTrue(CatalogSnapshotStore.snapshotName.hasPrefix("."))
    }

    // MARK: - IM11: reconciling against currently-enabled stores

    /// A store being disabled/removed can legitimately bring the freshly
    /// loaded set down to zero entries — that's a real reconciliation, not a
    /// failure, and the snapshot must be allowed to shrink to match (else a
    /// removed store's entries linger forever and drive a phantom "update
    /// available").
    func testShouldSaveWhenEmptyAndNoFailure() {
        XCTAssertTrue(CatalogSnapshotStore.shouldSave(entries: [], hadFailure: false))
    }

    /// A successful, non-empty load always saves, failure or not.
    func testShouldSaveWhenEntriesPresentRegardlessOfFailure() {
        let e = [entry(filename: "a.sh")]
        XCTAssertTrue(CatalogSnapshotStore.shouldSave(entries: e, hadFailure: false))
        XCTAssertTrue(CatalogSnapshotStore.shouldSave(entries: e, hadFailure: true), "a partial success (some entries despite another store failing) should still save")
    }

    /// Nothing came back AND something failed: indistinguishable from a
    /// transient outage — must not stomp the last-known-good snapshot.
    func testShouldNotSaveWhenEmptyAndFailed() {
        XCTAssertFalse(CatalogSnapshotStore.shouldSave(entries: [], hadFailure: true))
    }
}
