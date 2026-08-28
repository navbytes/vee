import XCTest
import VeeCatalog
import VeePluginFormat
@testable import VeeUI

/// Discover's search and sort must not depend on how much of the grid has been
/// looked at. Card metadata (title/summary) is fetched lazily when a card
/// scrolls into view, so anything derived from it changes under the user:
/// search returned more results the second time a query was typed, and
/// sort-by-name reordered the grid as each header landed — moving cards out
/// from under the cursor mid-click.
@MainActor
final class CatalogSearchStabilityTests: XCTestCase {
    private func entry(_ filename: String, category: String = "Tools", manifestTitle: String? = nil) -> CatalogEntry {
        CatalogEntry(
            path: "\(category)/\(filename)",
            category: category,
            filename: filename,
            rawURL: URL(string: "https://example.com/\(filename)")!,
            manifestTitle: manifestTitle
        )
    }

    private func model(_ entries: [CatalogEntry]) -> PluginBrowserModel {
        let model = PluginBrowserModel(
            fetcher: StubFetcher(),
            pluginsDirectory: NSTemporaryDirectory(),
            onInstalled: {}
        )
        model.entries = entries
        return model
    }

    private struct StubFetcher: CatalogFetching {
        func fetchIndex() async throws -> [CatalogEntry] { [] }
        func fetchSource(_ entry: CatalogEntry) async throws -> String { "" }
        func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? { nil }
    }

    func testSearchResultsDoNotChangeWhenHeadersArrive() {
        let m = model([entry("weather.10s.sh"), entry("clock.1m.sh")])
        m.search = "weather"
        let before = m.visibleEntries.map(\.filename)

        // A card scrolls into view and its header lands, giving it a title that
        // has nothing to do with the query.
        m.headers["Tools/clock.1m.sh"] = HeaderMetadata()
        m.headers["Tools/weather.10s.sh"] = HeaderMetadata()

        XCTAssertEqual(m.visibleEntries.map(\.filename), before,
                       "the same query must return the same plugins regardless of what has loaded")
    }

    func testSortOrderDoesNotChangeWhenHeadersArrive() {
        let m = model([entry("zebra.10s.sh"), entry("alpha.10s.sh"), entry("middle.10s.sh")])
        let before = m.visibleEntries.map(\.filename)
        XCTAssertEqual(before, ["alpha.10s.sh", "middle.10s.sh", "zebra.10s.sh"])

        for e in m.entries { m.headers[e.id] = HeaderMetadata() }
        XCTAssertEqual(m.visibleEntries.map(\.filename), before,
                       "cards must not slide around as headers land")
    }

    func testManifestTitleIsStillSearchableAndSortable() {
        let m = model([entry("aaa.10s.sh", manifestTitle: "Zebra"), entry("zzz.10s.sh", manifestTitle: "Alpha")])
        m.search = "zebra"
        XCTAssertEqual(m.visibleEntries.map(\.filename), ["aaa.10s.sh"],
                       "a manifest title is known up front, so it stays searchable")

        m.search = ""
        XCTAssertEqual(m.visibleEntries.map(\.filename), ["zzz.10s.sh", "aaa.10s.sh"],
                       "and sortable — Alpha before Zebra")
    }
    /// `loadHeader` marks an entry in-flight BEFORE fetching so two concurrent
    /// card `.task`s don't fetch it twice — but it used to leave that marker in
    /// place when the fetch failed, and its own `headers[id] == nil` gate then
    /// returned early forever. One network blip and that card stayed blank until
    /// the app was relaunched.
    func testAFailedHeaderFetchCanBeRetried() async {
        let failing = FailingFetcher()
        let m = PluginBrowserModel(fetcher: failing, pluginsDirectory: NSTemporaryDirectory(), onInstalled: {})
        let e = entry("weather.10s.sh")
        m.entries = [e]

        await m.loadHeader(for: e)
        XCTAssertNil(m.headers[e.id], "a failed fetch must not leave a marker behind")

        failing.shouldFail = false
        await m.loadHeader(for: e)
        XCTAssertNotNil(m.headers[e.id], "the retry must actually run rather than return early")
    }

    private final class FailingFetcher: CatalogFetching, @unchecked Sendable {
        var shouldFail = true
        struct Boom: Error {}
        func fetchIndex() async throws -> [CatalogEntry] { [] }
        func fetchSource(_ entry: CatalogEntry) async throws -> String {
            if shouldFail { throw Boom() }
            return "#!/bin/bash\n# <xbar.title>Weather</xbar.title>\necho hi\n"
        }
        func fetchLastUpdated(_ entry: CatalogEntry) async throws -> Date? { nil }
    }

}
