import XCTest
@testable import VeePluginFormat

/// Covers the structural addressing a detached window uses to re-find its row
/// after the plugin refreshes.
final class MenuItemPathTests: XCTestCase {
    private func item(_ text: String, _ submenu: [MenuNode] = []) -> MenuItem {
        MenuItem(text: text, submenu: submenu)
    }

    private func chartItem(_ text: String, _ values: [Double]) -> MenuItem {
        var p = LineParams()
        p.swiftbar.chart = ChartParams(kind: .pie, values: values)
        return MenuItem(text: text, params: p)
    }

    // MARK: - Finding

    func testFindsTopLevelAndNestedItems() {
        let tree: [MenuNode] = [
            .item(item("A")),
            .separator,
            .item(item("B", [.item(item("B1")), .item(item("B2"))]))
        ]
        XCTAssertEqual(MenuItemLocator.path(of: item("A"), in: tree), [0])
        XCTAssertEqual(MenuItemLocator.path(of: item("B1"), in: tree), [2, 0])
        XCTAssertEqual(MenuItemLocator.path(of: item("B2"), in: tree), [2, 1])
    }

    func testSeparatorsOccupyAnIndex() {
        // The path indexes the node array, so a separator shifts its siblings.
        // Resolving must agree with finding on that point or every row after a
        // separator would drift by one.
        let tree: [MenuNode] = [.separator, .item(item("A"))]
        let path = try? XCTUnwrap(MenuItemLocator.path(of: item("A"), in: tree))
        XCTAssertEqual(path, [1])
        XCTAssertEqual(MenuItemLocator.item(at: [1], in: tree)?.text, "A")
    }

    func testMissingItemHasNoPath() {
        XCTAssertNil(MenuItemLocator.path(of: item("nope"), in: [.item(item("A"))]))
    }

    func testDuplicateItemsResolveToTheFirst() {
        let tree: [MenuNode] = [.item(item("same")), .item(item("same"))]
        XCTAssertEqual(MenuItemLocator.path(of: item("same"), in: tree), [0])
    }

    // MARK: - Resolving

    func testRoundTripsThroughTheTree() {
        let tree: [MenuNode] = [
            .item(item("A")),
            .item(item("B", [.item(item("B1", [.item(item("B1a"))]))]))
        ]
        let path = MenuItemLocator.path(of: item("B1a"), in: tree)
        XCTAssertEqual(path, [1, 0, 0])
        XCTAssertEqual(MenuItemLocator.item(at: path ?? [], in: tree)?.text, "B1a")
    }

    /// The whole point: the row's text changes every refresh, and the path must
    /// still land on it.
    func testResolvesTheSameSlotAfterTheRowsTextAndDataChange() {
        let before: [MenuNode] = [.item(item("Header")), .item(chartItem("Disk 45%", [45, 30, 25]))]
        let after: [MenuNode] = [.item(item("Header")), .item(chartItem("Disk 60%", [60, 20, 20]))]

        let path = try? XCTUnwrap(MenuItemLocator.path(of: chartItem("Disk 45%", [45, 30, 25]), in: before))
        XCTAssertEqual(path, [1])
        let refreshed = MenuItemLocator.item(at: path ?? [], in: after)
        XCTAssertEqual(refreshed?.text, "Disk 60%")
        XCTAssertEqual(refreshed?.params.swiftbar.chart?.values, [60, 20, 20])
    }

    /// A shrunken or restructured menu must report "gone", not resolve to
    /// whatever now sits at that index.
    func testVanishedRowsResolveToNil() {
        XCTAssertNil(MenuItemLocator.item(at: [5], in: [.item(item("A"))]))
        XCTAssertNil(MenuItemLocator.item(at: [0, 0], in: [.item(item("A"))]))
        XCTAssertNil(MenuItemLocator.item(at: [0], in: [.separator]))
        XCTAssertNil(MenuItemLocator.item(at: [], in: [.item(item("A"))]))
    }

    func testDeepPathsAreBounded() {
        // A path longer than the walker's own depth cap is rejected rather than
        // walked, so a hostile/absurd path can't drive an unbounded descent.
        let path = MenuItemPath(repeating: 0, count: MenuItemLocator.maxDepth + 1)
        XCTAssertNil(MenuItemLocator.item(at: path, in: [.item(item("A"))]))
    }
}
