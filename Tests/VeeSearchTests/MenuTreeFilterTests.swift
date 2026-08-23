import XCTest
@testable import VeeSearch
import VeePluginFormat

/// Filtering a menu without flattening it, and projecting the result into the
/// lines a surface draws. Pure, so none of this needs a view.
final class MenuTreeFilterTests: XCTestCase {
    private func href(_ text: String, submenu: [MenuNode] = []) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        return .item(MenuItem(text: text, params: p, submenu: submenu))
    }

    private func group(_ text: String, _ children: MenuNode...) -> MenuNode {
        .item(MenuItem(text: text, params: LineParams(), submenu: children))
    }

    private func header(_ text: String) -> MenuNode {
        var p = LineParams()
        p.swiftbar.header = true
        return .item(MenuItem(text: text, params: p))
    }

    private func tree(_ nodes: [MenuNode]) -> [MenuTreeNode] { MenuTree.build(nodes) }

    /// Every row in the filtered tree, depth-first, regardless of expansion.
    private func allTitles(_ nodes: [MenuTreeNode]) -> [String] {
        nodes.flatMap { node -> [String] in
            guard case .row(let row) = node else { return [] }
            return [row.item.text] + allTitles(row.children)
        }
    }

    // MARK: - Idle

    func testAnEmptyQueryReturnsTheTreeUntouched() {
        let nodes = tree([header("S"), href("Alpha"), .separator, group("G", href("Child"))])
        XCTAssertEqual(MenuTreeFilter.filter(nodes, query: ""), nodes)
    }

    func testAWhitespaceQueryIsIdle() {
        let nodes = tree([href("Alpha")])
        XCTAssertEqual(MenuTreeFilter.filter(nodes, query: "  \t "), nodes)
    }

    // MARK: - Pruning

    func testAMatchKeepsItsAncestorChain() {
        let filtered = MenuTreeFilter.filter(
            tree([href("Alpha"), group("Disks", group("Volumes", href("Macintosh HD")))]),
            query: "macintosh"
        )
        XCTAssertEqual(allTitles(filtered), ["Disks", "Volumes", "Macintosh HD"])
    }

    func testANonMatchingSiblingIsDropped() {
        let filtered = MenuTreeFilter.filter(
            tree([group("Disks", href("Macintosh HD"), href("Backup"))]),
            query: "macintosh"
        )
        XCTAssertEqual(allTitles(filtered), ["Disks", "Macintosh HD"])
    }

    /// Naming a group is how a user asks for what is inside it, so the group's
    /// children come along unfiltered rather than being narrowed by a query
    /// that was about the group.
    func testAMatchingGroupKeepsItsWholeSubtree() {
        let filtered = MenuTreeFilter.filter(
            tree([group("Disks", href("Macintosh HD"), href("Backup"))]),
            query: "disks"
        )
        XCTAssertEqual(allTitles(filtered), ["Disks", "Macintosh HD", "Backup"])
    }

    func testNoMatchYieldsNothing() {
        XCTAssertTrue(MenuTreeFilter.filter(tree([href("Alpha")]), query: "zzzz").isEmpty)
    }

    /// A tree cannot rank — reordering would move rows out from under their
    /// parents — so filtered results keep the plugin's order.
    func testFilteringNeverReorders() {
        let filtered = MenuTreeFilter.filter(
            tree([href("zzz disk"), href("disk"), href("a disk")]),
            query: "disk"
        )
        XCTAssertEqual(allTitles(filtered), ["zzz disk", "disk", "a disk"])
    }

    /// Furniture marks boundaries between rows that filtering has just pulled
    /// apart, so it would draw dividers around groups that no longer exist.
    func testHeadersAndSeparatorsAreDroppedOnceFiltering() {
        let filtered = MenuTreeFilter.filter(
            tree([header("Alpha Section"), href("Alpha"), .separator]),
            query: "alpha"
        )
        XCTAssertEqual(allTitles(filtered), ["Alpha"])
        XCTAssertEqual(filtered.count, 1, "no separator survived either")
    }

    func testMatchingIsCaseAndDiacriticInsensitive() {
        let filtered = MenuTreeFilter.filter(tree([href("Café")]), query: "CAFE")
        XCTAssertEqual(allTitles(filtered), ["Café"])
    }

    // MARK: - Display projection

    func testClosedBranchesHideTheirChildren() {
        let visible = MenuTreeDisplay.visibleNodes(
            tree([group("Disks", href("Macintosh HD")), href("Alpha")]),
            expanded: []
        )
        XCTAssertEqual(visible.compactMap { $0.row?.spec.item.text }, ["Disks", "Alpha"])
    }

    func testAnOpenBranchShowsItsChildrenIndentedOneLevel() {
        let visible = MenuTreeDisplay.visibleNodes(
            tree([group("Disks", href("Macintosh HD"))]),
            expanded: [["Disks"]]
        )
        let rows = visible.compactMap(\.row)
        XCTAssertEqual(rows.map(\.spec.item.text), ["Disks", "Macintosh HD"])
        XCTAssertEqual(rows.map(\.depth), [0, 1])
    }

    func testRevealAllOpensEverythingRegardlessOfState() {
        let visible = MenuTreeDisplay.visibleNodes(
            tree([group("Disks", group("Volumes", href("Macintosh HD")))]),
            expanded: [],
            revealAll: true
        )
        XCTAssertEqual(visible.compactMap { $0.row?.spec.item.text }, ["Disks", "Volumes", "Macintosh HD"])
    }

    func testALeafCannotExpand() {
        let visible = MenuTreeDisplay.visibleNodes(tree([href("Alpha")]), expanded: [])
        XCTAssertEqual(visible.first?.row?.canExpand, false)
    }

    /// A row can declare a submenu whose children are all hidden. It has
    /// nothing to open, so it must not offer a chevron.
    func testARowWhoseChildrenAreAllHiddenCannotExpand() {
        var hidden = LineParams()
        hidden.href = URL(string: "https://example.com")
        hidden.dropdown = false
        let parent = MenuItem(text: "Parent", params: LineParams(), submenu: [
            .item(MenuItem(text: "hidden", params: hidden))
        ])
        let visible = MenuTreeDisplay.visibleNodes(MenuTree.build([.item(parent)]), expanded: [])
        XCTAssertEqual(visible.first?.row?.canExpand, false)
    }

    func testHeadersAndSeparatorsAreNotSelectable() {
        let visible = MenuTreeDisplay.visibleNodes(
            tree([header("S"), href("Alpha"), .separator]),
            expanded: []
        )
        XCTAssertEqual(visible.map(\.isSelectable), [false, true, false])
    }

    func testBranchKeysAreTheAncestorTitlePath() {
        let keys = MenuTreeDisplay.allKeys(tree([
            group("Disks", group("Volumes", href("Macintosh HD"))), href("Alpha")
        ]))
        XCTAssertEqual(keys, [["Disks"], ["Disks", "Volumes"]], "leaves carry no branch key")
    }
}
