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

/// A `CatalogFetching` that always fails its index fetch — simulates one
/// broken store in a multi-store `load()`.
private struct ThrowingFetcher: CatalogFetching {
    struct Boom: Error {}
    func fetchIndex() async throws -> [CatalogEntry] { throw Boom() }
    func fetchSource(_ entry: CatalogEntry) async throws -> String { throw Boom() }
    func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? { throw Boom() }
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

    // MARK: - Catalog-update nudge wiring (`onUpdatesFound`)

    /// `load()` must report an installed, catalog-tracked plugin whose
    /// manifest-pinned hash has moved on from what's recorded at install —
    /// the seam `AppController` wires to `Notifier.notifyCatalogUpdates`.
    func testLoadReportsCandidateForInstalledPluginWithNewerCatalogHash() async throws {
        let dir = tempDir()
        var entry = makeEntry("cpu")
        entry.declaredSHA256 = "new-hash"
        try ProvenanceStore(directory: dir).record(
            PluginProvenance(filename: entry.filename, sourceURL: entry.rawURL, sha256: "old-hash", installedAt: Date(timeIntervalSince1970: 0))
        )
        let fetcher = FakeCatalogFetcher(index: [entry])
        var reported: [PluginUpdateCandidate]?
        var reportedInstalled: Set<String>?
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {}, onUpdatesFound: { candidates, installed in
            reported = candidates
            reportedInstalled = installed
        })

        await model.load()

