import XCTest
@testable import VeePluginFormat
@testable import VeeWidgetShared

/// Covers the `layout` tree path in `WidgetCardParser`: a clean tree round-trips,
/// and every guardrail (depth/node/text/sparkline caps, numeric clamps, unknown
/// types) degrades to a sanitized tree + diagnostic — never a throw. These are
/// the Part-B hostile-payload cases: the parser runs app-side and writes the
/// snapshot the extension re-reads, so the tree must be bounded *here*.
final class WidgetCardLayoutTests: XCTestCase {
    // MARK: - Round trip

    func testCleanLayoutTreeParsesWithNoDiagnostics() {
        let json = """
        {"vee_widget":1,"layout":{
          "type":"vstack","spacing":6,"align":"leading","children":[
            {"type":"hstack","spacing":5,"children":[
              {"type":"image","symbol":"cpu","style":{"tint":"blue"}},
              {"type":"text","text":"CPU","style":{"font":{"size":"caption","weight":"semibold"},"tint":"secondary"}},
              {"type":"spacer"}
            ]},
            {"type":"text","text":"38%","style":{"font":{"size":"title","design":"rounded"},"monospaced_digit":true,"min_scale":0.6}},
            {"type":"gauge","value":0.38,"gauge_style":"circular","style":{"tint":"green"}}
          ]
        }}
        """
        let (card, diagnostics) = WidgetCardParser.parse(json)
        XCTAssertEqual(diagnostics, [])
        let layout = card?.layout
        XCTAssertEqual(layout?.type, "vstack")
        XCTAssertEqual(layout?.children?.count, 3)
        XCTAssertEqual(layout?.children?[0].children?.map(\.type), ["image", "text", "spacer"])
        XCTAssertEqual(layout?.children?[2].value, 0.38)
        XCTAssertEqual(layout?.children?[2].gaugeStyle, "circular")
    }

