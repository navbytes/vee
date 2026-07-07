import XCTest
@testable import VeeApp
import VeePluginFormat
import VeeSearch

@MainActor
final class MenuSearchViewModelTests: XCTestCase {
    private func row(_ text: String, path: [String] = []) -> FlatRow {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        return FlatRow(
            item: MenuItem(text: text, params: p),
            path: path,
            title: text.lowercased(),
            haystack: ([text] + path).joined(separator: " ").lowercased()
        )
    }

    func testIdleShowsAllRowsInOrder() {
        let vm = MenuSearchViewModel(rows: [row("Alpha"), row("Beta"), row("Gamma")])
        XCTAssertEqual(vm.results.map(\.item.text), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(vm.selection, 0)
    }

    func testQueryFiltersAndResetsSelectionToTop() {
        let vm = MenuSearchViewModel(rows: [row("Settings"), row("Reset"), row("About")])
        vm.selection = 2
        vm.query = "set"
        XCTAssertEqual(Set(vm.results.map(\.item.text)), ["Settings", "Reset"])
        XCTAssertEqual(vm.selection, 0, "selection resets to the best match on a new query")
    }

    func testMoveDownAndUpAreClamped() {
        let vm = MenuSearchViewModel(rows: [row("One"), row("Two"), row("Three")])
        vm.moveUp()                       // already at top → stays
        XCTAssertEqual(vm.selection, 0)
        vm.moveDown(); vm.moveDown(); vm.moveDown()  // clamp at last
        XCTAssertEqual(vm.selection, 2)
        vm.moveUp()
        XCTAssertEqual(vm.selection, 1)
    }

    func testSelectedRowTracksHighlight() {
        let vm = MenuSearchViewModel(rows: [row("One"), row("Two")])
        XCTAssertEqual(vm.selectedRow()?.item.text, "One")
        vm.moveDown()
        XCTAssertEqual(vm.selectedRow()?.item.text, "Two")
    }

    func testNoMatchYieldsNoSelectedRow() {
        let vm = MenuSearchViewModel(rows: [row("Alpha")])
        vm.query = "zzzz"
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNil(vm.selectedRow())
        vm.moveDown()                     // must not crash on empty results
        XCTAssertEqual(vm.selection, 0)
    }

    func testClearingQueryRestoresAllRows() {
        let vm = MenuSearchViewModel(rows: [row("Alpha"), row("Beta")])
        vm.query = "alpha"
        XCTAssertEqual(vm.results.count, 1)
        vm.query = ""
        XCTAssertEqual(vm.results.map(\.item.text), ["Alpha", "Beta"])
    }
}
