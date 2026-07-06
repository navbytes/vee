import XCTest
@testable import VeeWidgetShared

final class WidgetSnapshotStoreTests: XCTestCase {
    private func makeTempStore() -> (WidgetSnapshotStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-widget-tests-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(directory: dir), dir)
    }

    func testWriteThenReadRoundTrips() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = WidgetSnapshot(
            plugins: [
                PluginSnapshot(id: "cpu.5s.sh", name: "cpu", title: "42%", updated: Date(timeIntervalSince1970: 1_700_000_000)),
                PluginSnapshot(id: "net.1m.sh", name: "net", title: "↓ 1.2MB", updated: Date(timeIntervalSince1970: 1_700_000_050))
            ],
            generated: Date(timeIntervalSince1970: 1_700_000_100)
        )
        store.write(snapshot)

        let read = store.read()
        XCTAssertEqual(read, snapshot)
        XCTAssertEqual(read?.version, WidgetSnapshot.currentVersion)
    }

    func testReadReturnsNilWhenAbsent() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(store.read())
    }

    func testWriteCreatesDirectoryIfNeeded() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        store.write(WidgetSnapshot(plugins: [], generated: Date(timeIntervalSince1970: 1)))
        XCTAssertNotNil(store.read())
    }

    func testSupportDirectoryIsHomeRelative() {
        // Resolves the real home (…/Library/Application Support/Vee), not a
        // sandbox container path.
        let path = VeeWidgetSharing.supportDirectory().path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/Vee"), path)
    }

    func testEmptySnapshotHasNoPlugins() {
        XCTAssertTrue(WidgetSnapshot.empty().plugins.isEmpty)
    }
}
