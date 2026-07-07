import XCTest
@testable import VeePluginFormat
@testable import VeeWidgetShared

final class WidgetCardParserTests: XCTestCase {
    // MARK: - Per-template round trips

    func testStatCardRoundTrips() throws {
        let json = """
        {"vee_widget":1,"template":"stat","title":"Revenue","symbol":"chart.line.uptrend.xyaxis",
         "tint":"green","value":"$18.2k","caption":"today","detail":"214 orders","status":"ok"}
        """
        let (card, diagnostics) = WidgetCardParser.parse(json)
        XCTAssertEqual(diagnostics, [])
        let expected = WidgetCard(
            template: .stat,
            title: "Revenue",
            symbol: "chart.line.uptrend.xyaxis",
            tint: .named("green"),
            value: "$18.2k",
            caption: "today",
            detail: "214 orders",
            status: .ok
        )
        XCTAssertEqual(card, expected)
    }

    func testGaugeCardRoundTrips() throws {
        let json = """
        {"template":"gauge","title":"Disk","value":"72%","progress":0.72}
        """
        let (card, diagnostics) = WidgetCardParser.parse(json)
        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(card, WidgetCard(template: .gauge, title: "Disk", value: "72%", progress: 0.72))
    }

    func testTrendCardRoundTrips() throws {
        let json = """
        {"template":"trend","title":"Revenue","value":"$18.2k","trend":[12.1,13.4,12.9,15.0,18.2]}
        """
        let (card, diagnostics) = WidgetCardParser.parse(json)
        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(card, WidgetCard(template: .trend, title: "Revenue", value: "$18.2k", trend: [12.1, 13.4, 12.9, 15.0, 18.2]))
    }

    func testListCardRoundTrips() throws {
        let json = """
        {"template":"list","title":"Orders","items":[
          {"label":"Orders","value":"214","symbol":"bag","tint":"blue"},
          {"label":"Refunds","value":"3","symbol":"arrow.uturn.left","tint":"red"}
        ]}
        """
        let (card, diagnostics) = WidgetCardParser.parse(json)
        XCTAssertEqual(diagnostics, [])
        let expected = WidgetCard(template: .list, title: "Orders", items: [
            WidgetCardItem(label: "Orders", value: "214", symbol: "bag", tint: .named("blue")),
            WidgetCardItem(label: "Refunds", value: "3", symbol: "arrow.uturn.left", tint: .named("red"))
        ])
        XCTAssertEqual(card, expected)
    }

    func testBoardCardRoundTrips() throws {
        let json = """
        {"template":"board","title":"KPIs","items":[
          {"label":"Orders","value":"214"},
          {"label":"Refunds","value":"3"}
        ],"actions":[
          {"kind":"refresh","label":"Refresh"},
          {"kind":"href","label":"Open","url":"https://dash.example.com"}
        ]}
        """
        let (card, diagnostics) = WidgetCardParser.parse(json)
        XCTAssertEqual(diagnostics, [])
        let expected = WidgetCard(template: .board, title: "KPIs", items: [
            WidgetCardItem(label: "Orders", value: "214"),
            WidgetCardItem(label: "Refunds", value: "3")
        ], actions: [
            WidgetCardAction(kind: .refresh, label: "Refresh"),
            WidgetCardAction(kind: .href, label: "Open", url: "https://dash.example.com")
        ])
        XCTAssertEqual(card, expected)
    }

    func testShortcutActionRoundTrips() throws {
        let json = """
        {"template":"stat","value":"1","actions":[{"kind":"shortcut","label":"Deploy","name":"Deploy Prod"}]}
        """
        let (card, _) = WidgetCardParser.parse(json)
        XCTAssertEqual(card?.actions, [WidgetCardAction(kind: .shortcut, label: "Deploy", name: "Deploy Prod")])
    }

    // MARK: - Tolerance

    func testUnknownTemplateFallsBackToStatWithDiagnostic() {
        let (card, diagnostics) = WidgetCardParser.parse(#"{"template":"pie","value":"1"}"#)
        XCTAssertEqual(card?.template, .stat)
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.severity, .warning)
        XCTAssertTrue(diagnostics.first?.message.contains("pie") ?? false)
    }

