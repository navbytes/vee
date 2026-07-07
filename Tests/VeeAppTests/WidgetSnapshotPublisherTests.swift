import XCTest
import Foundation
import VeeWidgetShared
@testable import VeeApp

/// Covers `WidgetSnapshotPublisher` (wave 2): the coalesced-write / metered-reload
/// policy extracted from `AppController`. Uses injected counting closures and
/// tiny, generous intervals rather than the production defaults so the suite
/// stays fast; assertions poll with a deadline (or sleep several multiples of
/// the relevant interval) instead of asserting exact timing.
@MainActor
final class WidgetSnapshotPublisherTests: XCTestCase {
    private func makePublish(title: String) -> WidgetPublish {
        WidgetPublish(title: title)
    }

    /// Sleeps for `multiple`x the given interval — generous slack for scheduling
    /// jitter, never asserting exact timing.
    private func settle(_ interval: TimeInterval, multiple: Double = 4) async throws {
        try await Task.sleep(nanoseconds: UInt64(interval * multiple * 1_000_000_000))
    }

    func testOnePublishWritesAndReloadsOnceAfterCoalesce() async throws {
        let coalesce: TimeInterval = 0.05
        var writes: [WidgetSnapshot] = []
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(
            write: { writes.append($0) },
            requestReload: { reloads += 1 },
            flushCoalesce: coalesce,
            reloadFloor: 0.6,
            timestampFloor: 0.5
        )
        publisher.setLoaded(ids: ["a"])
        writes.removeAll() // drop the empty seed write from setLoaded's own flush

        publisher.publish(id: "a", name: "A", interval: nil, publish: makePublish(title: "hi"))
        try await settle(coalesce)

        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.plugins.first?.title, "hi")
        XCTAssertEqual(reloads, 1)
    }

    func testIdenticalRepublishSkipsWriteAndReloadBeforeFloors() async throws {
        let coalesce: TimeInterval = 0.05
        var writeCount = 0
        var reloads = 0
        // Floors far wider than this test's total runtime — deliberately. The
        // test only asserts what must NOT happen before a floor elapses and
        // never waits one out, so wide floors add no runtime; a floor near the
        // test's own elapsed time (two settles plus XCTest overhead on a
        // loaded CI runner) could legitimately pass mid-test and turn a
        // correct timestamp-floor write into a spurious failure.
        let publisher = WidgetSnapshotPublisher(
            write: { _ in writeCount += 1 },
            requestReload: { reloads += 1 },
            flushCoalesce: coalesce,
            reloadFloor: 5.0,
            timestampFloor: 5.0
        )
        publisher.setLoaded(ids: ["a"])
        writeCount = 0 // drop the empty seed write from setLoaded's own flush

        publisher.publish(id: "a", name: "A", interval: nil, publish: makePublish(title: "same"))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(reloads, 1)

        // Re-publishing identical content well inside the timestamp/reload floors
        // must neither rewrite the file nor spend a second reload.
        publisher.publish(id: "a", name: "A", interval: nil, publish: makePublish(title: "same"))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 1, "identical content before the timestamp floor must not rewrite")
        XCTAssertEqual(reloads, 1, "identical content must not spend a second reload")
    }

    func testChangedTitleWritesImmediatelyAndReloadsAgainEventually() async throws {
        let coalesce: TimeInterval = 0.05
        var writeCount = 0
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(
            write: { _ in writeCount += 1 },
            requestReload: { reloads += 1 },
            flushCoalesce: coalesce,
            reloadFloor: 0.6,
            timestampFloor: 0.5
        )
        publisher.setLoaded(ids: ["a"])
        writeCount = 0 // drop the empty seed write from setLoaded's own flush

        publisher.publish(id: "a", name: "A", interval: nil, publish: makePublish(title: "first"))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(reloads, 1)

        // A changed title writes immediately once coalesced, even though the
        // reload floor hasn't elapsed yet — the reload itself is throttled
        // (trailing), not the write.
        publisher.publish(id: "a", name: "A", interval: nil, publish: makePublish(title: "second"))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 2, "changed content must write immediately once coalesced")

        // The trailing reload fires once the reload floor elapses; poll with a
        // deadline rather than sleeping the full floor.
        let deadline = Date().addingTimeInterval(3.0)
        while reloads < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(reloads, 2, "a trailing reload should eventually fire so the change lands")
    }

    func testSetLoadedWithoutIDOmitsItFromNextFlush() async throws {
        let coalesce: TimeInterval = 0.05
        var writes: [WidgetSnapshot] = []
        let publisher = WidgetSnapshotPublisher(
            write: { writes.append($0) },
            requestReload: {},
            flushCoalesce: coalesce,
            reloadFloor: 0.6,
            timestampFloor: 0.5
        )
        publisher.setLoaded(ids: ["a", "b"])

        publisher.publish(id: "a", name: "A", interval: nil, publish: makePublish(title: "hi"))
        publisher.publish(id: "b", name: "B", interval: nil, publish: makePublish(title: "yo"))
        try await settle(coalesce)
        XCTAssertEqual(Set(writes.last?.plugins.map(\.id) ?? []), ["a", "b"], "both loaded plugins should appear first")

        // Dropping "b" from the loaded set must prune it from the very next
        // flush — setLoaded flushes synchronously, no sleep needed.
        publisher.setLoaded(ids: ["a"])
        XCTAssertEqual(writes.last?.plugins.map(\.id), ["a"], "unloaded plugin must be omitted from the next flush")
    }

    // MARK: - Wave D: card threading

    func testPublishedCardAppearsInWrittenSnapshot() async throws {
        let coalesce: TimeInterval = 0.05
        var writes: [WidgetSnapshot] = []
        let publisher = WidgetSnapshotPublisher(
            write: { writes.append($0) },
            requestReload: {},
            flushCoalesce: coalesce,
            reloadFloor: 0.6,
            timestampFloor: 0.5
        )
        publisher.setLoaded(ids: ["a"])
        writes.removeAll()

        let card = WidgetCard(template: .gauge, title: "Disk", value: "72%", progress: 0.72)
        publisher.publish(id: "a", name: "A", interval: nil, publish: WidgetPublish(title: "72%", card: card))
        try await settle(coalesce)

        XCTAssertEqual(writes.last?.plugins.first?.card, card)
    }

    func testChangedCardWritesAndReloadsAgain() async throws {
        let coalesce: TimeInterval = 0.05
        var writeCount = 0
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(
            write: { _ in writeCount += 1 },
            requestReload: { reloads += 1 },
            flushCoalesce: coalesce,
            reloadFloor: 0.6,
            timestampFloor: 0.5
        )
        publisher.setLoaded(ids: ["a"])
        writeCount = 0

        publisher.publish(id: "a", name: "A", interval: nil, publish: WidgetPublish(title: "72%", card: WidgetCard(value: "72%", progress: 0.72)))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(reloads, 1)

        // Same title, but a changed card (different progress) must still count
        // as a content change: write immediately, spend a (throttled) reload.
        publisher.publish(id: "a", name: "A", interval: nil, publish: WidgetPublish(title: "72%", card: WidgetCard(value: "72%", progress: 0.9)))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 2, "a changed card must write immediately once coalesced")

        let deadline = Date().addingTimeInterval(3.0)
        while reloads < 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(reloads, 2, "a changed card should eventually spend a trailing reload")
    }

    func testIdenticalCardRepublishSkipsWriteAndReloadBeforeFloors() async throws {
        let coalesce: TimeInterval = 0.05
        var writeCount = 0
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(
            write: { _ in writeCount += 1 },
            requestReload: { reloads += 1 },
            flushCoalesce: coalesce,
            reloadFloor: 5.0,
            timestampFloor: 5.0
        )
        publisher.setLoaded(ids: ["a"])
        writeCount = 0

        let card = WidgetCard(value: "72%", progress: 0.72)
        publisher.publish(id: "a", name: "A", interval: nil, publish: WidgetPublish(title: "72%", card: card))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(reloads, 1)

        // Re-publishing an identical card must neither rewrite nor reload.
        publisher.publish(id: "a", name: "A", interval: nil, publish: WidgetPublish(title: "72%", card: card))
        try await settle(coalesce)
        XCTAssertEqual(writeCount, 1, "identical card before the timestamp floor must not rewrite")
        XCTAssertEqual(reloads, 1, "identical card must not spend a second reload")
    }

    /// A card's presentation (tint/symbol/progress/trend) is projected onto the
    /// snapshot's scraped fields, so a `.both`/`.widget` plugin still renders in
    /// the multi-plugin roundup path (which reads color/symbolName/progress/
    /// sparkline, not the card) instead of looking bare.
    func testCardPresentationPopulatesScrapedFields() async throws {
        let coalesce: TimeInterval = 0.05
        var writes: [WidgetSnapshot] = []
        let publisher = WidgetSnapshotPublisher(
            write: { writes.append($0) },
            requestReload: {},
            flushCoalesce: coalesce,
            reloadFloor: 0.6,
            timestampFloor: 0.5
        )
        publisher.setLoaded(ids: ["a"])
        writes.removeAll()

        let card = WidgetCard(
            template: .trend,
            symbol: "chart.line.uptrend.xyaxis",
            tint: .named("green"),
            value: "$18.2k",
            progress: 0.72,
            trend: [1, 2, 3, 5, 8]
        )
        // The scraped `fields` are empty here — the values must come from the card.
        publisher.publish(id: "a", name: "A", interval: nil, publish: WidgetPublish(title: "$18.2k", card: card))
        try await settle(coalesce)

        let snapshot = try XCTUnwrap(writes.last?.plugins.first)
        XCTAssertEqual(snapshot.color, .named("green"))
        XCTAssertEqual(snapshot.symbolName, "chart.line.uptrend.xyaxis")
        XCTAssertEqual(snapshot.progress, 0.72)
        XCTAssertEqual(snapshot.sparkline, [1, 2, 3, 5, 8])
    }
}
