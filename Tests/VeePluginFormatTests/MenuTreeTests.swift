import XCTest
@testable import VeePluginFormat

/// `MenuTree` is the single place every surface reads its decisions from, so
/// these assertions are the ones that used to be spread across
/// `MenuBuilder.isActionable`, `MenuFlattener.isActionable`, and
/// `MenuRowAccessory.kind(for:)` — three copies kept in agreement by comment.
/// Pure, so none of it needs an `NSMenu` or a running app.
final class MenuTreeTests: XCTestCase {
    // MARK: - Helpers

    private func item(_ text: String, _ configure: (inout LineParams) -> Void = { _ in }) -> MenuItem {
        var params = LineParams()
        configure(&params)
        return MenuItem(text: text, params: params)
    }

    private func rows(_ nodes: [MenuTreeNode]) -> [MenuRowSpec] {
        nodes.compactMap { if case .row(let r) = $0 { return r } else { return nil } }
    }

    private func onlyRow(_ item: MenuItem) -> MenuRowSpec {
        let built = rows(MenuTree.build([.item(item)]))
        precondition(built.count == 1, "expected exactly one row, got \(built.count)")
        return built[0]
    }

    private let chart = ChartParams(kind: .pie, values: [1, 2, 3])
    private let link = URL(string: "https://example.com")!

    // MARK: - Which nodes become rows

    func testSeparatorsSurviveWhereTheyWereAuthored() {
        let built = MenuTree.build([.item(item("a")), .separator, .item(item("b"))])
        XCTAssertEqual(built.count, 3)
        guard case .separator = built[1] else { return XCTFail("the separator must stay between the two rows") }
    }

    /// Nothing is collapsed, trimmed, or repaired — a surface shows exactly what
    /// the plugin authored. The flat projection used to normalise runs of
    /// separators away; the tree has no damage to repair.
    func testRunsOfSeparatorsAreNotCollapsed() {
        let built = MenuTree.build([.separator, .separator, .item(item("a"))])
        XCTAssertEqual(built.count, 3)
    }

    func testDropdownFalseRowsAreExcluded() {
        let built = MenuTree.build([
            .item(item("visible")),
            .item(item("menu-bar only") { $0.dropdown = false })
        ])
        XCTAssertEqual(rows(built).map(\.text), ["visible"])
    }

    /// A hidden row takes its alternate with it — the alternate exists only as
    /// that row's ⌥ replacement.
    func testAHiddenRowTakesItsAlternateWithIt() {
        var hidden = item("hidden") { $0.dropdown = false }
        hidden.alternate = item("hidden alt")
        XCTAssertTrue(rows(MenuTree.build([.item(hidden)])).isEmpty)
    }

    // MARK: - Alternates

    func testAnAlternateIsASiblingImmediatelyAfterItsRow() {
        var main = item("Refresh") { $0.refresh = true }
        main.alternate = item("Force Refresh") { $0.refresh = true }
        let built = rows(MenuTree.build([.item(main)]))
        XCTAssertEqual(built.map(\.text), ["Refresh", "Force Refresh"])
        XCTAssertFalse(built[0].isAlternate)
        XCTAssertTrue(built[1].isAlternate)
    }

    /// AppKit swaps an alternate for its predecessor only when the two carry
    /// the same key equivalent. A primary declaring `key=` therefore has to
    /// lend it to its alternate, or the pair renders as two ordinary rows with
    /// nothing bound to the modifier.
    func testAnAlternateInheritsItsPrimarysKeyEquivalent() {
        var main = item("Refresh") {
            $0.refresh = true
            $0.key = "r"
        }
        main.alternate = item("Force Refresh") { $0.refresh = true }
        let built = rows(MenuTree.build([.item(main)]))
        XCTAssertEqual(built[0].keyEquivalent, "r")
        XCTAssertEqual(built[1].keyEquivalent, "r", "the alternate carries the primary's key, not its own absence of one")
    }

