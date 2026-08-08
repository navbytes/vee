import XCTest
import AppKit
@testable import VeeApp
import VeeMenu
import VeePluginFormat
import VeePreferences
import VeeSearch

/// The cross-plugin "search everything" panel — the parked slice from
/// `docs/_content/roadmap.md`. `AppController.aggregateSearchRows` is the pure
/// aggregation core: given each plugin's (name, controller) snapshot, it
/// flattens + breadcrumb-prefixes every plugin's *current* menu into one
/// `SearchEntry` list (headers/info rows/separators included, a `.separator`
/// spliced between plugin blocks, normalized as a whole) and pairs each
/// `.action` row with a closure that must fire through that SAME plugin's
/// handler — never a shared one.
///
/// Constructed the same `NSApplication`-free way `CompactMenuBarControllerTests`
/// does: compact mode forced on via injected `AppPreferences`, and
/// `CompactMenuBarController(attachesStatusItem: false)` short-circuits before
/// ever reaching `NSStatusBar` — so this never touches `NSApplication.shared`
/// (rebinds the MainActor executor process-wide; see that file's note).
@MainActor
final class SearchAllPluginsAggregatorTests: XCTestCase {
    private final class RecordingHandler: MenuActionHandling {
        private(set) var performed: [MenuItem] = []
        func perform(_ item: MenuItem) { performed.append(item) }
    }

    private func makeCompactPrefs() -> AppPreferences {
        let defaults = UserDefaults(suiteName: "vee-app-tests-\(UUID().uuidString)")!
        let prefs = AppPreferences(defaults: defaults)
        prefs.compactMenuBar = true
        return prefs
    }

    private func makeController(name: String, handler: MenuActionHandling, prefs: AppPreferences, compact: CompactMenuBarController) -> StatusItemController {
        StatusItemController(pluginName: name, handler: handler, onRefresh: {}, prefs: prefs, compactController: compact)
    }

    /// A single-item menu whose item is *actionable* (`href=`) — `MenuFlattener`
    /// drops non-actionable rows, so a plain-text item would never appear here.
    private func output(itemText: String) -> ParsedOutput {
        var params = LineParams()
        params.href = URL(string: "https://example.com")
        return ParsedOutput(titleLines: [TitleLine(text: "x")], body: [.item(MenuItem(text: itemText, params: params))])
    }

    func testAggregatesRowsFromEveryPluginPrefixedWithItsDisplayName() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let alpha = makeController(name: "Alpha", handler: RecordingHandler(), prefs: prefs, compact: compact)
        let beta = makeController(name: "Beta", handler: RecordingHandler(), prefs: prefs, compact: compact)
        alpha.render(output(itemText: "Foo"))
        beta.render(output(itemText: "Bar"))

        let aggregated = AppController.aggregateSearchRows([("Alpha", alpha), ("Beta", beta)])

