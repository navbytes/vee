import XCTest
@testable import VeeWidgetShared

/// The `WidgetNode` layout tree is the escape hatch alongside the five preset
/// templates (see `docs/design/widget-surface-contract.md` §"Layout tree").
/// These tests pin the wire shape: a node decodes from the same compact JSON a
/// plugin prints, unknown keys are ignored (forward-compatible), and the tree
/// round-trips through `Codable` so the app can carry it in the snapshot.
final class WidgetNodeTests: XCTestCase {
    private func decode(_ json: String) throws -> WidgetNode {
        try JSONDecoder().decode(WidgetNode.self, from: Data(json.utf8))
    }

    func testLeafTextNodeDecodes() throws {
        let node = try decode(#"{"type":"text","text":"CPU"}"#)
        XCTAssertEqual(node.type, "text")
        XCTAssertEqual(node.text, "CPU")
        XCTAssertNil(node.children)
    }

    func testContainerWithChildrenDecodes() throws {
        let node = try decode("""
        {"type":"hstack","spacing":5,"align":"center","children":[
          {"type":"image","symbol":"cpu"},
          {"type":"text","text":"CPU"},
          {"type":"spacer"}
        ]}
        """)
        XCTAssertEqual(node.type, "hstack")
        XCTAssertEqual(node.spacing, 5)
        XCTAssertEqual(node.align, "center")
        XCTAssertEqual(node.children?.count, 3)
        XCTAssertEqual(node.children?.map(\.type), ["image", "text", "spacer"])
        XCTAssertEqual(node.children?[0].symbol, "cpu")
    }

    func testGaugeAndSparklineFieldsDecode() throws {
        let gauge = try decode(#"{"type":"gauge","value":0.72,"gauge_style":"circular"}"#)
        XCTAssertEqual(gauge.value, 0.72)
        XCTAssertEqual(gauge.gaugeStyle, "circular")

        let spark = try decode(#"{"type":"sparkline","values":[1,2,3]}"#)
        XCTAssertEqual(spark.values, [1, 2, 3])
    }

    func testStyleDecodesIncludingPressureTestModifiers() throws {
        let node = try decode("""
        {"type":"text","text":"$18.2k","style":{
          "font":{"size":"title","weight":"semibold","design":"rounded"},
          "tint":"green","align":"center","padding":4,"line_limit":2,
          "monospaced_digit":true,"min_scale":0.6,"fill":true
        }}
        """)
        let style = try XCTUnwrap(node.style)
        XCTAssertEqual(style.font?.size, "title")
        XCTAssertEqual(style.font?.weight, "semibold")
        XCTAssertEqual(style.font?.design, "rounded")
        XCTAssertEqual(style.tint, .named("green"))
        XCTAssertEqual(style.align, "center")
        XCTAssertEqual(style.padding, 4)
        XCTAssertEqual(style.lineLimit, 2)
        XCTAssertEqual(style.monospacedDigit, true)
        XCTAssertEqual(style.minScale, 0.6)
        XCTAssertEqual(style.fill, true)
    }

    func testNumericFontSizeDecodes() throws {
        let node = try decode(#"{"type":"text","text":"42","style":{"font":{"point_size":48}}}"#)
        XCTAssertEqual(node.style?.font?.pointSize, 48)
        XCTAssertNil(node.style?.font?.size)
    }

    func testFamiliesAllowListDecodes() throws {
        let node = try decode(#"{"type":"text","text":"detail","families":["large"]}"#)
        XCTAssertEqual(node.families, ["large"])
    }

    func testGridColumnsDecode() throws {
        let node = try decode(#"{"type":"grid","columns":2,"children":[]}"#)
        XCTAssertEqual(node.type, "grid")
        XCTAssertEqual(node.columns, 2)
        XCTAssertEqual(node.children, [])
    }

    func testUnknownNodeKeysAreIgnored() throws {
        let node = try decode(#"{"type":"text","text":"x","totally_unknown":42,"nested":{"a":1}}"#)
        XCTAssertEqual(node.type, "text")
        XCTAssertEqual(node.text, "x")
    }

    func testUnknownTypeStringDecodesVerbatim() throws {
        // An unknown node type is not rejected at decode — the parser degrades
        // it to a diagnostic, so the raw string must survive decoding.
        let node = try decode(#"{"type":"canvas"}"#)
        XCTAssertEqual(node.type, "canvas")
    }

    func testCardCarriesOptionalLayout() throws {
        // `WidgetCard` is decoded directly only from app-written snapshots,
        // which always encode `template`; the parser owns defaulting it when a
        // plugin omits it (see `WidgetCardParserTests`).
        let card = try JSONDecoder().decode(WidgetCard.self, from: Data("""
        {"template":"stat","layout":{"type":"vstack","children":[{"type":"text","text":"hi"}]}}
        """.utf8))
        XCTAssertEqual(card.layout?.type, "vstack")
        XCTAssertEqual(card.layout?.children?.first?.text, "hi")
    }

    func testCardEncodesLayoutRoundTrip() throws {
        let card = WidgetCard(template: .stat, layout: WidgetNode(type: "vstack", children: [
            WidgetNode(type: "text", text: "hi")
        ]))
        let data = try JSONEncoder().encode(card)
        let redecoded = try JSONDecoder().decode(WidgetCard.self, from: data)
        XCTAssertEqual(card, redecoded)
    }

    func testCardWithoutLayoutHasNilLayout() throws {
        let card = try JSONDecoder().decode(WidgetCard.self, from: Data(#"{"template":"stat","value":"1"}"#.utf8))
        XCTAssertNil(card.layout)
        XCTAssertEqual(card.template, .stat)
    }

    func testNodeRoundTripsThroughCodable() throws {
        let json = #"{"type":"vstack","spacing":6,"children":[{"type":"text","text":"CPU","style":{"tint":"blue"}}]}"#
        let node = try decode(json)
        let reencoded = try JSONEncoder().encode(node)
        let redecoded = try JSONDecoder().decode(WidgetNode.self, from: reencoded)
        XCTAssertEqual(node, redecoded)
    }
}
