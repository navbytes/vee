import XCTest
@testable import VeePluginFormat

final class VeeColorTests: XCTestCase {
    func testNamed() {
        XCTAssertEqual(VeeColor.parse("Red"), .named("red"))
        XCTAssertEqual(VeeColor.parse("labelColor"), .named("labelcolor"))
    }
    func testHexForms() {
        XCTAssertEqual(VeeColor.parse("#f00"), .rgb(r: 255, g: 0, b: 0, a: 255))
        XCTAssertEqual(VeeColor.parse("#00ff00"), .rgb(r: 0, g: 255, b: 0, a: 255))
        XCTAssertEqual(VeeColor.parse("#0000ff80"), .rgb(r: 0, g: 0, b: 255, a: 128))
    }
    func testInvalid() {
        XCTAssertNil(VeeColor.parse(""))
        XCTAssertNil(VeeColor.parse("#12"))
        XCTAssertNil(VeeColor.parse("#gggggg"))
    }
}

final class LineParserTests: XCTestCase {
    func testNoParams() {
        let (text, pairs, _) = LineParser.splitTextAndParams("Just a title")
        XCTAssertEqual(text, "Just a title")
        XCTAssertTrue(pairs.isEmpty)
    }

    func testBareValueWithoutQuotes() {
        let (pairs, _) = LineParser.parseParams("color=red size=12")
        XCTAssertEqual(pairs.map(\.key), ["color", "size"])
        XCTAssertEqual(pairs.map(\.value), ["red", "12"])
    }

    func testEscapedQuoteInsideValue() {
        let (pairs, _) = LineParser.parseParams(#"tooltip="say \"hi\"""#)
        XCTAssertEqual(pairs.first?.value, #"say "hi""#)
    }

    func testMissingValueDiagnosed() {
        let (_, diags) = LineParser.parseParams("color")
        XCTAssertTrue(diags.contains { $0.message.contains("no value") })
    }
}

final class AnsiTests: XCTestCase {
    func testStripsWhenNoStyleRequested() {
        XCTAssertEqual(Ansi.strip("\u{1B}[1mbold\u{1B}[0m"), "bold")
    }
    func testBoldAndColor() {
        let (plain, runs) = Ansi.parse("\u{1B}[1;34mhi\u{1B}[0m")
        XCTAssertEqual(plain, "hi")
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].bold)
        XCTAssertEqual(runs[0].foreground, .named("blue"))
    }
    func testTruecolor() {
        let (_, runs) = Ansi.parse("\u{1B}[38;2;10;20;30mx\u{1B}[0m")
        XCTAssertEqual(runs.first?.foreground, .rgb(r: 10, g: 20, b: 30, a: 255))
    }
    func testPlainTextUnchanged() {
        let (plain, runs) = Ansi.parse("no escapes here")
        XCTAssertEqual(plain, "no escapes here")
        XCTAssertTrue(runs.isEmpty)
    }

    func test256Foreground() {
        // xterm 46 → (0,255,0) in the 6×6×6 cube.
        let (_, runs) = Ansi.parse("\u{1B}[38;5;46mX\u{1B}[0m")
        XCTAssertEqual(runs.first?.foreground, .rgb(r: 0, g: 255, b: 0, a: 255))
    }

    func testBackground256() {
        // xterm 196 → (255,0,0).
        let (_, runs) = Ansi.parse("\u{1B}[48;5;196mX\u{1B}[0m")
        XCTAssertEqual(runs.first?.background, .rgb(r: 255, g: 0, b: 0, a: 255))
    }

    func testBasicBackground() {
        let (_, runs) = Ansi.parse("\u{1B}[41mX\u{1B}[0m")
        XCTAssertEqual(runs.first?.background, .named("red"))
    }
}
