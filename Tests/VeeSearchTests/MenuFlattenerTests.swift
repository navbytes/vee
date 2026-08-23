import XCTest
@testable import VeeSearch
import VeePluginFormat

/// The flat, breadcrumb-annotated projection. Its only consumer now is
/// `vee search` — the app's menu surfaces render the tree directly — so what is
/// pinned here is the shape a terminal listing needs: activatable rows only, in
/// authored order, each carrying the path that says where it came from.
final class MenuFlattenerTests: XCTestCase {
    // MARK: - Builders

    private func href(_ text: String, _ url: String = "https://example.com", submenu: [MenuNode] = []) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: url)
        return .item(MenuItem(text: text, params: p, submenu: submenu))
    }

    private func plain(_ text: String, submenu: [MenuNode] = []) -> MenuNode {
        .item(MenuItem(text: text, params: LineParams(), submenu: submenu))
    }

    private func header(_ text: String, submenu: [MenuNode] = []) -> MenuNode {
        var p = LineParams()
        p.swiftbar.header = true
        return .item(MenuItem(text: text, params: p, submenu: submenu))
    }

    /// An item that WOULD be actionable (`href=`) if it weren't `disabled=true`.
    private func disabledAction(_ text: String) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        p.disabled = true
        return .item(MenuItem(text: text, params: p))
    }

    private func menuBarOnly(_ text: String, submenu: [MenuNode] = []) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        p.dropdown = false
        return .item(MenuItem(text: text, params: p, submenu: submenu))
    }

    private func row(_ text: String, in rows: [FlatRow]) -> FlatRow? {
        rows.first { $0.item.text == text }
    }

    // MARK: - Structure

    func testFlatListKeepsOrderAndActionOnly() {
        let rows = MenuFlattener.flatten([
            href("One"), plain("just text"), .separator, href("Two")
        ])
        XCTAssertEqual(rows.map(\.item.text), ["One", "Two"])
    }

    func testNestedItemsCarryBreadcrumb() {
        let rows = MenuFlattener.flatten([
            plain("Group", submenu: [href("Child")])
        ])
        XCTAssertEqual(rows.map(\.item.text), ["Child"])
        XCTAssertEqual(row("Child", in: rows)?.breadcrumb, "Group")
    }

    func testDeepNestingAccumulatesTheWholePath() {
        let rows = MenuFlattener.flatten([
            plain("A", submenu: [plain("B", submenu: [href("C")])])
        ])
        XCTAssertEqual(row("C", in: rows)?.breadcrumb, "A › B")
    }

    /// A row with both children and a command opens its children natively, so
    /// it must not be offered as an activatable row here either — while its
    /// children still descend.
    func testClickableParentIsNotARowButItsChildrenDescend() {
        let rows = MenuFlattener.flatten([
            href("Parent", submenu: [href("Child")])
        ])
        XCTAssertEqual(rows.map(\.item.text), ["Child"])
    }

    func testDisabledAndDropdownFalseExcluded() {
        let rows = MenuFlattener.flatten([
            disabledAction("Disabled"), menuBarOnly("Hidden"), href("Kept")
        ])
        XCTAssertEqual(rows.map(\.item.text), ["Kept"])
    }

    func testDropdownFalseStillDescends() {
        let rows = MenuFlattener.flatten([
            menuBarOnly("Hidden", submenu: [href("Buried")])
        ])
        XCTAssertEqual(rows.map(\.item.text), ["Buried"])
    }

    func testEmptyTextGroupContributesNoBreadcrumbSegment() {
        let rows = MenuFlattener.flatten([
            plain("  ", submenu: [href("Child")])
        ])
        XCTAssertEqual(row("Child", in: rows)?.breadcrumb, "")
    }

    func testEmptyTextLeafExcluded() {
        XCTAssertTrue(MenuFlattener.flatten([href("   ")]).isEmpty)
    }

    // MARK: - Alternates

    func testAlternateItemFlattenedAsSearchableActivatableRow() {
        var p = LineParams()
        p.refresh = true
        var main = MenuItem(text: "Refresh", params: p)
        main.alternate = MenuItem(text: "Force Refresh", params: p)
        let rows = MenuFlattener.flatten([.item(main)])
        XCTAssertEqual(rows.map(\.item.text), ["Refresh", "Force Refresh"])
    }

    func testAlternateWithSubmenuIsNotARowButItsChildrenDescend() {
        var p = LineParams()
        p.refresh = true
        var alt = MenuItem(text: "Force Refresh", params: p)
        alt.submenu = [href("Deep")]
        var main = MenuItem(text: "Refresh", params: p)
        main.alternate = alt
        let rows = MenuFlattener.flatten([.item(main)])
        XCTAssertEqual(rows.map(\.item.text), ["Refresh", "Deep"])
    }

    // MARK: - Headers

    /// A header's submenu is never part of the dropdown, so it is never walked.
    func testHeaderWithSubmenuNeverDescends() {
        let rows = MenuFlattener.flatten([
            header("Section", submenu: [href("Buried")])
        ])
        XCTAssertTrue(rows.isEmpty)
    }

    func testHeaderWithHrefNeverBecomesARow() {
        var p = LineParams()
        p.swiftbar.header = true
        p.href = URL(string: "https://example.com")
        let rows = MenuFlattener.flatten([.item(MenuItem(text: "Section", params: p))])
        XCTAssertTrue(rows.isEmpty)
    }

    /// A `header=true` item opens a section that adopts the siblings after it,
    /// so typing the section name surfaces its rows.
    func testSectionScopesFollowingSiblingsBreadcrumb() {
        let rows = MenuFlattener.flatten([
            header("Recent"), href("Fix retry"), href("Add tests")
        ])
        XCTAssertEqual(row("Fix retry", in: rows)?.breadcrumb, "Recent")
        XCTAssertEqual(row("Add tests", in: rows)?.breadcrumb, "Recent")
    }

    func testSectionEndsAtSeparatorAtSameLevel() {
        let rows = MenuFlattener.flatten([
            header("Recent"), href("In section"), .separator, href("After")
        ])
        XCTAssertEqual(row("In section", in: rows)?.breadcrumb, "Recent")
        XCTAssertEqual(row("After", in: rows)?.breadcrumb, "")
    }

    func testSectionEndsAtNextHeaderAtSameLevel() {
        let rows = MenuFlattener.flatten([
            header("First"), href("A"), header("Second"), href("B")
        ])
        XCTAssertEqual(row("A", in: rows)?.breadcrumb, "First")
        XCTAssertEqual(row("B", in: rows)?.breadcrumb, "Second")
    }

    func testNestedSubmenuSectionScopeIsIndependentOfParentLevel() {
        let rows = MenuFlattener.flatten([
            header("Top"),
            plain("Group", submenu: [header("Inner"), href("Deep")])
        ])
        XCTAssertEqual(row("Deep", in: rows)?.breadcrumb, "Top › Group › Inner")
    }

    func testSearchingTheSectionNameMatchesItsRows() {
        let rows = MenuFlattener.flatten([header("Recent"), href("Fix retry")])
        XCTAssertEqual(MenuSearch.search("recent", in: rows).map(\.item.text), ["Fix retry"])
    }

    // MARK: - Actionability

    func testActionabilityAcrossParamKinds() {
        func rowCount(_ configure: (inout LineParams) -> Void) -> Int {
            var p = LineParams()
            configure(&p)
            return MenuFlattener.flatten([.item(MenuItem(text: "row", params: p))]).count
        }
        XCTAssertEqual(rowCount { $0.href = URL(string: "https://example.com") }, 1)
        XCTAssertEqual(rowCount { $0.refresh = true }, 1)
        XCTAssertEqual(rowCount { $0.control = .toggle(on: true) }, 1)
        XCTAssertEqual(rowCount { $0.sparkline = [1, 2, 3] }, 1)
        XCTAssertEqual(rowCount { $0.progress = ProgressParams(fraction: 0.5) }, 0, "a gauge is display-only")
        XCTAssertEqual(rowCount { _ in }, 0)
    }
}
