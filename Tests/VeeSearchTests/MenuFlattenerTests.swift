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

    private func actionEntry(_ text: String) -> SearchEntry {
        .action(FlatRow(item: MenuItem(text: text), path: [], title: text, haystack: text))
    }

    /// The `.action`/`.info` row for `text` in a flattened entry list — sugar
    /// for digging one row's breadcrumb out of a mixed `[SearchEntry]`.
    private func flatRow(_ text: String, in entries: [SearchEntry]) -> FlatRow? {
        for entry in entries {
            switch entry {
            case .action(let r), .info(let r): if r.item.text == text { return r }
            case .header, .separator: continue
            }
        }
        return nil
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

    // MARK: - flattenEntries: emission kinds

    func testFlattenEntriesEmitsHeaderInfoActionAndSeparatorInOrder() {
        let entries = MenuFlattener.flattenEntries([
            header("Section"),
            plain("CPU: 42%"),        // non-actionable sub-text → .info
            href("Open Issue"),       // actionable → .action
            .separator,
            href("Refresh")
        ])
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries[0], .header("Section"))
        guard case .info(let cpu) = entries[1] else { return XCTFail("expected an .info row") }
        XCTAssertEqual(cpu.item.text, "CPU: 42%")
        guard case .action(let issue) = entries[2] else { return XCTFail("expected an .action row") }
        XCTAssertEqual(issue.item.text, "Open Issue")
        XCTAssertEqual(entries[3], .separator)
        guard case .action(let refresh) = entries[4] else { return XCTFail("expected an .action row") }
        XCTAssertEqual(refresh.item.text, "Refresh")
    }

    func testFlattenEntriesDisabledItemBecomesInfo() {
        let entries = MenuFlattener.flattenEntries([disabledAction("Disabled Item")])
        XCTAssertEqual(entries.count, 1)
        guard case .info(let row) = entries[0] else {
            return XCTFail("a disabled item — even an otherwise-actionable one — must surface as .info, not .action")
        }
        XCTAssertEqual(row.item.text, "Disabled Item")
        XCTAssertNotNil(row.item.params.href, "disabled overrides actionability, it doesn't strip the href")
    }

    func testFlattenEntriesDropdownFalseInvisibleButStillDescends() {
        let entries = MenuFlattener.flattenEntries([
            menuBarOnly("Hidden Parent", submenu: [href("Visible Child")]),
            href("Sibling")
        ])
        // The dropdown=false parent contributes no entry of its own — not even
        // a section boundary — but its submenu is still walked.
        XCTAssertEqual(entries.count, 2)
        guard case .action(let child) = entries[0] else { return XCTFail("expected the descended child") }
        XCTAssertEqual(child.item.text, "Visible Child")
        guard case .action(let sibling) = entries[1] else { return XCTFail("expected the sibling") }
        XCTAssertEqual(sibling.item.text, "Sibling")
    }

    func testFlattenEntriesEmptyTextGroupEmitsNothingButDescends() {
        let entries = MenuFlattener.flattenEntries([
            plain("", submenu: [href("Leaf")])   // group with no title: no entry of its own
        ])
        XCTAssertEqual(entries.count, 1)
        guard case .action(let leaf) = entries[0] else { return XCTFail("expected the child action row") }
        XCTAssertEqual(leaf.item.text, "Leaf")
        XCTAssertEqual(leaf.path, [], "the empty-text group contributes no breadcrumb segment")
    }

    func testFlattenEntriesEmptyTextLeafEmitsNothing() {
        XCTAssertTrue(MenuFlattener.flattenEntries([plain("   ")]).isEmpty)   // whitespace-only text
    }

    /// Mirrors `MenuBuilder.makeItem`'s early return for `header=true`
    /// (`NSMenuItem.sectionHeader(title:)`, built before any submenu) — a
    /// header's submenu is never part of the native dropdown, so it must
    /// never reach the panel either, unlike `dropdown=false` which still
    /// descends.
    func testHeaderWithSubmenuNeverDescendsMirrorsDropdownHiddenSubmenu() {
        let entries = MenuFlattener.flattenEntries([
            header("Section", submenu: [href("Hidden Action")]),
            href("Sibling")
        ])
        XCTAssertEqual(entries.count, 2, "the header's submenu contributes nothing — not even its actionable child")
        XCTAssertEqual(entries[0], .header("Section"), "the header row itself still emits, at the top level")
        XCTAssertNil(flatRow("Hidden Action", in: entries), "a header's submenu must never be walked")
        guard case .action(let sibling) = entries[1] else { return XCTFail("expected the sibling action") }
        XCTAssertEqual(sibling.item.text, "Sibling")
    }

    /// `header=true` is checked before the action/info branch and always
    /// `continue`s past it — an incidental `href=` must not smuggle a header
    /// line into `.action`.
    func testHeaderWithHrefNeverBecomesAnActionRow() {
        var p = LineParams()
        p.swiftbar.header = true
        p.href = URL(string: "https://example.com")
        let entries = MenuFlattener.flattenEntries([
            .item(MenuItem(text: "Section", params: p)),
            href("Sibling")
        ])
        XCTAssertEqual(entries[0], .header("Section"), "header=true takes precedence over an incidental href")
        XCTAssertFalse(entries.contains { if case .action(let r) = $0 { return r.item.text == "Section" }; return false })
    }

    // MARK: - Section scoping

    func testSectionScopesFollowingSiblingsBreadcrumb() {
        let entries = MenuFlattener.flattenEntries([
            header("Recent"),
            href("Issue 1"),
            href("Issue 2")
        ])
        XCTAssertEqual(flatRow("Issue 1", in: entries)?.path, ["Recent"])
        XCTAssertEqual(flatRow("Issue 2", in: entries)?.path, ["Recent"])
    }

    func testSectionEndsAtSeparatorAtSameLevel() {
        let entries = MenuFlattener.flattenEntries([
            header("Recent"),
            href("Issue 1"),
            .separator,
            href("Issue 2")
        ])
        XCTAssertEqual(flatRow("Issue 1", in: entries)?.path, ["Recent"])
        XCTAssertEqual(flatRow("Issue 2", in: entries)?.path, [], "the separator ends the section for later siblings")
    }

    func testSectionEndsAtNextHeaderAtSameLevel() {
        let entries = MenuFlattener.flattenEntries([
            header("Recent"),
            href("Issue 1"),
            header("Archived"),
            href("Issue 2")
        ])
        XCTAssertEqual(flatRow("Issue 1", in: entries)?.path, ["Recent"])
        XCTAssertEqual(flatRow("Issue 2", in: entries)?.path, ["Archived"], "a new header replaces the active section for later siblings")
    }

    func testNestedSubmenuSectionScopeIsIndependentOfParentLevel() {
        let entries = MenuFlattener.flattenEntries([
            header("Recent"),
            plain("orders", submenu: [
                header("Sub"),
                href("Task A"),
                .separator,
                href("Task B")
            ]),
            href("Issue 1")
        ])
        XCTAssertEqual(entries.count, 5, "the nested header and separator are section-scope bookkeeping only — never their own entries below depth 0")
        XCTAssertEqual(flatRow("orders", in: entries)?.path, ["Recent"], "the outer section wraps the group itself")
        XCTAssertEqual(flatRow("Task A", in: entries)?.path, ["Recent", "orders", "Sub"], "the submenu's own header opens an independent inner section")
        XCTAssertEqual(flatRow("Task B", in: entries)?.path, ["Recent", "orders"], "the inner separator ends the submenu's OWN section, not the parent's")
        XCTAssertEqual(flatRow("Issue 1", in: entries)?.path, ["Recent"], "back at the top level, the outer section is untouched by anything inside the submenu")
    }

    /// The requirement section scoping exists for: the section title folds
    /// into the row's haystack, so typing it surfaces the section's rows —
    /// not just its display breadcrumb.
    func testSearchingTheSectionNameMatchesItsRows() {
        let entries = MenuFlattener.flattenEntries([
            header("Recent"),
            href("Issue 1"),
            href("Issue 2")
        ])
        let result = MenuSearch.search("recent", in: entries)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { if case .action = $0 { return true }; return false })
    }

    // MARK: - Depth-gated furniture: nested headers/separators never leak into the flat stream

    /// The reviewer's leak scenario: before the fix, a header/separator
    /// nested inside a sibling item's submenu spliced its own `.header`/
    /// `.separator` entry into the flat stream between top-level rows it has
    /// no business separating. Pinned by the full emitted sequence, not just
    /// a couple of sampled paths.
    func testNestedHeaderAndSeparatorNeverLeakIntoTheFlatStreamBetweenTopLevelRows() {
        let entries = MenuFlattener.flattenEntries([
            header("Recent"),
            plain("CPU: 42%"),
            plain("orders", submenu: [
                header("Sub"),
                href("Task A"),
                .separator,
                href("Task B")
            ]),
            href("Trailing")
        ])

        XCTAssertEqual(entries.count, 6, "no entry for the nested header or the nested separator")
        XCTAssertEqual(entries.filter { if case .header = $0 { return true }; return false }, [.header("Recent")], "exactly one .header entry in the whole stream")
        XCTAssertTrue(entries.allSatisfy { if case .separator = $0 { return false }; return true }, "zero .separator entries — the tree's only separator is nested")

        XCTAssertEqual(flatRow("Task A", in: entries)?.path, ["Recent", "orders", "Sub"], "the nested header still opens its own section before the nested separator")
        XCTAssertEqual(flatRow("Task B", in: entries)?.path, ["Recent", "orders"], "the nested separator still resets that section afterward")

        guard case .action(let trailing) = entries.last else { return XCTFail("expected the trailing top-level action last") }
        XCTAssertEqual(trailing.item.text, "Trailing")
        XCTAssertEqual(trailing.path, ["Recent"], "sits directly after Task B — no nested header entry leaked in between — and stays scoped by the OUTER section")
    }

    // MARK: - normalized(_:)

    func testNormalizedCollapsesSeparatorRuns() {
        let result = MenuFlattener.normalized([actionEntry("A"), .separator, .separator, .separator, actionEntry("B")])
        XCTAssertEqual(result, [actionEntry("A"), .separator, actionEntry("B")])
    }

    func testNormalizedTrimsLeadingAndTrailingSeparators() {
        let result = MenuFlattener.normalized([.separator, actionEntry("A"), .separator])
        XCTAssertEqual(result, [actionEntry("A")])
    }

    func testNormalizedDropsADanglingHeaderButKeepsOneWithContent() {
        XCTAssertEqual(
            MenuFlattener.normalized([.header("Populated"), actionEntry("A")]),
            [.header("Populated"), actionEntry("A")],
            "a header WITH content underneath it is kept"
        )
        XCTAssertEqual(
            MenuFlattener.normalized([actionEntry("A"), .header("Dangling")]),
            [actionEntry("A")],
            "a header at the very end of the list has nothing under it"
        )
        XCTAssertEqual(
            MenuFlattener.normalized([.header("First"), .header("Second"), actionEntry("A")]),
            [.header("Second"), actionEntry("A")],
            "a header immediately followed by another header is dangling"
        )
    }

    /// Fixpoint case from the doc comment: dropping a dangling header can
    /// expose a newly-trailing separator that must ALSO go.
    func testNormalizedFixpointDroppingADanglingHeaderExposesATrailingSeparator() {
        let result = MenuFlattener.normalized([actionEntry("Item"), .header("Dangling"), .separator])
        XCTAssertEqual(result, [actionEntry("Item")])
    }

    /// A longer chain: trimming the leading separator (only exposed once the
    /// first dangling header is dropped) leaves a SECOND header dangling at
    /// the new front of the list — needs more than one pass to fully settle.
    func testNormalizedFixpointHandlesChainedDanglingHeadersAndSeparators() {
        let result = MenuFlattener.normalized([.header("A"), .separator, .header("B"), actionEntry("Item")])
        XCTAssertEqual(result, [.header("B"), actionEntry("Item")])
    }
}
