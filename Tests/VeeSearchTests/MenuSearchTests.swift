import XCTest
@testable import VeeSearch
import VeePluginFormat

final class MenuSearchTests: XCTestCase {
    // MARK: - Builders

    private func row(_ text: String, path: [String] = []) -> FlatRow {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        let item = MenuItem(text: text, params: p)
        return FlatRow(
            item: item,
            path: path,
            title: SearchText.fold(text),
            haystack: SearchText.fold(([text] + path).joined(separator: " "))
        )
    }

    private func rows(_ texts: String...) -> [FlatRow] { texts.map { row($0) } }

    private func actionEntry(_ text: String, path: [String] = []) -> SearchEntry { .action(row(text, path: path)) }
    private func infoEntry(_ text: String, path: [String] = []) -> SearchEntry { .info(row(text, path: path)) }

    // MARK: - Idle

    func testEmptyQueryReturnsAllInOriginalOrder() {
        let all = rows("Alpha", "Beta", "Gamma")
        XCTAssertEqual(MenuSearch.search("", in: all), all)
    }

    func testWhitespaceQueryIsIdle() {
        let all = rows("Alpha", "Beta")
        XCTAssertEqual(MenuSearch.search("   \t ", in: all), all)
    }

    // MARK: - Filtering

    func testNoMatchYieldsEmpty() {
        XCTAssertTrue(MenuSearch.search("zzzz", in: rows("Alpha", "Beta")).isEmpty)
    }

    func testSubstringFilter() {
        let result = MenuSearch.search("set", in: rows("Settings", "Reset", "About"))
        XCTAssertEqual(Set(result.map(\.item.text)), ["Settings", "Reset"])
    }

    func testFuzzySubsequenceMatch() {
        // "gh" is not a substring of "GitHub" but is a subsequence.
        let result = MenuSearch.search("gh", in: rows("GitHub", "Weather"))
        XCTAssertEqual(result.map(\.item.text), ["GitHub"])
    }

    func testMultiTokenAND() {
        let result = MenuSearch.search("open pr", in: rows("Open PR #12", "Open Issue", "Close PR"))
        XCTAssertEqual(result.map(\.item.text), ["Open PR #12"])
    }

    // MARK: - Ranking

    func testPrefixContiguousOutranksScattered() {
        // "set": "Settings" (prefix, contiguous) should beat "Sweet Escape Tool"
        // (scattered s…e…t).
        let result = MenuSearch.search("set", in: rows("Sweet Escape Tool", "Settings"))
        XCTAssertEqual(result.first?.item.text, "Settings")
    }

    func testTitleMatchOutranksBreadcrumbOnlyMatch() {
        let direct = row("orders dashboard")           // matches in the title
        let contextual = row("Fix retry", path: ["orders"])  // matches only via breadcrumb
        let result = MenuSearch.search("orders", in: [contextual, direct])
        XCTAssertEqual(result.map(\.item.text), ["orders dashboard", "Fix retry"])
    }

    func testBreadcrumbTokenSurfacesChildren() {
        let child = row("#123 Fix retry", path: ["orders", "Epics"])
        let result = MenuSearch.search("epics", in: [child, row("Unrelated")])
        XCTAssertEqual(result.map(\.item.text), ["#123 Fix retry"])
    }

    /// Regression: a short token must not scatter-match across breadcrumb words
    /// as a loose subsequence. Only a *contiguous* ancestor substring (or a title
    /// fuzzy match) counts — so `npm` finds the script, not `main`, whose folded
    /// breadcrumb merely happens to contain n…p…m as a scattered subsequence.
    func testBreadcrumbMatchRequiresContiguousSubstring() {
        let scattered = row("main", path: ["Repositories", "orders", "Branches"])
        let real = row("npm run dev", path: ["Scripts"])
        let result = MenuSearch.search("npm", in: [scattered, real])
        XCTAssertEqual(result.map(\.item.text), ["npm run dev"])
    }

    func testStableTieBreakByOriginalOrder() {
        // Identical text ⇒ identical score ⇒ original order preserved.
        let all = [row("Deploy A"), row("Deploy B"), row("Deploy C")]
        let result = MenuSearch.search("deploy", in: all)
        XCTAssertEqual(result.map(\.item.text), ["Deploy A", "Deploy B", "Deploy C"])
    }

    // MARK: - Normalization

    func testCaseAndDiacriticInsensitive() {
        let result = MenuSearch.search("cafe", in: rows("Café Menu", "Tea"))
        XCTAssertEqual(result.map(\.item.text), ["Café Menu"])
    }

    func testQueryCaseFolded() {
        let result = MenuSearch.search("GH", in: rows("GitHub"))
        XCTAssertEqual(result.map(\.item.text), ["GitHub"])
    }

    // MARK: - Scores

    func testScoredExposesPositiveScoresForMatches() {
        let scored = MenuSearch.scored("set", in: rows("Settings"))
        XCTAssertEqual(scored.count, 1)
        XCTAssertGreaterThan(scored[0].score, 0)
    }

    // MARK: - search(_:in: [SearchEntry])

    func testEntriesIdleQueryReturnsEverythingUnchangedIncludingHeadersAndSeparators() {
        let entries: [SearchEntry] = [.header("Recent"), actionEntry("Alpha"), .separator, infoEntry("CPU: 42%")]
        XCTAssertEqual(MenuSearch.search("", in: entries), entries)
    }

    func testEntriesTypedQueryDropsHeadersAndSeparatorsEvenWhenTheHeaderTextWouldMatch() {
        let entries: [SearchEntry] = [.header("Alpha Section"), actionEntry("Alpha"), .separator, actionEntry("Beta")]
        XCTAssertEqual(MenuSearch.search("alpha", in: entries), [actionEntry("Alpha")])
    }

    func testEntriesInfoRowsAreMatchableAlongsideActionRows() {
        let entries: [SearchEntry] = [infoEntry("Settings Panel"), actionEntry("Reset Settings")]
        let result = MenuSearch.search("settings", in: entries)
        XCTAssertEqual(result.count, 2, "an .info row is just as matchable as an .action row")
        XCTAssertTrue(result.contains(infoEntry("Settings Panel")))
        XCTAssertTrue(result.contains(actionEntry("Reset Settings")))
    }

    /// Mirrors `testPrefixContiguousOutranksScattered` but with an `.info` row
    /// on the winning side — proving `.info` goes through the identical
    /// per-row scoring as `.action`, not a separate, weaker path.
    func testEntriesInfoRowRankedByTheSameScoringAsAction() {
        let result = MenuSearch.search("set", in: [actionEntry("Sweet Escape Tool"), infoEntry("Settings")])
        XCTAssertEqual(result.first, infoEntry("Settings"))
    }
}