        XCTAssertEqual(Set(aggregated.pairs.map(\.row.item.text)), ["Foo", "Bar"])
        XCTAssertEqual(aggregated.pairs.first(where: { $0.row.item.text == "Foo" })?.row.breadcrumb, "Alpha")
        XCTAssertEqual(aggregated.pairs.first(where: { $0.row.item.text == "Bar" })?.row.breadcrumb, "Beta")
        withExtendedLifetime((alpha, beta)) {}
    }

    /// `.widget`-surface plugins have no `StatusItemController` at all
    /// (`PluginCoordinator.controller == nil`) — they must contribute nothing,
    /// excluded naturally rather than needing an explicit filter downstream.
    func testWidgetOnlyPluginNilControllerContributesNoRows() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let alpha = makeController(name: "Alpha", handler: RecordingHandler(), prefs: prefs, compact: compact)
        alpha.render(output(itemText: "Foo"))

        let aggregated = AppController.aggregateSearchRows([("Alpha", alpha), ("WidgetOnly", nil)])

        XCTAssertEqual(aggregated.pairs.count, 1, "a .widget-surface plugin (nil controller) must contribute no rows")
        XCTAssertEqual(aggregated.pairs.first?.row.item.text, "Foo")
        withExtendedLifetime(alpha) {}
    }

    func testNoPluginsYieldsEmptyRows() {
        let aggregated = AppController.aggregateSearchRows([])
        XCTAssertTrue(aggregated.entries.isEmpty)
        XCTAssertTrue(aggregated.pairs.isEmpty)
    }

    /// The critical routing guarantee: a row from plugin A must fire through
    /// plugin A's handler, never plugin B's — even though both rows are merged
    /// into one flat list for display/search.
    func testActivatingARowFiresOnlyTheOwningPluginsHandler() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let handlerA = RecordingHandler()
        let handlerB = RecordingHandler()
        let alpha = makeController(name: "Alpha", handler: handlerA, prefs: prefs, compact: compact)
        let beta = makeController(name: "Beta", handler: handlerB, prefs: prefs, compact: compact)
        alpha.render(output(itemText: "Foo"))
        beta.render(output(itemText: "Bar"))

        let aggregated = AppController.aggregateSearchRows([("Alpha", alpha), ("Beta", beta)])

        aggregated.pairs.first(where: { $0.row.item.text == "Foo" })?.activate()
        XCTAssertEqual(handlerA.performed.map(\.text), ["Foo"])
        XCTAssertTrue(handlerB.performed.isEmpty, "activating Alpha's row must not fire Beta's handler")

        aggregated.pairs.first(where: { $0.row.item.text == "Bar" })?.activate()
        XCTAssertEqual(handlerB.performed.map(\.text), ["Bar"])
        XCTAssertEqual(handlerA.performed.map(\.text), ["Foo"], "Alpha's handler must not fire again for Beta's row")
        withExtendedLifetime((alpha, beta)) {}
    }

    // MARK: - entries: separator splicing + normalization across plugin boundaries

    func testEntriesInsertsSeparatorBetweenPluginBlocks() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let alpha = makeController(name: "Alpha", handler: RecordingHandler(), prefs: prefs, compact: compact)
        let beta = makeController(name: "Beta", handler: RecordingHandler(), prefs: prefs, compact: compact)
        alpha.render(output(itemText: "Foo"))
        beta.render(output(itemText: "Bar"))

        let aggregated = AppController.aggregateSearchRows([("Alpha", alpha), ("Beta", beta)])

        guard case .action(let foo) = aggregated.entries.first else { return XCTFail("expected Alpha's row first") }
        XCTAssertEqual(foo.item.text, "Foo")
        XCTAssertEqual(aggregated.entries[1], .separator)
        guard case .action(let bar) = aggregated.entries.last else { return XCTFail("expected Beta's row last") }
        XCTAssertEqual(bar.item.text, "Bar")
        XCTAssertEqual(aggregated.entries.count, 3)
        withExtendedLifetime((alpha, beta)) {}
    }

    /// A plugin with a controller but an empty menu contributes no entries of
    /// its own — but the separator unconditionally inserted before its slot
    /// would otherwise double up with the next plugin's, or dangle at the
    /// end. `entries` runs `normalized` over the WHOLE concatenation
    /// specifically to clean this up.
    func testEntriesCollapseSeparatorAroundAnEmptyMiddlePlugin() {
        let prefs = makeCompactPrefs()
        let compact = CompactMenuBarController(attachesStatusItem: false)
        let alpha = makeController(name: "Alpha", handler: RecordingHandler(), prefs: prefs, compact: compact)
        let empty = makeController(name: "Empty", handler: RecordingHandler(), prefs: prefs, compact: compact)
        let beta = makeController(name: "Beta", handler: RecordingHandler(), prefs: prefs, compact: compact)
        alpha.render(output(itemText: "Foo"))
        empty.render(ParsedOutput(titleLines: [TitleLine(text: "x")], body: []))
        beta.render(output(itemText: "Bar"))

        let aggregated = AppController.aggregateSearchRows([("Alpha", alpha), ("Empty", empty), ("Beta", beta)])

        XCTAssertEqual(aggregated.entries.count, 3, "Foo, one separator, Bar — no doubled separator for Empty's contribution-less slot")
        XCTAssertEqual(aggregated.entries[1], .separator)
        withExtendedLifetime((alpha, empty, beta)) {}
    }
}
