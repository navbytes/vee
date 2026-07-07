import XCTest
@testable import VeeWidgetShared

/// Covers the v2 (enriched) `WidgetSnapshot`: the new per-plugin fields, their
/// round-trip, backward-compatible decoding of a v1 file, and the roll-up /
/// freshness helpers the health widget and view layer rely on.
final class WidgetSnapshotV2Tests: XCTestCase {
    private func iso8601Decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testCurrentVersionIsTwo() {
        XCTAssertEqual(WidgetSnapshot.currentVersion, 2)
    }

    func testEnrichedSnapshotRoundTripsThroughStore() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-widget-v2-\(UUID().uuidString)", isDirectory: true)
        let store = WidgetSnapshotStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = WidgetSnapshot(
            plugins: [
                PluginSnapshot(
                    id: "disk.10s.sh", name: "disk", title: "72%",
                    updated: Date(timeIntervalSince1970: 1_700_000_000),
                    color: .rgba(r: 10, g: 200, b: 30, a: 255),
                    symbolName: "internaldrive",
                    symbolColors: [.named("green")],
                    progress: 0.72,
                    sparkline: [1, 2, 3, 2.5, 4],
                    isError: false,
                    interval: 10
                ),
                PluginSnapshot(
                    id: "build.1m.sh", name: "build", title: "⚠︎ error",
                    updated: Date(timeIntervalSince1970: 1_700_000_050),
                    isError: true
                )
            ],
            generated: Date(timeIntervalSince1970: 1_700_000_100)
        )
        store.write(snapshot)
        XCTAssertEqual(store.read(), snapshot)
    }

    /// A snapshot written by the shipped v1 build (no enriched keys) must still
    /// decode — the widget shows plain titles rather than crashing.
    func testDecodesV1SnapshotWithoutEnrichedFields() throws {
        let v1JSON = """
        {
          "version": 1,
          "generated": "2023-11-14T22:15:00Z",
          "plugins": [
            { "id": "cpu.5s.sh", "name": "cpu", "title": "42%", "updated": "2023-11-14T22:13:20Z" }
          ]
        }
        """
        let snapshot = try iso8601Decoder().decode(WidgetSnapshot.self, from: Data(v1JSON.utf8))
        XCTAssertEqual(snapshot.version, 1)
        let cpu = try XCTUnwrap(snapshot.plugins.first)
        XCTAssertEqual(cpu.title, "42%")
        XCTAssertNil(cpu.color)
        XCTAssertNil(cpu.symbolName)
        XCTAssertNil(cpu.progress)
        XCTAssertNil(cpu.sparkline)
        XCTAssertNil(cpu.interval)
        XCTAssertFalse(cpu.failed)
    }

    func testFailedReflectsIsError() {
        let ok = PluginSnapshot(id: "a", name: "a", title: "ok", updated: Date(), isError: false)
        let bad = PluginSnapshot(id: "b", name: "b", title: "⚠︎", updated: Date(), isError: true)
        let unknown = PluginSnapshot(id: "c", name: "c", title: "?", updated: Date())
        XCTAssertFalse(ok.failed)
        XCTAssertTrue(bad.failed)
        XCTAssertFalse(unknown.failed) // absent isError is treated as healthy
    }

    func testRollupHelpers() {
        let snapshot = WidgetSnapshot(
            plugins: [
                PluginSnapshot(id: "a", name: "a", title: "ok", updated: Date(), isError: false),
                PluginSnapshot(id: "b", name: "b", title: "ok", updated: Date()),
                PluginSnapshot(id: "c", name: "c", title: "⚠︎", updated: Date(), isError: true)
            ],
            generated: Date()
        )
        XCTAssertEqual(snapshot.okCount, 2)
        XCTAssertEqual(snapshot.failingCount, 1)
        XCTAssertEqual(snapshot.failing.map(\.id), ["c"])
    }

    func testIsStaleUsesIntervalWithFloor() {
        let updated = Date(timeIntervalSince1970: 1_000_000)
        // 60s interval → threshold floors at 300s, so 200s old is fresh, 400s old is stale.
        let fast = PluginSnapshot(id: "a", name: "a", title: "x", updated: updated, interval: 60)
        XCTAssertFalse(fast.isStale(asOf: updated.addingTimeInterval(200)))
        XCTAssertTrue(fast.isStale(asOf: updated.addingTimeInterval(400)))
        // A long interval scales above the floor: 600s interval → 1200s threshold.
        let slow = PluginSnapshot(id: "b", name: "b", title: "x", updated: updated, interval: 600)
        XCTAssertFalse(slow.isStale(asOf: updated.addingTimeInterval(1000)))
        XCTAssertTrue(slow.isStale(asOf: updated.addingTimeInterval(1300)))
        // Unknown interval → never flagged stale (we can't know).
        let unknown = PluginSnapshot(id: "c", name: "c", title: "x", updated: updated)
        XCTAssertFalse(unknown.isStale(asOf: updated.addingTimeInterval(100_000)))
    }
}
