import XCTest
@testable import VeeApp
import VeePluginFormat
import VeeSearch

/// The menu surface's state: filtering a tree without flattening it, which
/// branches are open, and how both survive a live refresh. AppKit-free, so all
/// of it runs without a window.
@MainActor
final class MenuSearchViewModelTests: XCTestCase {
    // MARK: - Builders

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

    private func titles(_ model: MenuSearchViewModel) -> [String] {
        model.visible.compactMap { $0.row?.spec.item.text }
    }

    // MARK: - Idle

    func testIdleShowsTopLevelWithBranchesClosed() {
        let model = MenuSearchViewModel(nodes: tree([
            href("Alpha"), group("Disks", href("Macintosh HD")), href("Beta")
        ]))
        XCTAssertEqual(titles(model), ["Alpha", "Disks", "Beta"], "a closed branch hides its children")
    }

    func testIdleKeepsHeadersAndSeparators() {
        let model = MenuSearchViewModel(nodes: tree([
            header("Section"), href("Alpha"), .separator, href("Beta")
        ]))
        let kinds = model.visible.map { node -> String in
            switch node {
            case .row: return "row"
            case .header: return "header"
            case .separator: return "separator"
            }
        }
        XCTAssertEqual(kinds, ["header", "row", "separator", "row"])
    }

    // MARK: - Expansion

    func testOpeningABranchRevealsItsChildrenInPlace() {
        let model = MenuSearchViewModel(nodes: tree([
            href("Alpha"), group("Disks", href("Macintosh HD")), href("Beta")
        ]))
        model.toggle(["Disks"])
        XCTAssertEqual(titles(model), ["Alpha", "Disks", "Macintosh HD", "Beta"])
    }

    func testTwoBranchesCanBeOpenAtOnce() {
        let model = MenuSearchViewModel(nodes: tree([
            group("Disks", href("Macintosh HD")), group("Network", href("Wi-Fi"))
        ]))
        model.toggle(["Disks"])
        model.toggle(["Network"])
        XCTAssertEqual(titles(model), ["Disks", "Macintosh HD", "Network", "Wi-Fi"])
    }

    func testClosingABranchHidesItsChildrenAgain() {
        let model = MenuSearchViewModel(nodes: tree([group("Disks", href("Macintosh HD"))]))
        model.toggle(["Disks"])
        model.toggle(["Disks"])
        XCTAssertEqual(titles(model), ["Disks"])
    }

    func testNestedBranchesUseTheWholePathAsTheirKey() {
        let model = MenuSearchViewModel(nodes: tree([
            group("Disks", group("Volumes", href("Macintosh HD")))
        ]))
        model.toggle(["Disks"])
        model.toggle(["Disks", "Volumes"])
        XCTAssertEqual(titles(model), ["Disks", "Volumes", "Macintosh HD"])
    }

    // MARK: - Filtering

    func testFilterKeepsMatchesAndTheAncestorsNeededToReachThem() {
        let model = MenuSearchViewModel(nodes: tree([
            href("Alpha"), group("Disks", href("Macintosh HD"), href("Backup"))
        ]))
        model.query = "macintosh"
        XCTAssertEqual(titles(model), ["Disks", "Macintosh HD"], "the ancestor comes along, the sibling does not")
    }

    func testFilterRevealsAncestorsAutomatically() {
        let model = MenuSearchViewModel(nodes: tree([
            group("Disks", group("Volumes", href("Macintosh HD")))
        ]))
        model.query = "macintosh"
        XCTAssertEqual(titles(model), ["Disks", "Volumes", "Macintosh HD"], "no branch had been opened by hand")
    }

    func testMatchingAGroupSurfacesEverythingInsideIt() {
        let model = MenuSearchViewModel(nodes: tree([
            group("Disks", href("Macintosh HD"), href("Backup")), href("Alpha")
        ]))
        model.query = "disks"
        XCTAssertEqual(titles(model), ["Disks", "Macintosh HD", "Backup"])
    }

    /// A tree cannot reorder, so filtering keeps the plugin's authored order —
    /// the deliberate trade for preserving structure.
    func testFilteringPreservesAuthoredOrder() {
        let model = MenuSearchViewModel(nodes: tree([
            href("zzz disk"), href("disk"), href("a disk")
        ]))
        model.query = "disk"
        XCTAssertEqual(titles(model), ["zzz disk", "disk", "a disk"])
    }

