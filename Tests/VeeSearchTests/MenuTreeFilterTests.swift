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

    /// Built for the panel, the surface this filter belongs to.
    private func tree(_ nodes: [MenuNode]) -> [MenuTreeNode] { MenuTree.build(nodes, surface: .search) }

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
        let visible = MenuTreeDisplay.visibleNodes(MenuTree.build([.item(parent)], surface: .search), expanded: [])
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

    // MARK: - Alternates

    /// A row whose ⌥-alternate is `alt`, both activatable.
    private func withAlternate(_ text: String, alt: String, altSubmenu: [MenuNode] = []) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        return .item(MenuItem(
            text: text, params: p,
            alternate: MenuItem(text: alt, params: p, submenu: altSubmenu)
        ))
    }

    private func titles(_ visible: [VisibleNode]) -> [String] {
        visible.compactMap { $0.row?.spec.item.text }
    }

    func testIdleShowsOnlyThePrimary() {
        let visible = MenuTreeDisplay.visibleNodes(
            tree([withAlternate("Copy", alt: "Copy Path")]), expanded: []
        )
        XCTAssertEqual(titles(visible), ["Copy"])
    }

    func testHoldingOptionSwapsInTheAlternate() {
        let visible = MenuTreeDisplay.visibleNodes(
            tree([withAlternate("Copy", alt: "Copy Path")]), expanded: [], alternatesActive: true
        )
        XCTAssertEqual(titles(visible), ["Copy Path"])
    }

    /// The swap is 1:1 in place: same length, same neighbors at the same
    /// indices, so an index-based selection rides through a ⌥ toggle untouched.
    func testTheSwapPreservesListLengthAndIndices() {
        let nodes = tree([href("Before"), withAlternate("Copy", alt: "Copy Path"), href("After")])
        let idle = MenuTreeDisplay.visibleNodes(nodes, expanded: [])
        let held = MenuTreeDisplay.visibleNodes(nodes, expanded: [], alternatesActive: true)
        XCTAssertEqual(idle.count, held.count)
        XCTAssertEqual(titles(idle), ["Before", "Copy", "After"])
        XCTAssertEqual(titles(held), ["Before", "Copy Path", "After"])
    }

    /// A query has already narrowed the menu to matches; the filtered
    /// projection shows both halves and ⌥ changes nothing.
    func testFilteringEmitsBothHalvesRegardlessOfOption() {
        let nodes = tree([withAlternate("Copy", alt: "Copy Path")])
        let idle = MenuTreeDisplay.visibleNodes(nodes, expanded: [], revealAll: true)
        let held = MenuTreeDisplay.visibleNodes(nodes, expanded: [], revealAll: true, alternatesActive: true)
        XCTAssertEqual(titles(idle), ["Copy", "Copy Path"])
        XCTAssertEqual(idle, held, "the modifier is inert while filtering")
    }

    /// An alternate whose primary is absent — a filter pruned it, or the tree
    /// was built by hand — is an ordinary row in both states, never lost.
    func testALoneAlternateRendersAsAnOrdinaryRow() {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        let lone: [MenuTreeNode] = [
            .row(MenuTree.row(for: MenuItem(text: "Copy Path", params: p), surface: .search, isAlternate: true))
        ]
        XCTAssertEqual(titles(MenuTreeDisplay.visibleNodes(lone, expanded: [])), ["Copy Path"])
        XCTAssertEqual(
            titles(MenuTreeDisplay.visibleNodes(lone, expanded: [], alternatesActive: true)),
            ["Copy Path"]
        )
    }

    // MARK: - Searchability

    /// A row whose ⌥-alternate is `alt`, with `searchable=false` on the half
    /// the plugin wants kept out of a query's way.
    private func withUnsearchableAlternate(_ text: String, alt: String) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        var quiet = p
        quiet.swiftbar.searchable = false
        return .item(MenuItem(text: text, params: p, alternate: MenuItem(text: alt, params: quiet)))
    }

    private func unsearchable(_ text: String, submenu: [MenuNode] = []) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        p.swiftbar.searchable = false
        return .item(MenuItem(text: text, params: p, submenu: submenu))
    }

    /// The point of the flag: typing the row's own name plus Return can never
    /// land on it.
    func testAnUnsearchableRowNeverEarnsAMatch() {
        let filtered = MenuTreeFilter.filter(
            tree([unsearchable("Delete Everything"), href("Delete One")]),
            query: "delete"
        )
        XCTAssertEqual(allTitles(filtered), ["Delete One"])
    }

    func testAnUnsearchableRowIsUntouchedWhileTheTreeIsIdle() {
        let nodes = tree([unsearchable("Delete Everything")])
        XCTAssertEqual(MenuTreeFilter.filter(nodes, query: ""), nodes)
    }

    /// The "a hit keeps everything under it" rule is unchanged: an unsearchable
    /// row cannot be *found*, but it is still there when its group is.
    func testAnUnsearchableRowRidesAlongInsideAMatchingAncestor() {
        let filtered = MenuTreeFilter.filter(
            tree([group("Disks", unsearchable("Erase"))]),
            query: "disks"
        )
        XCTAssertEqual(allTitles(filtered), ["Disks", "Erase"])
    }

    /// The alternate half is out of reach; the modifier swap that reveals it is
    /// a deliberate act, and stays exactly as it was.
    func testFilteringSurfacesOnlyTheSearchableHalfOfAPair() {
        let nodes = tree([withUnsearchableAlternate("Copy", alt: "Copy Path")])
        XCTAssertEqual(allTitles(MenuTreeFilter.filter(nodes, query: "copy")), ["Copy"])
        XCTAssertEqual(titles(MenuTreeDisplay.visibleNodes(nodes, expanded: [])), ["Copy"])
        XCTAssertEqual(
            titles(MenuTreeDisplay.visibleNodes(nodes, expanded: [], alternatesActive: true)),
            ["Copy Path"],
            "⌥ still swaps in the alternate when nothing is typed"
        )
    }

    /// A swapped-in alternate opens its own children under its own key.
    func testASwappedAlternateExpandsItsOwnChildren() {
        let nodes = tree([withAlternate("Copy", alt: "Copy Path", altSubmenu: [href("As Tilde")])])
        let visible = MenuTreeDisplay.visibleNodes(
            nodes, expanded: [["Copy Path"]], alternatesActive: true
        )
        XCTAssertEqual(titles(visible), ["Copy Path", "As Tilde"])
        XCTAssertEqual(visible.first?.row?.canExpand, true)
    }
}
