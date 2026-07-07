import XCTest
@testable import VeeWidgetShared

/// Covers v3: `PluginSnapshot.card`, the version bump, and the roll-up/
/// staleness helpers accounting for a card when present. v1/v2 files (no
/// `card` key) must still decode — see `testDecodesV2SnapshotWithoutCard`.
final class WidgetSnapshotV3Tests: XCTestCase {
    private func iso8601Decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func iso8601Encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    func testCurrentVersionIsThree() {
        XCTAssertEqual(WidgetSnapshot.currentVersion, 3)
    }

    func testSnapshotWithCardRoundTripsThroughStore() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vee-widget-v3-\(UUID().uuidString)", isDirectory: true)
        let store = WidgetSnapshotStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let card = WidgetCard(
            template: .gauge,
            title: "Disk",
            symbol: "internaldrive",
            tint: .named("green"),
            value: "72%",
            status: .ok,
            progress: 0.72
        )
        let snapshot = WidgetSnapshot(
            plugins: [
                PluginSnapshot(
                    id: "disk.10s.sh", name: "disk", title: "72%",
                    updated: Date(timeIntervalSince1970: 1_700_000_000),
                    card: card
                )
            ],
            generated: Date(timeIntervalSince1970: 1_700_000_100)
        )
        store.write(snapshot)
        let read = store.read()
        XCTAssertEqual(read, snapshot)
        XCTAssertEqual(read?.version, 3)
        XCTAssertEqual(read?.plugins.first?.card, card)
    }

    func testEncodeDecodeRoundTripPreservesCard() throws {
        let card = WidgetCard(template: .list, title: "Orders", items: [
            WidgetCardItem(label: "Orders", value: "214", symbol: "bag", tint: .named("blue"))
        ])
        let snapshot = WidgetSnapshot(
            plugins: [PluginSnapshot(id: "a", name: "a", title: "x", updated: Date(timeIntervalSince1970: 1_700_000_000), card: card)],
            generated: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try iso8601Encoder().encode(snapshot)
        let decoded = try iso8601Decoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    /// A snapshot written by the v2 build (no `card` key) must still decode
    /// with `card == nil`, exactly like v1's missing enriched fields.
    func testDecodesV2SnapshotWithoutCard() throws {
        let v2JSON = """
        {
          "version": 2,
          "generated": "2023-11-14T22:15:00Z",
          "plugins": [
            {
              "id": "disk.10s.sh", "name": "disk", "title": "72%",
              "updated": "2023-11-14T22:13:20Z",
              "color": "green", "progress": 0.72, "isError": false, "interval": 10
            }
          ]
        }
        """
        let snapshot = try iso8601Decoder().decode(WidgetSnapshot.self, from: Data(v2JSON.utf8))
        XCTAssertEqual(snapshot.version, 2)
        let disk = try XCTUnwrap(snapshot.plugins.first)
        XCTAssertNil(disk.card)
        XCTAssertEqual(disk.progress, 0.72)
        XCTAssertFalse(disk.failed)
    }

    /// A v1 snapshot (no enriched fields, no `card`) still decodes too.
    func testDecodesV1SnapshotWithoutCard() throws {
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
        let cpu = try XCTUnwrap(snapshot.plugins.first)
        XCTAssertNil(cpu.card)
        XCTAssertFalse(cpu.failed)
    }

    func testFailedReflectsCardStatusError() {
        let ok = PluginSnapshot(id: "a", name: "a", title: "x", updated: Date(), card: WidgetCard(status: .ok))
        let warning = PluginSnapshot(id: "b", name: "b", title: "x", updated: Date(), card: WidgetCard(status: .warning))
        let error = PluginSnapshot(id: "c", name: "c", title: "x", updated: Date(), card: WidgetCard(status: .error))
        XCTAssertFalse(ok.failed)
        XCTAssertFalse(warning.failed)
        XCTAssertTrue(error.failed)
    }

    /// `isError == true` still marks a plugin failed even with a healthy (or
    /// absent) card — either signal failing is enough.
    func testFailedIsTrueWhenEitherIsErrorOrCardStatusIsError() {
        let isErrorOnly = PluginSnapshot(id: "a", name: "a", title: "x", updated: Date(), isError: true, card: WidgetCard(status: .ok))
        let cardOnly = PluginSnapshot(id: "b", name: "b", title: "x", updated: Date(), isError: false, card: WidgetCard(status: .error))
        let neither = PluginSnapshot(id: "c", name: "c", title: "x", updated: Date(), isError: false, card: WidgetCard(status: .ok))
        XCTAssertTrue(isErrorOnly.failed)
        XCTAssertTrue(cardOnly.failed)
        XCTAssertFalse(neither.failed)
    }

    func testIsStalePrefersCardStaleAfterOverInterval() {
        let updated = Date(timeIntervalSince1970: 1_000_000)
        // interval alone would floor the threshold at 300s; staleAfter: 60
        // overrides that down to 60s.
        let snapshot = PluginSnapshot(
            id: "a", name: "a", title: "x", updated: updated, interval: 600,
            card: WidgetCard(staleAfter: 60)
        )
        XCTAssertFalse(snapshot.isStale(asOf: updated.addingTimeInterval(30)))
        XCTAssertTrue(snapshot.isStale(asOf: updated.addingTimeInterval(90)))
    }

    func testIsStaleFallsBackToIntervalWhenCardHasNoStaleAfter() {
        let updated = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = PluginSnapshot(
            id: "a", name: "a", title: "x", updated: updated, interval: 60,
            card: WidgetCard(title: "x")
        )
        XCTAssertFalse(snapshot.isStale(asOf: updated.addingTimeInterval(200)))
        XCTAssertTrue(snapshot.isStale(asOf: updated.addingTimeInterval(400)))
    }
}
