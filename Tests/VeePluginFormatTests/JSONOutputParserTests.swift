import XCTest
@testable import VeePluginFormat

final class JSONOutputParserTests: XCTestCase {
    private let sample = """
    {"vee":1,
     "title":[{"text":"CPU 12%","color":"green","sfimage":"cpu"}],
     "items":[
       {"text":"Details","href":"https://example.com"},
       {"separator":true},
       {"text":"Sub","submenu":[{"text":"Child","color":"blue"}]}
     ]}
    """

    func testParsesStructuredMenu() throws {
        let out = try XCTUnwrap(JSONOutputParser.parse(sample))
        XCTAssertEqual(out.titleLines.first?.text, "CPU 12%")
        XCTAssertEqual(out.titleLines.first?.params.color, .named("green"))
        XCTAssertEqual(out.titleLines.first?.params.swiftbar.sfimage, "cpu")

        XCTAssertEqual(out.body.count, 3)
        guard case .item(let details) = out.body[0] else { return XCTFail() }
        XCTAssertEqual(details.text, "Details")
        XCTAssertEqual(details.params.href?.absoluteString, "https://example.com")
        guard case .separator = out.body[1] else { return XCTFail("expected separator") }
        guard case .item(let sub) = out.body[2] else { return XCTFail() }
        XCTAssertEqual(sub.submenu.compactMap { if case .item(let i) = $0 { return i.text } else { return nil } }, ["Child"])
    }

    func testReturnsNilForNonJSON() {
        XCTAssertNil(JSONOutputParser.parse("CPU 12%\n---\nplain text"))
    }

    func testReturnsNilForJSONWithoutVeeKey() {
        XCTAssertNil(JSONOutputParser.parse(#"{"title":"not ours"}"#))
    }

    func testParseAutoFallsBackToText() {
        // No "vee" key → text parser handles it.
        let out = OutputParser.parseAuto("Title\n---\nItem")
        XCTAssertEqual(out.titleLines.first?.text, "Title")
        XCTAssertEqual(out.body.count, 1)
    }
}
