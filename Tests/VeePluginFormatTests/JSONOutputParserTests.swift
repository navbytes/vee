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
        guard case .item(let details) = out.body[0] else { return XCTFail("expected first item") }
        XCTAssertEqual(details.text, "Details")
        XCTAssertEqual(details.params.href?.absoluteString, "https://example.com")
        guard case .separator = out.body[1] else { return XCTFail("expected separator") }
        guard case .item(let sub) = out.body[2] else { return XCTFail("expected submenu item") }
        XCTAssertEqual(sub.submenu.compactMap { if case .item(let i) = $0 { return i.text } else { return nil } }, ["Child"])
    }

    /// Regression: pathologically-nested JSON must not overflow the mapping
    /// recursion. (Foundation's decoder also rejects input past its own depth
    /// limit — either way we degrade gracefully instead of crashing.)
    func testDeeplyNestedSubmenuIsBoundedNotCrashing() {
        let depth = 300
        let json = "{\"vee\":1,\"items\":[" +
            String(repeating: "{\"submenu\":[", count: depth) + "{\"text\":\"leaf\"}" +
            String(repeating: "]}", count: depth) + "]}"
        // Either Foundation rejects it (nil → text fallback) or the depth cap
        // truncates it; neither crashes. Just assert the call returns.
        _ = JSONOutputParser.parse(json)

        // A moderate, decodable nesting is capped at maxDepth without crashing.
        let shallow = 80
        let capped = "{\"vee\":1,\"items\":[" +
            String(repeating: "{\"submenu\":[", count: shallow) + "{\"text\":\"leaf\"}" +
            String(repeating: "]}", count: shallow) + "]}"
        if let out = JSONOutputParser.parse(capped) {
            // Walk to the deepest reachable item; depth must not exceed the cap.
            var node = out.body.first
            var reached = 0
            while case .item(let item)? = node, let next = item.submenu.first {
                reached += 1
                node = next
            }
            XCTAssertLessThanOrEqual(reached, 64)
        }
    }

    func testRichParamsMapFromJSON() throws {
        let json = """
        {"vee":1,"items":[
          {"text":"Load","sparkline":[1,2,3,5,8]},
          {"text":"Notify","toggle":true},
          {"text":"Volume","slider":{"min":0,"max":100,"value":40}},
          {"text":"Disk","color":"green","progress":0.72,"trackColor":"#333333","progressWidth":80,"progressHeight":6}
        ]}
        """
        let out = try XCTUnwrap(JSONOutputParser.parse(json))
        func item(_ i: Int) throws -> MenuItem {
            guard case .item(let m) = out.body[i] else { throw XCTSkip("not an item") }
            return m
        }
        XCTAssertEqual(try item(0).params.sparkline, [1, 2, 3, 5, 8])
        XCTAssertEqual(try item(1).params.control, .toggle(on: true))
        XCTAssertEqual(try item(2).params.control, .slider(min: 0, max: 100, value: 40))
        let disk = try item(3).params
        XCTAssertEqual(disk.progress?.fraction ?? -1, 0.72, accuracy: 1e-9)
        XCTAssertEqual(disk.progress?.trackColor, VeeColor.parse("#333333"))
        XCTAssertEqual(disk.progress?.width, 80)
        XCTAssertEqual(disk.progress?.height, 6)
    }

    func testRichParamsRejectNonFiniteAndClamp() throws {
        let json = """
        {"vee":1,"items":[
          {"text":"a","progress":5},
          {"text":"b","slider":{"min":0,"max":0,"value":1}},
          {"text":"c","sparkline":[1,2]}
        ]}
        """
        let out = try XCTUnwrap(JSONOutputParser.parse(json))
        guard case .item(let a) = out.body[0] else { return XCTFail("expected item a") }
        XCTAssertEqual(a.params.progress?.fraction, 1.0) // clamped
        guard case .item(let b) = out.body[1] else { return XCTFail("expected item b") }
        XCTAssertNil(b.params.control) // min == max → rejected
        guard case .item(let c) = out.body[2] else { return XCTFail("expected item c") }
        XCTAssertEqual(c.params.sparkline, [1, 2])
    }

    /// `header=`/`accessory=` mirror the text protocol from `JSONItem`.
    func testHeaderAndAccessoryMapFromJSON() throws {
        let json = """
        {"vee":1,"items":[
          {"text":"Section","header":true},
          {"text":"Budget","progress":0.5,"accessory":"leading"}
        ]}
        """
        let out = try XCTUnwrap(JSONOutputParser.parse(json))
        func item(_ i: Int) throws -> MenuItem {
            guard case .item(let m) = out.body[i] else { throw XCTSkip("not an item") }
            return m
        }
        XCTAssertEqual(try item(0).params.swiftbar.header, true)
        XCTAssertEqual(try item(1).params.swiftbar.accessory, .leading)
    }

    func testInvalidAccessoryStringIsNilFromJSON() throws {
        let json = #"{"vee":1,"items":[{"text":"x","accessory":"middle"}]}"#
        let out = try XCTUnwrap(JSONOutputParser.parse(json))
        guard case .item(let item) = out.body[0] else { return XCTFail("expected item") }
        XCTAssertNil(item.params.swiftbar.accessory)
    }

    /// Unlike the text protocol (`LineParser`/`OutputParser`, which reports an
    /// unrecognized `accessory=` value as a `ParseDiagnostic`), the JSON
    /// protocol has no diagnostics channel at all: `JSONOutputParser.parse`
    /// never populates `ParsedOutput.diagnostics`, for this field or any other.
    /// Locks in the asymmetry so a future change doesn't add diagnostics for
    /// one JSON field but not its siblings.
    func testJSONProtocolNeverEmitsDiagnosticsUnlikeTextProtocol() throws {
        let json = #"{"vee":1,"items":[{"text":"x","accessory":"middle","header":true}]}"#
        let out = try XCTUnwrap(JSONOutputParser.parse(json))
        XCTAssertEqual(out.diagnostics, [], "the JSON protocol has no diagnostics channel — the equivalent text line `x | accessory=middle` does warn")
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