    /// An alternate cannot hold a key equivalent of its own — AppKit requires it
    /// to match the primary's — so the primary's wins outright.
    func testAnAlternatesOwnKeyEquivalentIsIgnored() {
        var main = item("Refresh") {
            $0.refresh = true
            $0.key = "r"
        }
        main.alternate = item("Force Refresh") {
            $0.refresh = true
            $0.key = "f"
        }
        XCTAssertEqual(rows(MenuTree.build([.item(main)]))[1].keyEquivalent, "r")
    }

    func testAnAlternateOfAKeylessPrimaryCarriesNoKey() {
        var main = item("Reveal") { $0.href = self.link }
        main.alternate = item("Reveal alternate") { $0.href = self.link }
        let built = rows(MenuTree.build([.item(main)]))
        XCTAssertNil(built[0].keyEquivalent)
        XCTAssertNil(built[1].keyEquivalent)
    }

    // MARK: - Headers

    func testAHeaderIsInertAndCarriesNothingElse() {
        let row = onlyRow(item("Section") {
            $0.swiftbar.header = true
            $0.href = self.link
            $0.progress = ProgressParams(fraction: 0.5)
        })
        XCTAssertTrue(row.isHeader)
        XCTAssertFalse(row.isActionable)
        XCTAssertNil(row.accessory, "a native section header is title-only")
    }

    /// AppKit never builds a section header's submenu, so it is never walked.
    func testAHeadersChildrenAreNotWalked() {
        var header = item("Section") { $0.swiftbar.header = true }
        header.submenu = [.item(item("buried"))]
        XCTAssertTrue(onlyRow(header).children.isEmpty)
    }

    // MARK: - Actionability

    func testEveryDispatchedParamMakesARowActionable() {
        XCTAssertTrue(onlyRow(item("href") { $0.href = self.link }).isActionable)
        XCTAssertTrue(onlyRow(item("shell") { $0.shell = ShellCommand(launchPath: "/bin/ls", arguments: [], openInTerminal: false) }).isActionable)
        XCTAssertTrue(onlyRow(item("refresh") { $0.refresh = true }).isActionable)
        XCTAssertTrue(onlyRow(item("shortcut") { $0.swiftbar.shortcut = "Do Thing" }).isActionable)
        XCTAssertTrue(onlyRow(item("webview") { $0.swiftbar.webview = self.link }).isActionable)
        XCTAssertTrue(onlyRow(item("sparkline") { $0.sparkline = [1, 2, 3] }).isActionable)
        XCTAssertTrue(onlyRow(item("chart") { $0.swiftbar.chart = self.chart }).isActionable)
        XCTAssertTrue(onlyRow(item("control") { $0.control = .toggle(on: true) }).isActionable)
    }

    func testAPlainRowIsInert() {
        XCTAssertFalse(onlyRow(item("just text")).isActionable)
    }

    /// `progress=` is display-only — it is never dispatched, so it must not by
    /// itself make a row clickable.
    func testProgressAloneIsNotActionable() {
        XCTAssertFalse(onlyRow(item("gauge") { $0.progress = ProgressParams(fraction: 0.5) }).isActionable)
    }

    func testAnEmptyShortcutIsNotActionable() {
        XCTAssertFalse(onlyRow(item("empty") { $0.swiftbar.shortcut = "" }).isActionable)
    }

    func testADisabledRowIsNeverActionable() {
        let row = onlyRow(item("disabled") {
            $0.href = self.link
            $0.disabled = true
        })
        XCTAssertFalse(row.isEnabled)
        XCTAssertFalse(row.isActionable)
    }

    /// Children win over a command: AppKit wires either a submenu or an action,
    /// never both, so a destructive command on a parent row must not fire from
    /// any surface.
    func testChildrenWinOverACommand() {
        var parent = item("Parent") { $0.shell = ShellCommand(launchPath: "/bin/rm", arguments: ["-rf", "/"], openInTerminal: false) }
        parent.submenu = [.item(item("child"))]
        let row = onlyRow(parent)
        XCTAssertFalse(row.isActionable, "a row with children must not run its own command")
        XCTAssertEqual(rows(row.children).map(\.text), ["child"])
    }

