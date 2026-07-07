import XCTest
import VeeCatalog
@testable import VeeUI

/// A counting fake `CatalogFetching` — an actor so the call count is safe to
/// read from the test's (main) actor after `await`ing into the model.
private actor FakeCatalogFetcher: CatalogFetching {
    private(set) var fetchIndexCallCount = 0
    var index: [CatalogEntry]
    var source: String
    var lastUpdated: Date?

    init(index: [CatalogEntry] = [], source: String = "", lastUpdated: Date? = nil) {
        self.index = index
        self.source = source
        self.lastUpdated = lastUpdated
    }

    func fetchIndex() async throws -> [CatalogEntry] {
        fetchIndexCallCount += 1
        return index
    }
    func fetchSource(_ entry: CatalogEntry) async throws -> String { source }
    func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? { lastUpdated }
}

/// Covers `PluginBrowserModel` fixes: the freshness-badge key mismatch (wave
/// 6c) and the Discover refresh affordance (wave 6i).
@MainActor
final class PluginBrowserModelTests: XCTestCase {
    private func makeEntry(_ name: String = "a") -> CatalogEntry {
        CatalogEntry(path: "System/\(name).sh", category: "System", filename: "\(name).sh", rawURL: URL(string: "https://example.com/\(name).sh")!)
    }

    /// Regression: `loadLastUpdated` writes under `entry.id` ("store#path"),
    /// but the freshness badge used to read `entry.path` — a different string
    /// for any non-empty store id — so the badge never rendered.
    func testLastUpdatedDateUsesEntryIDKeyMatchingLoadLastUpdated() async throws {
        let entry = makeEntry("b")
        XCTAssertNotEqual(entry.id, entry.path, "the regression only reproduces when these differ")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let fetcher = FakeCatalogFetcher(lastUpdated: date)
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: NSTemporaryDirectory(), onInstalled: {})

        await model.loadLastUpdated(for: entry)

        XCTAssertEqual(model.lastUpdatedDate(for: entry), date, "the badge's date lookup must key on entry.id, matching the write side")
        XCTAssertNotNil(model.freshness(for: entry))
    }

    /// A freshness lookup for an entry that was never fetched stays nil rather
    /// than crashing or misreporting.
    func testLastUpdatedDateNilWhenNeverFetched() {
        let entry = makeEntry("c")
        let model = PluginBrowserModel(fetcher: FakeCatalogFetcher(), pluginsDirectory: NSTemporaryDirectory(), onInstalled: {})
        XCTAssertNil(model.lastUpdatedDate(for: entry))
        XCTAssertNil(model.freshness(for: entry))
    }

    /// `refresh()` must re-fetch the catalog (not just reuse `entries`) and
    /// drop cached per-entry metadata so a card's header/trust re-fetches too.
    func testRefreshReinvokesFetchIndexAndClearsHeaders() async throws {
        let entry = makeEntry("d")
        let fetcher = FakeCatalogFetcher(index: [entry], source: "#!/bin/bash\necho hi\n")
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: NSTemporaryDirectory(), onInstalled: {})

        await model.load()
        var count = await fetcher.fetchIndexCallCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.entries.map(\.id), [entry.id])

        // Pre-seed a headers entry, as loadHeader would once the card appears.
        await model.loadHeader(for: entry)
        XCTAssertNotNil(model.headers[entry.id])

        await model.refresh()
        count = await fetcher.fetchIndexCallCount
        XCTAssertEqual(count, 2, "refresh() should re-invoke fetchIndex, not just reuse the cached entries")
        XCTAssertNil(model.headers[entry.id], "refresh() should clear cached headers so loadHeader refetches")
    }
}
