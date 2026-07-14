import XCTest
@testable import VeeCatalog

final class CatalogUpdateCheckTests: XCTestCase {
    private let url = URL(string: "https://example.com/x.sh")!

    /// Matching is by origin (`sourceURL == rawURL`), so fixtures derive the
    /// URL from the filename: each plugin's install origin lines up with its
    /// own catalog entry, and only the origin-forgery test diverges on purpose.
    private func originURL(_ filename: String) -> URL {
        URL(string: "https://example.com/\(filename)")!
    }

    private func entry(filename: String = "x.sh", rawURL: URL? = nil, declaredSHA256: String? = nil) -> CatalogEntry {
        CatalogEntry(path: "System/\(filename)", category: "System", filename: filename, rawURL: rawURL ?? originURL(filename), declaredSHA256: declaredSHA256)
    }

    private func provenance(filename: String = "x.sh", sourceURL: URL? = nil, sha256: String = "abc", installedAt: Date = Date(timeIntervalSince1970: 1_000)) -> PluginProvenance {
        PluginProvenance(filename: filename, sourceURL: sourceURL ?? originURL(filename), sha256: sha256, installedAt: installedAt)
    }

    // MARK: - status: date-based (no manifest-pinned hash)

    func testNewerCatalogDateIsUpdateAvailable() {
        let installed = provenance(installedAt: Date(timeIntervalSince1970: 1_000))
        let status = CatalogUpdateCheck.status(installed: installed, entry: entry(), catalogLastUpdated: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(status, .updateAvailable)
    }

    func testSameCatalogDateIsUpToDate() {
        let installed = provenance(installedAt: Date(timeIntervalSince1970: 1_000))
        let status = CatalogUpdateCheck.status(installed: installed, entry: entry(), catalogLastUpdated: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(status, .upToDate)
    }

    func testOlderCatalogDateIsUpToDate() {
        let installed = provenance(installedAt: Date(timeIntervalSince1970: 2_000))
        let status = CatalogUpdateCheck.status(installed: installed, entry: entry(), catalogLastUpdated: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(status, .upToDate, "the catalog predating the install must never read as an update")
    }

    func testUnknownCatalogDateIsUpToDate() {
        let installed = provenance()
        XCTAssertEqual(CatalogUpdateCheck.status(installed: installed, entry: entry(), catalogLastUpdated: nil), .upToDate,
                        "no signal must never be guessed into an update")
    }

    func testNotInCatalogWhenNoMatchingEntry() {
        let installed = provenance()
        XCTAssertEqual(CatalogUpdateCheck.status(installed: installed, entry: nil, catalogLastUpdated: Date()), .notInCatalog)
    }

    /// Cross-feature regression: `ProvenanceStatus` (pre-existing local-edit
    /// detection) and `CatalogUpdateCheck` (this wave) both read from
    /// `PluginProvenance`, but must never conflate their signals. A local edit
    /// after install correctly flips `ProvenanceStatus` to `.modified` — but
    /// `installed.sha256` is the value frozen at install time, never
    /// recomputed from the live file, so the same edit must not leak into a
    /// false "update available": the catalog's own copy hasn't changed.
    func testLocalEditDoesNotProduceFalseUpdateAvailable() {
        let installedSource = "#!/bin/bash\necho original\n"
        let record = PluginProvenance(filename: "x.sh", sourceURL: url, source: installedSource, installedAt: Date(timeIntervalSince1970: 1_000))

        let editedSource = "#!/bin/bash\necho edited-locally\n"
        XCTAssertEqual(ProvenanceStatus.evaluate(record: record, currentSource: editedSource), .modified, "sanity: the local edit is detected")

        let catalogEntry = entry(declaredSHA256: PluginHash.sha256Hex(installedSource))
        XCTAssertEqual(
            CatalogUpdateCheck.status(installed: record, entry: catalogEntry, catalogLastUpdated: nil),
            .upToDate,
            "a local edit must never surface as a catalog update — the catalog's copy hasn't changed"
        )
    }

    // MARK: - status: hash-based (manifest-pinned store, no fetch needed)

    func testDifferingDeclaredHashIsUpdateAvailable() {
        let installed = provenance(sha256: "old-hash")
        let status = CatalogUpdateCheck.status(installed: installed, entry: entry(declaredSHA256: "new-hash"), catalogLastUpdated: nil)
        XCTAssertEqual(status, .updateAvailable)
    }

    func testMatchingDeclaredHashIsUpToDate() {
        let installed = provenance(sha256: "same-hash")
        let status = CatalogUpdateCheck.status(installed: installed, entry: entry(declaredSHA256: "same-hash"), catalogLastUpdated: nil)
        XCTAssertEqual(status, .upToDate)
    }

    func testDeclaredHashTakesPrecedenceOverDate() {
        // Even if the date alone would say "older" (no update), a differing
        // pinned hash is authoritative.
        let installed = provenance(sha256: "old-hash", installedAt: Date(timeIntervalSince1970: 5_000))
        let status = CatalogUpdateCheck.status(
            installed: installed,
            entry: entry(declaredSHA256: "new-hash"),
            catalogLastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(status, .updateAvailable)
    }

    // MARK: - versionToken

    func testVersionTokenPrefersDeclaredHash() {
        XCTAssertEqual(CatalogUpdateCheck.versionToken(entry: entry(declaredSHA256: "h"), catalogLastUpdated: Date()), "h")
    }

    func testVersionTokenFallsBackToISODate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(CatalogUpdateCheck.versionToken(entry: entry(), catalogLastUpdated: date), ISO8601DateFormatter().string(from: date))
    }

    func testVersionTokenNilWhenNoSignal() {
        XCTAssertNil(CatalogUpdateCheck.versionToken(entry: entry(), catalogLastUpdated: nil))
    }

    // MARK: - pendingUpdates (batch scan / "collect plugins with updates available")

    func testPendingUpdatesCollectsOnlyThoseWithAnUpdate() {
        let installed = [
            provenance(filename: "newer.sh", installedAt: Date(timeIntervalSince1970: 1_000)),
            provenance(filename: "same.sh", installedAt: Date(timeIntervalSince1970: 1_000)),
            provenance(filename: "gone.sh", installedAt: Date(timeIntervalSince1970: 1_000))
        ]
        let catalog = [
            entry(filename: "newer.sh"),
            entry(filename: "same.sh")
            // "gone.sh" intentionally absent — removed upstream.
        ]
        let dates: [String: Date] = [
            "newer.sh": Date(timeIntervalSince1970: 2_000),
            "same.sh": Date(timeIntervalSince1970: 1_000)
        ]

        let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: catalog) { dates[$0.filename] }

        XCTAssertEqual(candidates.map(\.filename), ["newer.sh"])
    }

    func testPendingUpdatesSortedByFilenameForStableCoalescing() {
        let installed = [
            provenance(filename: "z.sh", installedAt: Date(timeIntervalSince1970: 1_000)),
            provenance(filename: "a.sh", installedAt: Date(timeIntervalSince1970: 1_000))
        ]
        let catalog = [entry(filename: "z.sh"), entry(filename: "a.sh")]
        let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: catalog) { _ in Date(timeIntervalSince1970: 2_000) }

        XCTAssertEqual(candidates.map(\.filename), ["a.sh", "z.sh"])
    }

    func testPendingUpdatesEmptyWhenNothingChanged() {
        let installed = [provenance(filename: "a.sh", installedAt: Date(timeIntervalSince1970: 2_000))]
        let catalog = [entry(filename: "a.sh")]
        let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: catalog) { _ in Date(timeIntervalSince1970: 1_000) }
        XCTAssertEqual(candidates, [])
    }

