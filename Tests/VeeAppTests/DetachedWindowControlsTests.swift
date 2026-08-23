import XCTest
@testable import VeeApp
import VeeMenu
import VeePluginFormat
import VeeSearch

/// A detached window's structure and its plugin controls, exercised through the
/// `attachesWindows: false` seam so no real `NSWindow` is ever constructed.
@MainActor
final class DetachedWindowControlsTests: XCTestCase {
    private final class SpyHandler: MenuActionHandling {
        func perform(_ item: MenuItem) {}
        func commitControl(_ item: MenuItem, value: Double) {}
    }

    private func manager() -> DetachedPluginWindows { DetachedPluginWindows(attachesWindows: false) }

    private func body(_ titles: [String]) -> [MenuNode] {
        titles.map { title in
            var params = LineParams()
            params.href = URL(string: "https://example.com")
            return .item(MenuItem(text: title, params: params))
        }
    }

    private func branch(_ child: String) -> [MenuNode] {
        var parent = MenuItem(text: "Disks", params: LineParams())
        parent.submenu = body([child])
        return [.item(parent)]
    }

    // MARK: - Structure

    /// A window shows the plugin's structure, so a closed branch hides its
    /// children until it is opened — the same tree the dropdown renders.
    func testAWindowShowsNestingWithBranchesClosed() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: branch("Macintosh HD"), handler: SpyHandler())

        XCTAssertEqual(windows.visibleRowTitles(pluginName: "sysmon"), ["Disks"])
        windows.toggleBranch(pluginName: "sysmon", key: ["Disks"])
        XCTAssertEqual(windows.visibleRowTitles(pluginName: "sysmon"), ["Disks", "Macintosh HD"])
    }

    /// The window exists to be left open, so a refresh must not close what the
    /// user opened.
    func testOpenBranchesSurviveARefresh() {
        let windows = manager()
        windows.show(pluginName: "sysmon", body: branch("Macintosh HD 40%"), handler: SpyHandler())
        windows.toggleBranch(pluginName: "sysmon", key: ["Disks"])

        windows.update(pluginName: "sysmon", body: branch("Macintosh HD 41%"))

        XCTAssertTrue(windows.isBranchExpanded(pluginName: "sysmon", key: ["Disks"]))
        XCTAssertEqual(windows.visibleRowTitles(pluginName: "sysmon"), ["Disks", "Macintosh HD 41%"])
    }

    // MARK: - Controls

    /// Controls are Vee's actions, not the plugin's output. They live in the
    /// window's chrome, so they never appear among the rows a filter searches.
    func testControlsAreNeverRowsAndSoAreNeverFiltered() {
        let windows = manager()
        windows.show(
            pluginName: "sysmon",
            body: body(["CPU 12%"]),
            handler: SpyHandler(),
            controls: PluginWindowControls(onRefresh: {})
        )
        XCTAssertEqual(windows.visibleRowTitles(pluginName: "sysmon"), ["CPU 12%"])
        XCTAssertFalse(
            windows.visibleRowTitles(pluginName: "sysmon").contains { $0.lowercased().contains("refresh") },
            "no control leaked into the plugin's rows"
        )
    }

    /// Refresh from a window runs the controller's own refresh closure — the
    /// same one the dropdown's footer fires, not a second path.
    func testRefreshFromAWindowRunsThePluginsOwnRefresh() {
        let windows = manager()
        var refreshes = 0
        windows.show(
            pluginName: "sysmon",
            body: body(["CPU 12%"]),
            handler: SpyHandler(),
            controls: PluginWindowControls(onRefresh: { refreshes += 1 })
        )
        windows.controls(pluginName: "sysmon")?.onRefresh()
        XCTAssertEqual(refreshes, 1)
    }

    func testEveryControlIsCarriedThrough() {
        let windows = manager()
        var fired: [String] = []
        windows.show(
            pluginName: "sysmon",
            body: body(["CPU 12%"]),
            handler: SpyHandler(),
            controls: PluginWindowControls(
                onRefresh: { fired.append("refresh") },
                onSettings: { fired.append("settings") },
                onAbout: { fired.append("about") },
                onReveal: { fired.append("reveal") },
                onEdit: { fired.append("edit") },
                onDebug: { fired.append("debug") }
            )
        )
        let controls = windows.controls(pluginName: "sysmon")
        controls?.onRefresh()
        controls?.onSettings()
        controls?.onAbout()
        controls?.onReveal()
        controls?.onEdit()
        controls?.onDebug()
        XCTAssertEqual(fired, ["refresh", "settings", "about", "reveal", "edit", "debug"])
    }

    func testControlsAreEvictedWhenTheWindowCloses() {
        let windows = manager()
        windows.show(
            pluginName: "sysmon",
            body: body(["CPU 12%"]),
            handler: SpyHandler(),
            controls: PluginWindowControls(onRefresh: {})
        )
        windows.close(pluginName: "sysmon")
        XCTAssertNil(windows.controls(pluginName: "sysmon"), "no closure outlives its window")
    }
}