        XCTAssertEqual(reported?.map(\.filename), [entry.filename])
        XCTAssertEqual(reportedInstalled, [entry.filename], "the installed set rides along so the app can prune its notified-versions ledger")
    }

    /// A successful `load()` persists the fetched index as the on-disk
    /// snapshot the app's launch-time update scan reads — written only here,
    /// on a user-initiated Discover load, never by a launch fetch.
    func testLoadWritesCatalogSnapshotForLaunchScan() async throws {
        let dir = tempDir()
        let entry = makeEntry("cpu")
        let fetcher = FakeCatalogFetcher(index: [entry])
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {}, onUpdatesFound: { _, _ in })

        await model.load()

        XCTAssertEqual(CatalogSnapshotStore(directory: dir).load().map(\.filename), [entry.filename])
    }

    /// An installed plugin whose recorded hash still matches the catalog must
    /// never produce a candidate. The callback still fires (with an empty
    /// list) so the app can prune its ledger on every scan.
    func testLoadReportsNoCandidateWhenInstalledHashMatchesCatalog() async throws {
        let dir = tempDir()
        var entry = makeEntry("cpu")
        entry.declaredSHA256 = "same-hash"
        try ProvenanceStore(directory: dir).record(
            PluginProvenance(filename: entry.filename, sourceURL: entry.rawURL, sha256: "same-hash", installedAt: Date(timeIntervalSince1970: 0))
        )
        let fetcher = FakeCatalogFetcher(index: [entry])
        var reported: [PluginUpdateCandidate]?
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {}, onUpdatesFound: { candidates, _ in reported = candidates })

        await model.load()

        XCTAssertEqual(reported, [], "an up-to-date installed plugin must never produce a candidate (the empty prune-only call is expected)")
    }

    /// A plugin that merely shares a filename with a catalog entry, but was
    /// never installed *through* Discover (no provenance record), must never
    /// be nudged — `pendingUpdates` only scans `ProvenanceStore`'s ledger, and
    /// this must not be bypassed.
    func testLoadDoesNotReportForAPluginWithNoProvenanceRecord() async throws {
        let dir = tempDir()
        var entry = makeEntry("cpu")
        entry.declaredSHA256 = "new-hash"
        let fetcher = FakeCatalogFetcher(index: [entry])
        var reportCount = 0
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {}, onUpdatesFound: { _, _ in reportCount += 1 })

        await model.load()

        XCTAssertEqual(reportCount, 0, "no provenance record means never installed via the catalog — must never be nudged (nothing installed, so not even a prune call)")
    }

    /// `refresh()` calls through to `load()`, so the same report fires for a
    /// manual refresh as for the view's automatic cold-open `load()` — one
    /// report per fetch, with zero extra wiring needed at either call site.
    func testRefreshAlsoReportsPendingUpdates() async throws {
        let dir = tempDir()
        var entry = makeEntry("cpu")
        entry.declaredSHA256 = "new-hash"
        try ProvenanceStore(directory: dir).record(
            PluginProvenance(filename: entry.filename, sourceURL: entry.rawURL, sha256: "old-hash", installedAt: Date(timeIntervalSince1970: 0))
        )
        let fetcher = FakeCatalogFetcher(index: [entry], source: "#!/bin/bash\necho hi\n")
        var reportCount = 0
        let model = PluginBrowserModel(fetcher: fetcher, pluginsDirectory: dir, onInstalled: {}, onUpdatesFound: { candidates, _ in
            if !candidates.isEmpty { reportCount += 1 }
        })

        await model.load()
        XCTAssertEqual(reportCount, 1, "the initial load already reports the pending update once")

        await model.refresh()
        XCTAssertEqual(reportCount, 2, "refresh() re-runs load(), so a still-pending update reports again — de-duping repeat reports is Notifier's job, not this model's")
    }

    // MARK: - IM4: multi-store provenance disambiguation

    /// Two stores list the same filename; installing store X's copy must
    /// never let store Y's card claim it as Verified/Installed — that would
    /// misattribute X's install to Y and hide that clicking Y's button would
    /// overwrite it.
    func testProvenanceStatusDoesNotAttributeAnotherStoresInstallAsVerified() async throws {
        let dir = tempDir()
        let storeX = StoreConfig(id: StoreID("x"), displayName: "Store X", kind: .github)
        let storeY = StoreConfig(id: StoreID("y"), displayName: "Store Y", kind: .github)
        let sourceX = "#!/bin/bash\necho from-x\n"
        let entryX = CatalogEntry(storeID: storeX.id, path: "Git/git.5s.sh", category: "Git", filename: "git.5s.sh", rawURL: URL(string: "https://x.example.com/git.5s.sh")!)
        let entryY = CatalogEntry(storeID: storeY.id, path: "Git/git.5s.sh", category: "Git", filename: "git.5s.sh", rawURL: URL(string: "https://y.example.com/git.5s.sh")!)
        let fetcherX = FakeCatalogFetcher(index: [entryX], source: sourceX)
        let fetcherY = FakeCatalogFetcher(index: [entryY], source: "#!/bin/bash\necho from-y\n")
        let model = PluginBrowserModel(
            stores: [storeX, storeY],
            makeClient: { $0.id == storeX.id ? fetcherX : fetcherY },
            pluginsDirectory: dir,
            onInstalled: {}
        )
        await model.load()
        XCTAssertEqual(Set(model.entries.map(\.id)), [entryX.id, entryY.id], "sanity: both stores' same-named entries loaded side by side")

        // Install store X's copy.
        await model.requestInstall(entryX)
        model.confirmInstall()

        XCTAssertEqual(model.provenanceStatus(for: entryX), .verified, "sanity: X's own card is verified")
        XCTAssertEqual(model.provenanceStatus(for: entryY), .installedFromAnotherSource, "store Y's same-named entry must not borrow store X's verified badge")
        XCTAssertTrue(model.isInstalled(entryY), "a file named git.5s.sh does genuinely exist on disk (from X) — isInstalled's disk-presence check is still accurate")
    }

    // MARK: - IM11: snapshot reconciles against currently-enabled stores

    /// A store's entries linger in the on-disk snapshot only as long as it
    /// keeps being asked; once it's no longer configured, the next
    /// successful load must reconcile it away — otherwise a removed store's
    /// plugin drives a phantom "update available" forever.
    func testRemovingAStoreReconcilesTheSnapshotSoItsEntriesDoNotLinger() async throws {
        let dir = tempDir()
        let storeA = StoreConfig(id: StoreID("a"), displayName: "Store A", kind: .github)
        let storeB = StoreConfig(id: StoreID("b"), displayName: "Store B", kind: .github)
        let entryA = CatalogEntry(storeID: storeA.id, path: "System/a.sh", category: "System", filename: "a.sh", rawURL: URL(string: "https://a.example.com/a.sh")!)
        let entryB = CatalogEntry(storeID: storeB.id, path: "System/b.sh", category: "System", filename: "b.sh", rawURL: URL(string: "https://b.example.com/b.sh")!)

        let both = PluginBrowserModel(
            stores: [storeA, storeB],
            makeClient: { $0.id == storeA.id ? FakeCatalogFetcher(index: [entryA]) : FakeCatalogFetcher(index: [entryB]) },
            pluginsDirectory: dir,
            onInstalled: {}
        )
        await both.load()
        XCTAssertEqual(Set(CatalogSnapshotStore(directory: dir).load().map(\.filename)), ["a.sh", "b.sh"], "sanity: both stores' entries snapshotted")

        // Store B removed from the registry entirely — a fresh model (as
        // `AppController.browserModel()` builds whenever the configured store
        // set changes) only ever sees A.
        let onlyA = PluginBrowserModel(
            stores: [storeA],
            makeClient: { _ in FakeCatalogFetcher(index: [entryA]) },
            pluginsDirectory: dir,
            onInstalled: {}
        )
        await onlyA.load()

        XCTAssertEqual(CatalogSnapshotStore(directory: dir).load().map(\.filename), ["a.sh"], "store B's entries must not linger in the snapshot once it's no longer configured")
    }

    // MARK: - IM9: per-store failure surfacing

    /// A broken enabled store must not go silently invisible just because
    /// another store's fetch still succeeds.
    func testLoadSurfacesAPerStoreFailureNoticeWhenAnotherStoreStillLoads() async throws {
        let dir = tempDir()
        let storeA = StoreConfig(id: StoreID("a"), displayName: "Store A", kind: .github)
        let storeBroken = StoreConfig(id: StoreID("broken"), displayName: "Broken Store", kind: .github)
        let entryA = CatalogEntry(storeID: storeA.id, path: "System/a.sh", category: "System", filename: "a.sh", rawURL: URL(string: "https://a.example.com/a.sh")!)

        let model = PluginBrowserModel(
            stores: [storeA, storeBroken],
            makeClient: { store -> CatalogFetching in store.id == storeA.id ? FakeCatalogFetcher(index: [entryA]) : ThrowingFetcher() },
            pluginsDirectory: dir,
            onInstalled: {}
        )

        await model.load()

        XCTAssertEqual(model.entries.map(\.filename), ["a.sh"], "the healthy store's entries must still load")
        XCTAssertNil(model.errorMessage, "a partial failure must not blank the whole grid with the full-screen error — that's reserved for a total failure")
        XCTAssertNotNil(model.notice, "the broken store's failure must be surfaced (a banner), not silently invisible")
        XCTAssertEqual(model.notice?.kind, .failure)
    }

    /// The inverse of the above: when every store fails, the existing
    /// full-screen error still wins — this fix must not regress that.
    func testLoadShowsFullScreenErrorWhenEveryStoreFails() async throws {
        let dir = tempDir()
        let storeBroken = StoreConfig(id: StoreID("broken"), displayName: "Broken Store", kind: .github)
        let model = PluginBrowserModel(
            stores: [storeBroken],
            makeClient: { _ in ThrowingFetcher() },
            pluginsDirectory: dir,
            onInstalled: {}
        )

        await model.load()

        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertNotNil(model.errorMessage, "nothing loaded at all — the full-screen error must still show")
    }

    // MARK: - Store changes refresh the live Discover tab (no relaunch)

    /// `reload(stores:)` is what a Settings-tab store change drives (via
    /// `AppController.handleStoresChanged`) — a newly-enabled store's entries
    /// must show up without the model being torn down and rebuilt.
    func testReloadStoresPicksUpANewlyAddedStore() async throws {
        let dir = tempDir()
        let storeA = StoreConfig(id: StoreID("a"), displayName: "Store A", kind: .github)
        let storeB = StoreConfig(id: StoreID("b"), displayName: "Store B", kind: .github)
        let entryA = CatalogEntry(storeID: storeA.id, path: "System/a.sh", category: "System", filename: "a.sh", rawURL: URL(string: "https://a.example.com/a.sh")!)
        let entryB = CatalogEntry(storeID: storeB.id, path: "System/b.sh", category: "System", filename: "b.sh", rawURL: URL(string: "https://b.example.com/b.sh")!)

        let model = PluginBrowserModel(
            stores: [storeA],
            makeClient: { $0.id == storeA.id ? FakeCatalogFetcher(index: [entryA]) : FakeCatalogFetcher(index: [entryB]) },
            pluginsDirectory: dir,
            onInstalled: {}
        )
        await model.load()
        XCTAssertEqual(model.entries.map(\.filename), ["a.sh"])

        await model.reload(stores: [storeA, storeB])

        XCTAssertEqual(model.entries.map(\.filename), ["a.sh", "b.sh"], "the newly-added store's entries must appear without rebuilding the model")
        XCTAssertTrue(model.hasMultipleStores)
    }

    /// The inverse: a store removed/disabled in Settings must drop its
    /// entries from the SAME live model, not just a freshly-built one.
    func testReloadStoresDropsARemovedStoresEntries() async throws {
        let dir = tempDir()
        let storeA = StoreConfig(id: StoreID("a"), displayName: "Store A", kind: .github)
        let storeB = StoreConfig(id: StoreID("b"), displayName: "Store B", kind: .github)
        let entryA = CatalogEntry(storeID: storeA.id, path: "System/a.sh", category: "System", filename: "a.sh", rawURL: URL(string: "https://a.example.com/a.sh")!)
        let entryB = CatalogEntry(storeID: storeB.id, path: "System/b.sh", category: "System", filename: "b.sh", rawURL: URL(string: "https://b.example.com/b.sh")!)

        let model = PluginBrowserModel(
            stores: [storeA, storeB],
            makeClient: { $0.id == storeA.id ? FakeCatalogFetcher(index: [entryA]) : FakeCatalogFetcher(index: [entryB]) },
            pluginsDirectory: dir,
            onInstalled: {}
        )
        await model.load()
        XCTAssertEqual(Set(model.entries.map(\.filename)), ["a.sh", "b.sh"])

        await model.reload(stores: [storeA])

        XCTAssertEqual(model.entries.map(\.filename), ["a.sh"], "the removed store's entries must not linger")
        XCTAssertFalse(model.hasMultipleStores)
    }
}
