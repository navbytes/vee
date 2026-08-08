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

    private func action(_ text: String, path: [String] = []) -> SearchEntry { .action(row(text, path: path)) }
    private func info(_ text: String, path: [String] = []) -> SearchEntry { .info(row(text, path: path)) }

    /// Renders an entry as its display text, for order/content assertions
    /// that don't care which case it is (`SearchEntry` has no `.item` of its
    /// own the way `FlatRow` does).
    private func texts(_ entries: [SearchEntry]) -> [String] {
        entries.compactMap {
            switch $0 {
            case .action(let r), .info(let r): return r.item.text
            case .header(let title): return title
            case .separator: return nil
            }
        }
    }

    // MARK: - Idle / filtering (existing behavior, now over SearchEntry)

    func testIdleShowsAllRowsInOrder() {
        let vm = MenuSearchViewModel(entries: [action("Alpha"), action("Beta"), action("Gamma")])
        XCTAssertEqual(texts(vm.results), ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(vm.selection, 0)
    }

    func testQueryFiltersAndResetsSelectionToTop() {
        let vm = MenuSearchViewModel(entries: [action("Settings"), action("Reset"), action("About")])
        vm.selection = 2
        vm.query = "set"
        XCTAssertEqual(Set(texts(vm.results)), ["Settings", "Reset"])
        XCTAssertEqual(vm.selection, 0, "selection resets to the best match on a new query")
    }

    func testMoveDownAndUpAreClamped() {
        let vm = MenuSearchViewModel(entries: [action("One"), action("Two"), action("Three")])
        vm.moveUp()                       // already at top → stays
        XCTAssertEqual(vm.selection, 0)
        vm.moveDown(); vm.moveDown(); vm.moveDown()  // clamp at last
        XCTAssertEqual(vm.selection, 2)
        vm.moveUp()
        XCTAssertEqual(vm.selection, 1)
    }

    func testSelectedRowTracksHighlight() {
        let vm = MenuSearchViewModel(entries: [action("One"), action("Two")])
        XCTAssertEqual(vm.selectedRow()?.item.text, "One")
        vm.moveDown()
        XCTAssertEqual(vm.selectedRow()?.item.text, "Two")
    }

    func testNoMatchYieldsNoSelectedRow() {
        let vm = MenuSearchViewModel(entries: [action("Alpha")])
        vm.query = "zzzz"
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertNil(vm.selectedRow())
        vm.moveDown()                     // must not crash on empty results
        XCTAssertEqual(vm.selection, -1, "no .action entries at all ⇒ the -1 sentinel, not a clamped 0")
    }

    func testClearingQueryRestoresAllRows() {
        let vm = MenuSearchViewModel(entries: [action("Alpha"), action("Beta")])
        vm.query = "alpha"
        XCTAssertEqual(vm.results.count, 1)
        vm.query = ""
        XCTAssertEqual(texts(vm.results), ["Alpha", "Beta"])
    }

    // MARK: - Structured entries: selection/navigation skip non-action rows

    func testInitialSelectionSkipsLeadingHeaderAndInfoRows() {
        let vm = MenuSearchViewModel(entries: [.header("Section"), info("CPU: 42%"), action("Alpha"), action("Beta")])
        XCTAssertEqual(vm.selection, 2)
        XCTAssertEqual(vm.selectedRow()?.item.text, "Alpha")
    }

    func testMoveDownSkipsSeparatorHeaderAndInfoRows() {
        let vm = MenuSearchViewModel(entries: [
            action("Alpha"), .separator, .header("Section"), info("Sub-text"), action("Beta")
        ])
        XCTAssertEqual(vm.selection, 0)
        vm.moveDown()
        XCTAssertEqual(vm.selection, 4, "must skip the separator, header, and info row to land on the next action")
        XCTAssertEqual(vm.selectedRow()?.item.text, "Beta")
        vm.moveDown()                     // already the last action → clamp, no wrap
        XCTAssertEqual(vm.selection, 4)
    }

    func testMoveUpSkipsSeparatorHeaderAndInfoRows() {
        let vm = MenuSearchViewModel(entries: [
            action("Alpha"), .separator, .header("Section"), info("Sub-text"), action("Beta")
        ])
        vm.selection = 4
        vm.moveUp()
        XCTAssertEqual(vm.selection, 0, "must skip the info row, header, and separator to land back on the first action")
        vm.moveUp()                       // already the first action → clamp, no wrap
        XCTAssertEqual(vm.selection, 0)
    }

    func testSelectedRowNilWhenNoActionRowsExist() {
        let vm = MenuSearchViewModel(entries: [.header("Section"), info("Sub-text"), .separator])
        XCTAssertEqual(vm.selection, -1)
        XCTAssertNil(vm.selectedRow())
    }

    func testClearingQueryAfterTypingRestoresStructureAndSelection() {
        let entries: [SearchEntry] = [.header("Section"), action("Alpha"), .separator, action("Beta")]
        let vm = MenuSearchViewModel(entries: entries)
        vm.query = "beta"
        XCTAssertEqual(texts(vm.results), ["Beta"])
        vm.query = ""
        XCTAssertEqual(vm.results, entries, "idle passthrough restores the full structured list")
        XCTAssertEqual(vm.selection, 1, "selection lands back on the first action row, after the header")
        XCTAssertEqual(vm.selectedRow()?.item.text, "Alpha")
    }
}
