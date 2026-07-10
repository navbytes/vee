import XCTest
import VeeCatalog
@testable import VeeUI

/// A counting fake `CatalogFetching` — an actor so the call count is safe to
/// read from the test's (main) actor after `await`ing into the model.
private actor FakeCatalogFetcher: CatalogFetching {
    private(set) var fetchIndexCallCount = 0
    private(set) var fetchLastUpdatedCallCount = 0
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
    func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? {
        fetchLastUpdatedCallCount += 1
        return lastUpdated
    }
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

    /// A unique per-test directory, so tests that write the on-disk freshness
    /// ledger don't collide with each other or with parallel test runs.
    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "vee-browser-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Sort order

    func testVisibleEntriesDefaultSortIsNameCaseInsensitive() {
        let model = PluginBrowserModel(fetcher: FakeCatalogFetcher(), pluginsDirectory: tempDir(), onInstalled: {})
        model.entries = [makeEntry("banana"), makeEntry("Apple"), makeEntry("cherry")]

        XCTAssertEqual(model.sortOrder, .name, "default sort order")
        XCTAssertEqual(model.visibleEntries.map(\.filename), ["Apple.sh", "banana.sh", "cherry.sh"])
    }

    func testVisibleEntriesSortOrderUpdatedIsNewestFirst() {
        let model = PluginBrowserModel(fetcher: FakeCatalogFetcher(), pluginsDirectory: tempDir(), onInstalled: {})
        let old = makeEntry("old")
        let mid = makeEntry("mid")
        let new = makeEntry("new")
        model.entries = [old, mid, new]
        model.lastUpdated = [
            old.id: Date(timeIntervalSince1970: 100),
            mid.id: Date(timeIntervalSince1970: 200),
            new.id: Date(timeIntervalSince1970: 300)
        ]
        model.sortOrder = .updated

        XCTAssertEqual(model.visibleEntries.map(\.filename), ["new.sh", "mid.sh", "old.sh"])
    }

    func testVisibleEntriesSortOrderUpdatedPushesNilDatesToEndSortedByName() {
        let model = PluginBrowserModel(fetcher: FakeCatalogFetcher(), pluginsDirectory: tempDir(), onInstalled: {})
        let zebra = makeEntry("Zebra") // no date
        let apple = makeEntry("Apple") // no date
        let middle = makeEntry("Middle") // has a date
        model.entries = [zebra, apple, middle]
        model.lastUpdated = [middle.id: Date(timeIntervalSince1970: 500)]
        model.sortOrder = .updated

        XCTAssertEqual(model.visibleEntries.map(\.filename), ["Middle.sh", "Apple.sh", "Zebra.sh"],
                        "dated entries come first; undated entries fall back to name order among themselves")
    }

    // MARK: - Category filtering and sectioning

    func testVisibleEntriesFiltersToSelectedCategory() {
        let model = PluginBrowserModel(fetcher: FakeCatalogFetcher(), pluginsDirectory: tempDir(), onInstalled: {})
        let sys = makeEntry("sys")
        var net = makeEntry("net")
        net.category = "Network"
        model.entries = [sys, net]

        model.selectedCategory = "Network"

        XCTAssertEqual(model.visibleEntries.map(\.filename), ["net.sh"])
    }

    /// `sectionedEntries` groups by category (sorted by category name), and
    /// each section's entries respect the model's current sort order —
    /// verified with `.updated` so a bug that sorted sections but not their
    /// contents (or vice versa) would show up.
    func testSectionedEntriesGroupsByCategorySortedByNameWithSectionsInternallySorted() {
        let model = PluginBrowserModel(fetcher: FakeCatalogFetcher(), pluginsDirectory: tempDir(), onInstalled: {})
        var netOld = makeEntry("netOld"); netOld.category = "Network"
        var netNew = makeEntry("netNew"); netNew.category = "Network"
        var sys = makeEntry("sys"); sys.category = "System"
        model.entries = [netOld, sys, netNew]
        model.lastUpdated = [
            netOld.id: Date(timeIntervalSince1970: 100),
            netNew.id: Date(timeIntervalSince1970: 200)
        ]
        model.sortOrder = .updated

        let sections = model.sectionedEntries

        XCTAssertEqual(sections.map(\.category), ["Network", "System"], "sections sorted by category name")
        XCTAssertEqual(sections[0].entries.map(\.filename), ["netNew.sh", "netOld.sh"],
                        "within a section, entries follow the model's current sort order")
    }

    /// `sectionedEntries` is built from `visibleEntries`, so a category filter
    /// (which the view uses to decide flat-vs-sectioned) also scopes what
    /// would appear if sectioned — they can never disagree about membership.
    func testSectionedEntriesRespectsSelectedCategory() {
        let model = PluginBrowserModel(fetcher: FakeCatalogFetcher(), pluginsDirectory: tempDir(), onInstalled: {})
        let sys = makeEntry("sys")
        var net = makeEntry("net"); net.category = "Network"
        model.entries = [sys, net]
        model.selectedCategory = "Network"

        XCTAssertEqual(model.sectionedEntries.map(\.category), ["Network"])
    }

    // MARK: - Freshness cache wiring

    func testLoadLastUpdatedFetchesNetworkOnlyOncePerEntry() async throws {
        let entry = makeEntry("once")
        let fetcher = FakeCatalogFetcher(lastUpdated: Date(timeIntervalSince1970: 42))
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: tempDir(), onInstalled: {})

        await model.loadLastUpdated(for: entry)
        await model.loadLastUpdated(for: entry)

        let count = await fetcher.fetchLastUpdatedCallCount
        XCTAssertEqual(count, 1, "the in-memory guard should prevent a second network call for the same entry")
    }

    func testLoadLastUpdatedUsesOnDiskCacheAndSkipsNetwork() async throws {
        let dir = tempDir()
        let entry = makeEntry("cached")
        let cachedDate = Date(timeIntervalSince1970: 999)
        try CatalogFreshnessStore(directory: dir).record(entryID: entry.id, date: cachedDate)

        let fetcher = FakeCatalogFetcher(lastUpdated: Date(timeIntervalSince1970: 1))
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {})

        await model.loadLastUpdated(for: entry)

        let count = await fetcher.fetchLastUpdatedCallCount
        XCTAssertEqual(count, 0, "a cache hit must never fall through to the network")
        XCTAssertEqual(model.lastUpdatedDate(for: entry), cachedDate)
    }

    func testLoadLastUpdatedWritesNetworkFetchThroughToOnDiskStore() async throws {
        let dir = tempDir()
        let entry = makeEntry("writes-through")
        let fetchedDate = Date(timeIntervalSince1970: 123456)
        let fetcher = FakeCatalogFetcher(lastUpdated: fetchedDate)
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {})

        await model.loadLastUpdated(for: entry)

        let reread = CatalogFreshnessStore(directory: dir).date(for: entry.id)
        XCTAssertEqual(reread, fetchedDate, "a cache-miss network fetch should be persisted so a later store/launch reads it back")
    }

    // MARK: - ensureLastUpdatedLoaded

    func testEnsureLastUpdatedLoadedFetchesEachNeverSeenEntryOnce() async throws {
        let dir = tempDir()
        let a = makeEntry("a")
        let b = makeEntry("b")
        let cached = makeEntry("cached")
        try CatalogFreshnessStore(directory: dir).record(entryID: cached.id, date: Date(timeIntervalSince1970: 1))

        let fetcher = FakeCatalogFetcher(lastUpdated: Date(timeIntervalSince1970: 2))
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {})

        await model.ensureLastUpdatedLoaded(for: [a, b, cached])

        let count = await fetcher.fetchLastUpdatedCallCount
        XCTAssertEqual(count, 2, "one network call per never-before-seen entry; the pre-cached entry should be skipped")
        XCTAssertNotNil(model.lastUpdatedDate(for: a))
        XCTAssertNotNil(model.lastUpdatedDate(for: b))
        XCTAssertEqual(model.lastUpdatedDate(for: cached), Date(timeIntervalSince1970: 1))

        // A second pass over the same entries must not trigger any more calls.
        await model.ensureLastUpdatedLoaded(for: [a, b, cached])
        let secondCount = await fetcher.fetchLastUpdatedCallCount
        XCTAssertEqual(secondCount, 2, "already-fetched entries must not be re-fetched")
    }
}
