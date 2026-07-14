import XCTest
@testable import VeeSearch
import VeePluginFormat

/// `FlatRow.prefixed(with:)` — the small derivation the cross-plugin search
/// aggregator (`AppController`) uses to breadcrumb-prefix every plugin's rows
/// with its display name before merging them into one panel.
final class FlatRowTests: XCTestCase {
    private func row(_ text: String, path: [String] = []) -> FlatRow {
        FlatRow(
            item: MenuItem(text: text),
            path: path,
            title: SearchText.fold(text),
            haystack: SearchText.fold(([text] + path).joined(separator: " "))
        )
    }

    func testPrependsPluginNameAsTheOutermostPathSegment() {
        let prefixed = row("Fix retry", path: ["orders"]).prefixed(with: "GitHub")
        XCTAssertEqual(prefixed.path, ["GitHub", "orders"])
        XCTAssertEqual(prefixed.breadcrumb, "GitHub › orders")
    }

    func testWithNoPriorPathYieldsJustThePluginName() {
        let prefixed = row("Refresh").prefixed(with: "Weather")
        XCTAssertEqual(prefixed.path, ["Weather"])
        XCTAssertEqual(prefixed.breadcrumb, "Weather")
    }

    func testLeavesItemAndTitleUnchanged() {
        let original = row("Fix retry", path: ["orders"])
        let prefixed = original.prefixed(with: "GitHub")
        XCTAssertEqual(prefixed.item, original.item)
        XCTAssertEqual(prefixed.title, original.title)
    }

    /// The requirement this exists for: the plugin name must itself be
    /// fuzzy-searchable, not just displayed.
    func testFoldsThePluginNameIntoHaystackSoItsSearchable() {
        let prefixed = row("Fix retry").prefixed(with: "GitHub")
        XCTAssertTrue(prefixed.haystack.contains(SearchText.fold("GitHub")))

        let results = MenuSearch.search("github", in: [prefixed])
        XCTAssertEqual(results.map(\.item.text), ["Fix retry"], "typing the plugin name must surface its rows")
    }
}
