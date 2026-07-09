import XCTest
import VeeCore
@testable import VeePluginFormat

final class HeaderParserTests: XCTestCase {
    func testBasicMetadata() {
        let src = """
        #!/usr/bin/env bash
        # <xbar.title>Weather</xbar.title>
        # <xbar.version>1.2.0</xbar.version>
        # <xbar.author>Jane Doe</xbar.author>
        # <xbar.author.github>janedoe</xbar.author.github>
        # <xbar.desc>Shows the weather.</xbar.desc>
        # <xbar.dependencies>python,curl</xbar.dependencies>
        # <xbar.abouturl>https://example.com</xbar.abouturl>
        echo "Sunny"
        """
        let m = HeaderParser.parse(source: src)
        XCTAssertEqual(m.title, "Weather")
        XCTAssertEqual(m.version, "1.2.0")
        XCTAssertEqual(m.author, "Jane Doe")
        XCTAssertEqual(m.authorGithub, "janedoe")
        XCTAssertEqual(m.summary, "Shows the weather.")
        XCTAssertEqual(m.dependencies, ["python", "curl"])
        XCTAssertEqual(m.aboutURL, URL(string: "https://example.com"))
    }

    /// Regression: a plugin's declared About URL is scheme-filtered, so the
    /// About dialog's "Open Website" can't open file:// / javascript:.
    func testAboutURLRejectsUnsafeSchemes() {
        for hostile in ["file:///etc/passwd", "javascript:alert(1)"] {
            let m = HeaderParser.parse(source: "# <xbar.abouturl>\(hostile)</xbar.abouturl>\n")
            XCTAssertNil(m.aboutURL, "\(hostile) should be dropped")
        }
        let ok = HeaderParser.parse(source: "# <xbar.abouturl>https://example.com</xbar.abouturl>\n")
        XCTAssertEqual(ok.aboutURL?.absoluteString, "https://example.com")
    }

    func testSwiftBarOptions() {
        let src = """
        # <swiftbar.type>streamable</swiftbar.type>
        # <swiftbar.schedule>0 9 * * *|0 17 * * *</swiftbar.schedule>
        # <swiftbar.runInBash>false</swiftbar.runInBash>
        # <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
        # <swiftbar.environment>[API=https://api.test, MODE=fast]</swiftbar.environment>
        """
        let m = HeaderParser.parse(source: src)
        XCTAssertTrue(m.streamable)
        XCTAssertEqual(m.schedule, ["0 9 * * *", "0 17 * * *"])
        XCTAssertEqual(m.runInBash, false)
        XCTAssertEqual(m.refreshOnOpen, true)
        XCTAssertEqual(m.environment["API"], "https://api.test")
        XCTAssertEqual(m.environment["MODE"], "fast")
    }

    func testHideControlHeaders() {
        let src = """
        # <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
        # <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
        # <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
        # <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
        """
        let m = HeaderParser.parse(source: src)
        XCTAssertTrue(m.hideLastUpdated)
        XCTAssertTrue(m.hideRunInTerminal)
        XCTAssertTrue(m.hideDisablePlugin)
        XCTAssertTrue(m.hideSwiftBar)
    }

    func testVarDeclarations() {
        let src = """
        # <xbar.var>string(API_TOKEN=): Your API token</xbar.var>
        # <xbar.var>number(COUNT=5): How many items</xbar.var>
        # <xbar.var>boolean(VERBOSE=false): Verbose output</xbar.var>
        # <xbar.var>select(MODE=fast): Speed [fast, slow, auto]</xbar.var>
        """
        let m = HeaderParser.parse(source: src)
        XCTAssertEqual(m.vars.count, 4)

        let token = m.vars[0]
        XCTAssertEqual(token.name, "API_TOKEN")
        XCTAssertEqual(token.kind, .string)
        XCTAssertEqual(token.defaultValue, "")
        XCTAssertEqual(token.summary, "Your API token")
        XCTAssertTrue(token.isSecret) // name contains "token"

        XCTAssertEqual(m.vars[1].kind, .number)
        XCTAssertEqual(m.vars[1].defaultValue, "5")
        XCTAssertFalse(m.vars[1].isSecret)

        XCTAssertEqual(m.vars[2].kind, .boolean)

        let select = m.vars[3]
        XCTAssertEqual(select.kind, .select)
        XCTAssertEqual(select.defaultValue, "fast")
        XCTAssertEqual(select.options, ["fast", "slow", "auto"])
    }

    func testVeeFilterOptIn() {
        let on = HeaderParser.parse(source: "# <vee.filter>true</vee.filter>\n")
        XCTAssertTrue(on.filter)
        let off = HeaderParser.parse(source: "# <vee.filter>false</vee.filter>\n")
        XCTAssertFalse(off.filter)
        let absent = HeaderParser.parse(source: "echo hi\n")
        XCTAssertFalse(absent.filter)
    }

    func testVeeShortcutParsedAndIgnoredWhenInvalid() {
        let ok = HeaderParser.parse(source: "# <vee.shortcut>cmd+shift+k</vee.shortcut>\n")
        XCTAssertEqual(ok.shortcut?.keyCode, 0x28)
        XCTAssertEqual(ok.shortcut?.display, "⇧⌘K")
        // A bare key (no modifier) is rejected → no hotkey registered.
        let bad = HeaderParser.parse(source: "# <vee.shortcut>k</vee.shortcut>\n")
        XCTAssertNil(bad.shortcut)
        let absent = HeaderParser.parse(source: "echo hi\n")
        XCTAssertNil(absent.shortcut)
    }

    func testVeeSurfaceParsesEachValueCaseInsensitively() {
        XCTAssertEqual(HeaderParser.parse(source: "# <vee.surface>menu</vee.surface>\n").surface, .menu)
        XCTAssertEqual(HeaderParser.parse(source: "# <vee.surface>both</vee.surface>\n").surface, .both)
        XCTAssertEqual(HeaderParser.parse(source: "# <vee.surface>widget</vee.surface>\n").surface, .widget)
        XCTAssertEqual(HeaderParser.parse(source: "# <vee.surface>WIDGET</vee.surface>\n").surface, .widget)
        XCTAssertEqual(HeaderParser.parse(source: "# <vee.surface>  Both  </vee.surface>\n").surface, .both)
    }

    func testVeeSurfaceUnknownValueFallsBackToMenu() {
        XCTAssertEqual(HeaderParser.parse(source: "# <vee.surface>popover</vee.surface>\n").surface, .menu)
    }

    func testVeeSurfaceAbsentDefaultsToMenu() {
        XCTAssertEqual(HeaderParser.parse(source: "echo hi\n").surface, .menu)
    }

    /// The widget-mode cadence is deliberately *not* a header field — it reuses
    /// the filename interval (see `PluginCoordinator.widgetRefreshInterval`), so
    /// `<vee.widget.interval>` is just an unknown tag that parses to nothing.
    func testVeeWidgetIntervalTagIsIgnored() {
        let m = HeaderParser.parse(source: "# <vee.widget.interval>15m</vee.widget.interval>\n")
        XCTAssertEqual(m.surface, .menu)
        XCTAssertTrue(m.vars.isEmpty)
    }

    func testNoHeaderYieldsEmptyMetadata() {
        let m = HeaderParser.parse(source: "echo hello\n")
        XCTAssertNil(m.title)
        XCTAssertTrue(m.vars.isEmpty)
        XCTAssertFalse(m.streamable)
    }
}