    func testMissingTemplateDefaultsToStatSilently() {
        let (card, diagnostics) = WidgetCardParser.parse(#"{"value":"1"}"#)
        XCTAssertEqual(card?.template, .stat)
        XCTAssertEqual(diagnostics, [])
    }

    func testOutOfRangeProgressIsClamped() {
        let (card, diagnostics) = WidgetCardParser.parse(#"{"template":"gauge","progress":1.4}"#)
        XCTAssertEqual(card?.progress, 1.0)
        XCTAssertEqual(diagnostics.count, 1)

        let (negative, negDiagnostics) = WidgetCardParser.parse(#"{"template":"gauge","progress":-0.2}"#)
        XCTAssertEqual(negative?.progress, 0.0)
        XCTAssertEqual(negDiagnostics.count, 1)
    }

    func testInRangeProgressPassesThroughWithNoDiagnostic() {
        let (card, diagnostics) = WidgetCardParser.parse(#"{"template":"gauge","progress":0.5}"#)
        XCTAssertEqual(card?.progress, 0.5)
        XCTAssertEqual(diagnostics, [])
    }

    // Non-finite `progress`/`trend` values can't be expressed as a JSON
    // literal (the grammar has no NaN/Infinity token, so an out-of-range
    // exponent's overflow behavior is decoder-specific and untestable without
    // a toolchain here) — the `.isFinite` guards in `clampProgress`/
    // `finiteTrend` are defensive parity with `JSONOutputParser`'s existing
    // pattern, not exercised by a literal fixture.

    func testUnknownStatusIsIgnoredWithDiagnostic() {
        let (card, diagnostics) = WidgetCardParser.parse(#"{"template":"stat","status":"critical"}"#)
        XCTAssertNil(card?.status)
        XCTAssertEqual(diagnostics.count, 1)
    }

    func testMalformedJSONYieldsNilAndDiagnostic() {
        let (card, diagnostics) = WidgetCardParser.parse("{not json at all")
        XCTAssertNil(card)
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.severity, .error)
    }

    func testNonObjectJSONYieldsNilAndDiagnostic() {
        for text in ["[1,2,3]", "\"just a string\"", "plain text, not JSON at all"] {
            let (card, diagnostics) = WidgetCardParser.parse(text)
            XCTAssertNil(card, text)
            XCTAssertEqual(diagnostics.count, 1, text)
        }
    }

    func testEmptyOutputYieldsNilWithNoDiagnostic() {
        for text in ["", "   ", "\n\n"] {
            let (card, diagnostics) = WidgetCardParser.parse(text)
            XCTAssertNil(card, text)
            XCTAssertEqual(diagnostics, [], text)
        }
    }

    func testUnknownTopLevelKeysAreIgnored() {
        let (card, diagnostics) = WidgetCardParser.parse(#"{"template":"stat","value":"1","totally_unknown_field":42}"#)
        XCTAssertEqual(card?.value, "1")
        XCTAssertEqual(diagnostics, [])
    }

    func testTintParsesNamedAndHex() {
        let (named, _) = WidgetCardParser.parse(#"{"template":"stat","tint":"green"}"#)
        XCTAssertEqual(named?.tint, .named("green"))

        // Two-# delimiter: the JSON contains `"#` (the quote before the hex
        // color), which would close a single-# raw string early.
        let (hex, _) = WidgetCardParser.parse(##"{"template":"stat","tint":"#ff0000aa"}"##)
        XCTAssertEqual(hex?.tint, .rgba(r: 0xff, g: 0x00, b: 0x00, a: 0xaa))
    }

    // MARK: - href action scheme filtering (matches menu href=/<xbar.abouturl>)

    func testHrefActionWithSafeSchemeIsKept() {
        let (card, diagnostics) = WidgetCardParser.parse(
            #"{"template":"stat","actions":[{"kind":"href","label":"Open","url":"https://dash.example.com"}]}"#
        )
        XCTAssertEqual(card?.actions, [WidgetCardAction(kind: .href, label: "Open", url: "https://dash.example.com")])
        XCTAssertEqual(diagnostics, [])
    }

    func testHrefActionWithUnsafeSchemeIsDropped() {
        for hostile in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,x"] {
            let (card, diagnostics) = WidgetCardParser.parse(
                #"{"template":"stat","actions":[{"kind":"href","label":"Open","url":"\#(hostile)"}]}"#
            )
            XCTAssertEqual(card?.actions, [], hostile)
            XCTAssertEqual(diagnostics.count, 1, hostile)
        }
    }

    func testHrefActionWithMissingOrUnparseableURLIsDropped() {
        let (missingURL, missingDiagnostics) = WidgetCardParser.parse(#"{"template":"stat","actions":[{"kind":"href","label":"Open"}]}"#)
        XCTAssertEqual(missingURL?.actions, [])
        XCTAssertEqual(missingDiagnostics.count, 1)
    }

    /// `refresh`/`shortcut` actions carry no URL, so they pass through
    /// untouched regardless of the href scheme filter.
    func testNonHrefActionsAreUnaffectedBySchemeFilter() {
        let (card, diagnostics) = WidgetCardParser.parse(
            #"{"template":"stat","actions":[{"kind":"refresh","label":"Refresh"},{"kind":"shortcut","label":"Deploy","name":"Deploy Prod"}]}"#
        )
        XCTAssertEqual(card?.actions, [
            WidgetCardAction(kind: .refresh, label: "Refresh"),
            WidgetCardAction(kind: .shortcut, label: "Deploy", name: "Deploy Prod")
        ])
        XCTAssertEqual(diagnostics, [])
    }

    func testRefreshAndStaleAfterDecodeFromSnakeCase() {
        let (card, _) = WidgetCardParser.parse(#"{"template":"stat","refresh_after":900,"stale_after":3600}"#)
        XCTAssertEqual(card?.refreshAfter, 900)
        XCTAssertEqual(card?.staleAfter, 3600)
    }
}
