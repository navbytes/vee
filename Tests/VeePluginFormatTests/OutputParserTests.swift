import XCTest
@testable import VeePluginFormat

final class OutputParserTests: XCTestCase {
    func testTitleOnlyNoBody() {
        let out = OutputParser.parse("CPU 12%")
        XCTAssertEqual(out.titleLines.map(\.text), ["CPU 12%"])
        XCTAssertTrue(out.body.isEmpty)
    }

    func testMultipleTitleLinesCycle() {
        let out = OutputParser.parse("Line 1\nLine 2\n---\nBody")
        XCTAssertEqual(out.titleLines.map(\.text), ["Line 1", "Line 2"])
        XCTAssertEqual(out.body.items.map(\.text), ["Body"])
    }

    func testSectionSplitOnFirstSeparator() {
        let out = OutputParser.parse("Title\n---\nA\n---\nB")
        XCTAssertEqual(out.titleLines.map(\.text), ["Title"])
        // Second `---` becomes a separator inside the body.
        XCTAssertEqual(out.body.count, 3)
        XCTAssertEqual(out.body[0].item?.text, "A")
        XCTAssertTrue(out.body[1].isSeparator)
        XCTAssertEqual(out.body[2].item?.text, "B")
    }

    func testNestedSubmenusByDashDepth() {
        let src = """
        Title
        ---
        Top
        --Sub A
        --Sub B
        ----Deep
        Another
        """
        let out = OutputParser.parse(src)
        let top = out.body.items
        XCTAssertEqual(top.map(\.text), ["Top", "Another"])
        let subs = top[0].submenu.items
        XCTAssertEqual(subs.map(\.text), ["Sub A", "Sub B"])
        XCTAssertEqual(subs[1].submenu.items.map(\.text), ["Deep"])
    }

    func testSeparatorInsideSubmenu() {
        let src = """
        Title
        ---
        Top
        --Sub A
        -----
        --Sub B
        """
        let out = OutputParser.parse(src)
        let subs = out.body.items[0].submenu
        XCTAssertEqual(subs.count, 3)
        XCTAssertEqual(subs[0].item?.text, "Sub A")
        XCTAssertTrue(subs[1].isSeparator)
        XCTAssertEqual(subs[2].item?.text, "Sub B")
    }

    func testDepthJumpIsClamped() {
        // A depth-2 line with no depth-1 parent clamps to available depth.
        let out = OutputParser.parse("Title\n---\nTop\n----TooDeep")
        let top = out.body.items
        XCTAssertEqual(top[0].submenu.items.map(\.text), ["TooDeep"])
        XCTAssertTrue(out.diagnostics.contains { $0.message.contains("depth jumped") })
    }

    func testParamsParsedAndTextTrimmed() {
        let out = OutputParser.parse("Title\n---\nBuild | color=red size=14 href=https://example.com")
        let item = out.body.items[0]
        XCTAssertEqual(item.text, "Build")
        XCTAssertEqual(item.params.color, .named("red"))
        XCTAssertEqual(item.params.size, 14)
        XCTAssertEqual(item.params.href, URL(string: "https://example.com"))
    }

    func testQuotedParamWithSpacesAndEquals() {
        let out = OutputParser.parse(#"Title\#n---\#nRun | bash="/usr/bin/say" param1="hello world" tooltip="a=b|c""#)
        let item = out.body.items[0]
        XCTAssertEqual(item.params.shell?.launchPath, "/usr/bin/say")
        XCTAssertEqual(item.params.shell?.arguments, ["hello world"])
        XCTAssertEqual(item.params.swiftbar.tooltip, "a=b|c")
    }

    func testShellWithMultipleOrderedParams() {
        let out = OutputParser.parse("Title\n---\nGo | shell=/bin/echo param2=second param1=first terminal=true")
        let shell = out.body.items[0].params.shell
        XCTAssertEqual(shell?.arguments, ["first", "second"])
        XCTAssertEqual(shell?.openInTerminal, true)
    }

    func testAlternateAttachesToPreviousItem() {
        let src = """
        Title
        ---
        Open
        Open in background | alternate=true
        """
        let out = OutputParser.parse(src)
        XCTAssertEqual(out.body.items.count, 1)
        XCTAssertEqual(out.body.items[0].text, "Open")
        XCTAssertEqual(out.body.items[0].alternate?.text, "Open in background")
    }

    func testEmojize() {
        let out = OutputParser.parse("Title\n---\nBuild passed :white_check_mark:")
        XCTAssertEqual(out.body.items[0].text, "Build passed ✅")
    }

    func testEmojizeDisabled() {
        let out = OutputParser.parse("Title\n---\nLiteral :rocket: | emojize=false")
        XCTAssertEqual(out.body.items[0].text, "Literal :rocket:")
    }

    func testAnsiColorProducesRuns() {
        let out = OutputParser.parse("Title\n---\n\u{1B}[31mERR\u{1B}[0M ok".replacingOccurrences(of: "0M", with: "0m"))
        let item = out.body.items[0]
        XCTAssertEqual(item.text, "ERR ok")
        XCTAssertEqual(item.ansiRuns.count, 1)
        XCTAssertEqual(item.ansiRuns[0].range, 0..<3)
        XCTAssertEqual(item.ansiRuns[0].foreground, .named("red"))
    }

    func testUnknownParamKeptAndDiagnosed() {
        let out = OutputParser.parse("Title\n---\nX | frobnicate=yes")
        XCTAssertEqual(out.body.items[0].params.unknown["frobnicate"], "yes")
        XCTAssertTrue(out.diagnostics.contains { $0.message.contains("unknown parameter") })
    }

    func testBlankLinesIgnoredInBody() {
        let out = OutputParser.parse("Title\n---\nA\n\n\nB")
        XCTAssertEqual(out.body.items.map(\.text), ["A", "B"])
    }
}