    func testPendingUpdatesCarriesVersionToken() {
        let installed = [provenance(filename: "a.sh", sha256: "old", installedAt: Date(timeIntervalSince1970: 1_000))]
        let catalog = [entry(filename: "a.sh", declaredSHA256: "new")]
        let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: catalog) { _ in nil }
        XCTAssertEqual(candidates, [PluginUpdateCandidate(filename: "a.sh", versionToken: "new")])
    }

    /// Security regression (V-security D1): with several stores configured, a
    /// hostile store publishing an entry with the SAME FILENAME as a plugin
    /// installed from a different store must not be able to forge an "update
    /// available" nudge — matching is by origin URL, not filename.
    func testPendingUpdatesIgnoresSameFilenameFromDifferentOrigin() {
        let installed = [provenance(filename: "x.sh", sourceURL: URL(string: "https://trusted.example/x.sh")!, sha256: "installed-hash")]
        let hostile = entry(
            filename: "x.sh",
            rawURL: URL(string: "https://hostile.example/x.sh")!,
            declaredSHA256: "attacker-controlled-differing-hash"
        )
        let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: [hostile]) { _ in Date(timeIntervalSince1970: 99_000) }
        XCTAssertEqual(candidates, [], "a same-named entry from a different origin must never match")
    }

    /// The conservative flip side of origin matching: a store that MOVES a
    /// plugin to a new path (new rawURL) stops matching — no update nudge, and
    /// crucially no false positive. A missing signal is never guessed.
    func testPendingUpdatesSilentWhenStoreMovedThePlugin() {
        let installed = [provenance(filename: "x.sh", sourceURL: URL(string: "https://store.example/old-path/x.sh")!, sha256: "old")]
        let moved = entry(filename: "x.sh", rawURL: URL(string: "https://store.example/new-path/x.sh")!, declaredSHA256: "new")
        let candidates = CatalogUpdateCheck.pendingUpdates(installed: installed, catalog: [moved]) { _ in nil }
        XCTAssertEqual(candidates, [])
    }
}