    func testFilterDropsHeadersAndSeparators() {
        let model = MenuSearchViewModel(nodes: tree([
            header("Section"), href("Alpha"), .separator, href("Alpine")
        ]))
        model.query = "alp"
        XCTAssertEqual(model.visible.count, 2)
        XCTAssertEqual(titles(model), ["Alpha", "Alpine"])
    }

    func testEmptyQueryRestoresTheFullStructure() {
        let model = MenuSearchViewModel(nodes: tree([
            header("Section"), href("Alpha"), group("Disks", href("Macintosh HD"))
        ]))
        model.query = "macintosh"
        model.query = ""
        XCTAssertEqual(titles(model), ["Alpha", "Disks"])
        XCTAssertEqual(model.visible.count, 3, "the header is back")
    }

    /// Every token must match (AND). Matching is fuzzy-subsequence, so a token
    /// only excludes a row when its characters genuinely cannot be found in
    /// order — `ssd` fails on `Macintosh HD` for want of a second `s`.
    func testMultiTokenAnd() {
        let model = MenuSearchViewModel(nodes: tree([href("Macintosh HD"), href("Macintosh SSD")]))
        model.query = "mac ssd"
        XCTAssertEqual(titles(model), ["Macintosh SSD"])
        model.query = "macintosh"
        XCTAssertEqual(titles(model), ["Macintosh HD", "Macintosh SSD"])
        model.query = "macintosh zzz"
        XCTAssertEqual(titles(model), [], "a token that matches nothing excludes every row")
    }

    // MARK: - Open branches survive a refresh

    func testARefreshKeepsBranchesOpen() {
        let model = MenuSearchViewModel(nodes: tree([group("Disks", href("Macintosh HD 40%"))]))
        model.toggle(["Disks"])
        model.update(nodes: tree([group("Disks", href("Macintosh HD 41%"))]))
        XCTAssertEqual(titles(model), ["Disks", "Macintosh HD 41%"], "still open, showing the new value")
    }

    func testRepeatedRefreshesLeaveOpenBranchesOpen() {
        let model = MenuSearchViewModel(nodes: tree([group("Disks", href("a"))]))
        model.toggle(["Disks"])
        for i in 0..<10 {
            model.update(nodes: tree([group("Disks", href("value \(i)"))]))
        }
        XCTAssertEqual(titles(model), ["Disks", "value 9"])
    }

    /// The containment guarantee: a branch that cannot be matched after a
    /// refresh closes **alone**. Title-keyed expansion is imperfect by
    /// construction — a plugin that retitles a group changes its own key — so
    /// what is pinned here is that the damage never spreads.
    func testAVanishedBranchClosesWithoutDisturbingItsSiblings() {
        let model = MenuSearchViewModel(nodes: tree([
            group("Disks", href("Macintosh HD")), group("Network", href("Wi-Fi"))
        ]))
        model.toggle(["Disks"])
        model.toggle(["Network"])

        model.update(nodes: tree([group("Network", href("Wi-Fi"))]))
        XCTAssertEqual(titles(model), ["Network", "Wi-Fi"], "Network stays open after Disks disappeared")
    }

    func testARetitledBranchClosesOnlyItself() {
        let model = MenuSearchViewModel(nodes: tree([
            group("Disks (3)", href("Macintosh HD")), group("Network", href("Wi-Fi"))
        ]))
        model.toggle(["Disks (3)"])
        model.toggle(["Network"])

        model.update(nodes: tree([
            group("Disks (4)", href("Macintosh HD")), group("Network", href("Wi-Fi"))
        ]))
        XCTAssertEqual(
            titles(model), ["Disks (4)", "Network", "Wi-Fi"],
            "the retitled branch closed; the untouched one did not"
        )
    }

    func testTheQuerySurvivesARefresh() {
        let model = MenuSearchViewModel(nodes: tree([href("cpu 12%"), href("memory")]))
        model.query = "cpu"
        model.update(nodes: tree([href("cpu 15%"), href("memory")]))
        XCTAssertEqual(titles(model), ["cpu 15%"])
    }

    // MARK: - Selection

    func testSelectionStartsOnTheFirstRow() {
        let model = MenuSearchViewModel(nodes: tree([header("Section"), href("Alpha")]))
        XCTAssertEqual(model.selectedRow()?.item.text, "Alpha", "a header is not selectable")
    }

