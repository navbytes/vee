import XCTest
@testable import VeeSearch
import VeePluginFormat

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

    // MARK: - Structure

    func testFlatListKeepsOrderAndActionOnly() {
        let rows = MenuFlattener.flatten([
            href("Open Issue 1"),
            plain("CPU: 42%"),          // non-actionable → excluded
            .separator,                 // separators skipped
            href("Open Issue 2")
        ])
        XCTAssertEqual(rows.map(\.item.text), ["Open Issue 1", "Open Issue 2"])
        XCTAssertTrue(rows.allSatisfy { $0.path.isEmpty })
    }

    func testNestedItemsCarryBreadcrumb() {
        let rows = MenuFlattener.flatten([
            plain("orders", submenu: [
                plain("Epics", submenu: [
                    href("#123 Fix retry")
                ]),
                href("Status")
            ])
        ])
        XCTAssertEqual(rows.count, 2)
        let fix = rows.first { $0.item.text == "#123 Fix retry" }
        XCTAssertEqual(fix?.path, ["orders", "Epics"])
        XCTAssertEqual(fix?.breadcrumb, "orders › Epics")
        let status = rows.first { $0.item.text == "Status" }
        XCTAssertEqual(status?.path, ["orders"])
    }

    /// Regression (spec bug #3): an item with BOTH an action and a submenu must
    /// surface its own action *and* recurse into children.
    func testClickableParentEmittedAndRecursed() {
        let rows = MenuFlattener.flatten([
            href("orders", "https://orders.dev", submenu: [
                href("Child")
            ])
        ])
        XCTAssertEqual(rows.count, 2)
        let parent = rows.first { $0.item.text == "orders" }
        XCTAssertEqual(parent?.path, [])                         // emitted at its own level
        XCTAssertNotNil(parent?.item.params.href)
        let child = rows.first { $0.item.text == "Child" }
        XCTAssertEqual(child?.path, ["orders"])               // breadcrumb still carries the group
    }

    func testDisabledAndDropdownFalseExcluded() {
        var disabled = LineParams(); disabled.href = URL(string: "https://x"); disabled.disabled = true
        var menuBarOnly = LineParams(); menuBarOnly.href = URL(string: "https://y"); menuBarOnly.dropdown = false
        let rows = MenuFlattener.flatten([
            .item(MenuItem(text: "Disabled", params: disabled)),
            .item(MenuItem(text: "MenuBarOnly", params: menuBarOnly)),
            href("Visible")
        ])
        XCTAssertEqual(rows.map(\.item.text), ["Visible"])
    }

    func testEmptyTextGroupContributesNoBreadcrumbSegment() {
        let rows = MenuFlattener.flatten([
            plain("", submenu: [ href("Leaf") ])               // group with no title
        ])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].path, [])                        // no dangling empty segment
    }

    func testEmptyTextLeafExcluded() {
        let rows = MenuFlattener.flatten([ href("   ") ])       // whitespace-only text
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Actionability mirrors the dispatcher

    func testActionabilityAcrossParamKinds() {
        func item(_ configure: (inout LineParams) -> Void) -> MenuItem {
            var p = LineParams(); configure(&p); return MenuItem(text: "x", params: p)
        }
        XCTAssertTrue(MenuFlattener.isActionable(item { $0.href = URL(string: "https://x") }))
        XCTAssertTrue(MenuFlattener.isActionable(item { $0.shell = ShellCommand(launchPath: "/bin/echo", arguments: [], openInTerminal: false) }))
        XCTAssertTrue(MenuFlattener.isActionable(item { $0.swiftbar.webview = URL(string: "https://x") }))
        XCTAssertTrue(MenuFlattener.isActionable(item { $0.sparkline = [1, 2, 3] }))
        XCTAssertTrue(MenuFlattener.isActionable(item { $0.control = .toggle(on: true) }))
        XCTAssertTrue(MenuFlattener.isActionable(item { $0.swiftbar.shortcut = "Run Thing" }))
        XCTAssertTrue(MenuFlattener.isActionable(item { $0.refresh = true }))

        // Not actionable on their own:
        XCTAssertFalse(MenuFlattener.isActionable(item { _ in }))                       // plain text
        XCTAssertFalse(MenuFlattener.isActionable(item { $0.progress = ProgressParams(fraction: 0.5) }))  // display-only gauge
        XCTAssertFalse(MenuFlattener.isActionable(item { $0.swiftbar.shortcut = "" }))  // empty shortcut
    }
}