    func testLayoutWithoutTemplateStillDefaultsTemplateToStat() {
        // A pure-layout card need not declare `template`; the parser defaults it
        // (as it does for any card) so downstream code always has one.
        let (card, diagnostics) = WidgetCardParser.parse(#"{"vee_widget":1,"layout":{"type":"text","text":"hi"}}"#)
        XCTAssertEqual(card?.template, .stat)
        XCTAssertEqual(card?.layout?.text, "hi")
        XCTAssertEqual(diagnostics, [])
    }

    func testLayoutAndPresetFieldsCoexist() {
        let (card, _) = WidgetCardParser.parse(#"{"template":"gauge","value":"72%","layout":{"type":"text","text":"x"}}"#)
        XCTAssertEqual(card?.template, .gauge)
        XCTAssertEqual(card?.value, "72%")
        XCTAssertEqual(card?.layout?.type, "text")
    }

    func testNoLayoutKeyLeavesLayoutNil() {
        let (card, _) = WidgetCardParser.parse(#"{"template":"stat","value":"1"}"#)
        XCTAssertNil(card?.layout)
    }

    // MARK: - Depth cap

    func testDeeplyNestedLayoutIsCappedWithDiagnostic() {
        // 20 nested vstacks; the parser prunes children past depth 8.
        var json = #"{"type":"text","text":"deep"}"#
        for _ in 0..<20 { json = #"{"type":"vstack","children":[\#(json)]}"# }
        let (card, diagnostics) = WidgetCardParser.parse(#"{"layout":\#(json)}"#)

        // Walk to the deepest surviving node; it must bottom out at the cap.
        var depth = 0
        var node = card?.layout
        while let n = node, let child = n.children?.first { node = child; depth += 1 }
        XCTAssertLessThanOrEqual(depth, 8)
        XCTAssertTrue(diagnostics.contains { $0.message.contains("deep") || $0.message.contains("nested") })
    }

    // MARK: - Node-count cap

    func testTooManyNodesAreCappedWithDiagnostic() {
        let children = Array(repeating: #"{"type":"text","text":"x"}"#, count: 200).joined(separator: ",")
        let (card, diagnostics) = WidgetCardParser.parse(#"{"layout":{"type":"vstack","children":[\#(children)]}}"#)
        // Total node count (root + surviving children) must not exceed the cap.
        func count(_ n: WidgetNode?) -> Int {
            guard let n else { return 0 }
            return 1 + (n.children ?? []).reduce(0) { $0 + count($1) }
        }
        XCTAssertLessThanOrEqual(count(card?.layout), 64)
        XCTAssertTrue(diagnostics.contains { $0.message.contains("nodes") })
    }

    // MARK: - Text length cap

    func testOverlongTextIsTruncatedWithDiagnostic() {
        let long = String(repeating: "a", count: 1000)
        let (card, diagnostics) = WidgetCardParser.parse(#"{"layout":{"type":"text","text":"\#(long)"}}"#)
        XCTAssertEqual(card?.layout?.text?.count, 512)
        XCTAssertTrue(diagnostics.contains { $0.message.contains("text") })
    }

    // MARK: - Sparkline

    func testSparklineIsCapped() {
        let many = (0..<400).map { String($0) }.joined(separator: ",")
        let (card, diagnostics) = WidgetCardParser.parse(#"{"layout":{"type":"sparkline","values":[\#(many)]}}"#)
        XCTAssertEqual(card?.layout?.values?.count, 256)
        XCTAssertTrue(diagnostics.contains { $0.message.contains("sparkline") })
    }

    // The sanitizer also drops non-finite sparkline/gauge values (`.isFinite`
    // guards mirroring `finiteTrend`/`clampProgress`), but — as the existing
    // WidgetCardParserTests already notes — a non-finite value can't be written
    // as a JSON literal: JSON has no NaN/Infinity token, and an overflowing
    // exponent like `1e400` makes JSONDecoder *throw* before the sanitizer runs
    // (the whole card degrades to a "not a JSON object" diagnostic). So those
    // guards are defensive parity, not exercised by a literal fixture here.

    // MARK: - Gauge value clamp

    func testGaugeValueClamped() {
        let (over, _) = WidgetCardParser.parse(#"{"layout":{"type":"gauge","value":1.4}}"#)
        XCTAssertEqual(over?.layout?.value, 1.0)

        let (under, _) = WidgetCardParser.parse(#"{"layout":{"type":"gauge","value":-0.5}}"#)
        XCTAssertEqual(under?.layout?.value, 0.0)
    }

    // MARK: - Style clamps

    func testStyleNumericValuesAreClamped() {
        let json = """
        {"layout":{"type":"text","text":"x","style":{
          "font":{"point_size":400},"padding":999,"line_limit":99,"min_scale":0.05
        }}}
        """
        let (card, _) = WidgetCardParser.parse(json)
        let style = card?.layout?.style
        XCTAssertEqual(style?.font?.pointSize, 96)
        XCTAssertEqual(style?.padding, 64)
        XCTAssertEqual(style?.lineLimit, 20)
        XCTAssertEqual(style?.minScale, 0.3)
    }

    func testGridColumnsClamped() {
        let (card, _) = WidgetCardParser.parse(#"{"layout":{"type":"grid","columns":9,"children":[]}}"#)
        XCTAssertEqual(card?.layout?.columns, 4)
    }

    // MARK: - Unknown types / forward compatibility

    func testUnknownNodeTypeYieldsDiagnosticButKeepsNode() {
        let (card, diagnostics) = WidgetCardParser.parse(#"{"layout":{"type":"canvas","text":"x"}}"#)
        XCTAssertEqual(card?.layout?.type, "canvas")
        XCTAssertTrue(diagnostics.contains { $0.message.contains("canvas") })
    }

    func testUnknownStyleAndNodeKeysAreIgnored() {
        let (card, diagnostics) = WidgetCardParser.parse(
            #"{"layout":{"type":"text","text":"x","future_field":1,"style":{"future_style":2,"tint":"red"}}}"#
        )
        XCTAssertEqual(card?.layout?.style?.tint, .named("red"))
        XCTAssertEqual(diagnostics, [])
    }
}