    func testArrowsMoveOverRowsAndSkipFurniture() {
        let model = MenuSearchViewModel(nodes: tree([href("Alpha"), .separator, href("Beta")]))
        model.moveDown()
        XCTAssertEqual(model.selectedRow()?.item.text, "Beta")
        model.moveUp()
        XCTAssertEqual(model.selectedRow()?.item.text, "Alpha")
    }

    func testArrowsClampWithoutWrapping() {
        let model = MenuSearchViewModel(nodes: tree([href("Alpha"), href("Beta")]))
        model.moveUp()
        XCTAssertEqual(model.selectedRow()?.item.text, "Alpha")
        model.moveDown()
        model.moveDown()
        XCTAssertEqual(model.selectedRow()?.item.text, "Beta")
    }

    /// A parent is selectable so it can be opened from the keyboard — which is
    /// what `→` does, and `←` closes it again.
    func testRightOpensTheSelectedBranchAndLeftClosesIt() {
        let model = MenuSearchViewModel(nodes: tree([group("Disks", href("Macintosh HD"))]))
        XCTAssertEqual(model.selectedRow()?.item.text, "Disks")
        model.expandSelection()
        XCTAssertEqual(titles(model), ["Disks", "Macintosh HD"])
        model.collapseSelection()
        XCTAssertEqual(titles(model), ["Disks"])
    }

    func testLeftFromALeafMovesToItsParent() {
        let model = MenuSearchViewModel(nodes: tree([group("Disks", href("Macintosh HD"))]))
        model.toggle(["Disks"])
        model.moveDown()
        XCTAssertEqual(model.selectedRow()?.item.text, "Macintosh HD")
        model.collapseSelection()
        XCTAssertEqual(model.selectedRow()?.item.text, "Disks")
    }

    func testSelectionSurvivesARefreshByPosition() {
        let model = MenuSearchViewModel(nodes: tree([href("cpu 12%"), href("memory 4G")]))
        model.moveDown()
        XCTAssertEqual(model.selectedRow()?.item.text, "memory 4G")
        model.update(nodes: tree([href("cpu 15%"), href("memory 3G")]))
        XCTAssertEqual(model.selectedRow()?.item.text, "memory 3G", "position, not text — a watched row's text changes")
    }

    func testSelectionClampsForwardWhenTheListShrinks() {
        let model = MenuSearchViewModel(nodes: tree([href("a"), href("b"), href("c")]))
        model.moveDown()
        model.moveDown()
        XCTAssertEqual(model.selectedRow()?.item.text, "c")
        model.update(nodes: tree([href("a")]))
        XCTAssertEqual(model.selectedRow()?.item.text, "a")
    }

    func testNoSelectionWhenNothingMatches() {
        let model = MenuSearchViewModel(nodes: tree([href("Alpha")]))
        model.query = "zzzz"
        XCTAssertEqual(model.selection, -1)
        XCTAssertNil(model.selectedRow())
    }

    // MARK: - Alternates

    private func withAlternate(_ text: String, alt: String) -> MenuNode {
        var p = LineParams()
        p.href = URL(string: "https://example.com")
        return .item(MenuItem(text: text, params: p, alternate: MenuItem(text: alt, params: p)))
    }

    func testOptionSwapsThePairUnderTheSelection() {
        let model = MenuSearchViewModel(nodes: tree([
            href("Alpha"), withAlternate("Copy", alt: "Copy Path"), href("Beta")
        ]))
        model.moveDown()
        XCTAssertEqual(model.selectedRow()?.item.text, "Copy")
        model.optionHeld = true
        XCTAssertEqual(titles(model), ["Alpha", "Copy Path", "Beta"])
        XCTAssertEqual(model.selectedRow()?.item.text, "Copy Path", "selection stays put; the row swaps under it")
        model.optionHeld = false
        XCTAssertEqual(model.selectedRow()?.item.text, "Copy")
    }

    func testFilteringShowsBothHalvesAndIgnoresOption() {
        let model = MenuSearchViewModel(nodes: tree([withAlternate("Copy", alt: "Copy Path")]))
        model.query = "copy"
        XCTAssertEqual(titles(model), ["Copy", "Copy Path"])
        model.optionHeld = true
        XCTAssertEqual(titles(model), ["Copy", "Copy Path"], "the modifier is inert while filtering")
    }

    func testAQueryReachesTheAlternateWithoutTheModifier() {
        let model = MenuSearchViewModel(nodes: tree([withAlternate("Copy", alt: "Copy Path")]))
        model.query = "path"
        XCTAssertEqual(titles(model), ["Copy Path"], "explicit intent beats the modifier gate")
    }
}