    /// The submenu-wins rule keys off the *declaration*, not the filtered
    /// result: a parent whose children are all hidden still declares a submenu,
    /// so it stays inert with an empty one rather than becoming clickable.
    func testAParentWhoseChildrenAreAllHiddenStaysInert() {
        var parent = item("Parent") { $0.href = self.link }
        parent.submenu = [.item(item("hidden") { $0.dropdown = false })]
        let row = onlyRow(parent)
        XCTAssertTrue(row.hasSubmenu)
        XCTAssertTrue(row.children.isEmpty)
        XCTAssertFalse(row.isActionable)
    }

    // MARK: - Display graphics

    func testDisplayGraphicPrecedenceIsProgressThenSparklineThenChart() {
        let all = onlyRow(item("all") {
            $0.progress = ProgressParams(fraction: 0.5)
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.chart = self.chart
        })
        guard case .progress = all.accessory else { return XCTFail("the gauge outranks the rest") }

        let sparkAndChart = onlyRow(item("two") {
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.chart = self.chart
        })
        guard case .sparkline = sparkAndChart.accessory else { return XCTFail("the sparkline outranks the chart") }

        let chartOnly = onlyRow(item("chart") { $0.swiftbar.chart = self.chart })
        guard case .chart = chartOnly.accessory else { return XCTFail("expected the chart") }
    }

    func testAnEmptySparklineIsNoGraphic() {
        XCTAssertNil(onlyRow(item("empty") { $0.sparkline = [] }).accessory)
    }

    /// A live control is not a display graphic: the row exposes both, and each
    /// surface decides which it can draw. The menu bar draws the gauge (it
    /// cannot host a control); a window draws the control.
    func testAControlIsCarriedSeparatelyFromTheDisplayGraphic() {
        let row = onlyRow(item("both") {
            $0.control = .toggle(on: true)
            $0.progress = ProgressParams(fraction: 0.5)
        })
        XCTAssertEqual(row.control, .toggle(on: true))
        guard case .progress = row.accessory else { return XCTFail("the display graphic is still resolved") }
    }

    func testSparklineStyleTravelsWithTheSeries() {
        let row = onlyRow(item("spark") {
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.sparklineStyle = SparklineStyle(width: 140, height: 24, color: .named("teal"))
        })
        guard case .sparkline(let values, let style, _) = row.accessory else { return XCTFail("expected a sparkline") }
        XCTAssertEqual(values, [1, 2, 3])
        XCTAssertEqual(style.effectiveWidth, 140)
        XCTAssertEqual(style.color, .named("teal"))
    }

    // MARK: - Passthrough state

    func testCheckedTooltipPlacementAndKeyAreCarried() {
        let row = onlyRow(item("row") {
            $0.swiftbar.checked = true
            $0.swiftbar.accessory = .leading
            $0.key = "r"
            $0.progress = ProgressParams(fraction: 0.5)
        })
        XCTAssertTrue(row.isChecked)
        XCTAssertTrue(row.accessoryLeading)
        XCTAssertEqual(row.keyEquivalent, "r")
    }

    // MARK: - Nesting

    func testNestingIsPreservedToDepth() {
        var grandchild = item("leaf") { $0.href = self.link }
        grandchild.params.href = link
        var child = item("child")
        child.submenu = [.item(grandchild)]
        var parent = item("parent")
        parent.submenu = [.item(child)]

        let top = onlyRow(parent)
        let mid = rows(top.children)
        XCTAssertEqual(mid.map(\.text), ["child"])
        let leaf = rows(mid[0].children)
        XCTAssertEqual(leaf.map(\.text), ["leaf"])
        XCTAssertTrue(leaf[0].isActionable)
    }
}
