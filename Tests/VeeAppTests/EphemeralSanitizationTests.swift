import XCTest
@testable import VeeApp
import VeePluginFormat

/// `setephemeralplugin` content arrives via a deep link any web page can open, so
/// executable actions must be stripped before it becomes a clickable status item.
final class EphemeralSanitizationTests: XCTestCase {
    private func shellCount(_ output: ParsedOutput) -> Int {
        var count = output.titleLines.filter { $0.params.shell != nil }.count
        func walk(_ nodes: [MenuNode]) {
            for node in nodes {
                if case .item(let item) = node {
                    if item.params.shell != nil { count += 1 }
                    if item.alternate?.params.shell != nil { count += 1 }
                    walk(item.submenu)
                }
            }
        }
        walk(output.body)
        return count
    }

    func testStripsShellFromTitleItemsSubmenusAndAlternates() {
        let content = """
        Status | shell=/bin/rm param1=-rf
        ---
        Do thing | bash=/usr/bin/curl param1=evil.sh
        Nested | shell=/bin/sh
        -- Child | bash=/bin/danger
        Alt | alternate=true shell=/bin/sneaky
        """
        let parsed = OutputParser.parse(content)
        XCTAssertGreaterThan(shellCount(parsed), 0, "fixture should contain shell actions before stripping")

        let stripped = AppController.strippingShellActions(parsed)
        XCTAssertEqual(shellCount(stripped), 0, "all shell/bash actions must be removed")
    }

    /// `AppActionDispatcher.perform` dispatches `shortcut=` to
    /// `/usr/bin/shortcuts run <name>` and `webview=` to a `WKWebView` with JS
    /// enabled. Both are code execution reachable from one click on a row an
    /// attacker put in the menu bar via an ungated deep link, so both must be
    /// stripped alongside `shell=` — everywhere `shell=` is.
    func testStripsShortcutAndWebviewEverywhereShellIsStripped() {
        let content = """
        Status | shortcut=Wipe Disk
        ---
        Run it | shortcut=Backup Now
        Browse | webview=https://evil.example
        Nested | shortcut=Nested Shortcut
        -- Child | webview=https://evil.example/child
        Alt | alternate=true shortcut=Sneaky
        """
        let parsed = OutputParser.parse(content)
        XCTAssertGreaterThan(dispatchableCount(parsed), 0, "fixture should contain actions before stripping")

        let stripped = AppController.strippingShellActions(parsed)
        XCTAssertEqual(dispatchableCount(stripped), 0, "shortcut= and webview= must be removed too")
    }

    private func dispatchableCount(_ output: ParsedOutput) -> Int {
        func isDispatchable(_ params: LineParams) -> Bool {
            params.swiftbar.shortcut != nil || params.swiftbar.webview != nil
        }
        var count = output.titleLines.filter { isDispatchable($0.params) }.count
        func walk(_ nodes: [MenuNode]) {
            for node in nodes {
                if case .item(let item) = node {
                    if isDispatchable(item.params) { count += 1 }
                    if let alternate = item.alternate, isDispatchable(alternate.params) { count += 1 }
                    walk(item.submenu)
                }
            }
        }
        walk(output.body)
        return count
    }

    func testPreservesNonShellContent() {
        let parsed = OutputParser.parse("Hello | color=red\n---\nOpen | href=https://example.com")
        let stripped = AppController.strippingShellActions(parsed)
        XCTAssertEqual(stripped.titleLines.first?.text, "Hello")
        // href (already scheme-filtered) and other params survive.
        if case .item(let item)? = stripped.body.first(where: { if case .item = $0 { return true }; return false }) {
            XCTAssertNotNil(item.params.href)
        }
    }
}
