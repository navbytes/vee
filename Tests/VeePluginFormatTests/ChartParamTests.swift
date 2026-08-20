import XCTest
@testable import VeePluginFormat

/// Covers the Vee-native categorical share charts (`pie=`/`donut=`/
/// `stackedbar=`) and their `chartlabels=`/`chartcolors=` companions, plus the
/// invariants every renderer relies on.
final class ChartParamTests: XCTestCase {
    private func parse(_ line: String) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs)
    }
    private func chart(_ line: String) -> ChartParams? { parse(line).params.swiftbar.chart }

    // MARK: - Shapes

    func testEachShapeParsesTheSameData() {
        for kind in ChartKind.allCases {
            let c = chart("Disk | \(kind.rawValue)=45,30,25")
            XCTAssertEqual(c?.kind, kind, "\(kind.rawValue)= should parse")
            XCTAssertEqual(c?.values, [45, 30, 25])
        }
    }

    func testLastShapeOnALineWins() {
        // Same "last one wins" rule the rest of the parser uses for repeats.
        XCTAssertEqual(chart("x | pie=1,2 stackedbar=3,4")?.kind, .stackedBar)
        XCTAssertEqual(chart("x | pie=1,2 stackedbar=3,4")?.values, [3, 4])
    }

    func testKeysAreCaseInsensitive() {
        XCTAssertEqual(chart("x | StackedBar=1,1")?.kind, .stackedBar)
    }

    // MARK: - Fractions

    func testFractionsAreSharesOfTheTotal() {
        let c = chart("x | pie=45,30,25")
        XCTAssertEqual(c?.fraction(at: 0) ?? 0, 0.45, accuracy: 1e-9)
        XCTAssertEqual(c?.fraction(at: 2) ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertEqual(c?.total, 100)
    }

    func testFractionOutOfRangeIsZeroNotACrash() {
        let c = chart("x | pie=1,1")
        XCTAssertEqual(c?.fraction(at: 9), 0)
        XCTAssertEqual(c?.fraction(at: -1), 0)
    }

    // MARK: - Rejected input

    func testNonNumericTokenRejectsTheWholeSeries() {
        // Matching progress='s strictness: a bad token must not silently chart
        // the tokens that happened to parse.
        let r = parse("x | pie=10,abc,30")
        XCTAssertNil(r.params.swiftbar.chart)
        XCTAssertTrue(r.diagnostics.contains { $0.message.contains("pie=") })
    }

    func testNegativeAndNonFiniteAreRejected() {
        for bad in ["pie=10,-5,30", "pie=nan,1", "donut=inf,2"] {
            let r = parse("x | \(bad)")
            XCTAssertNil(r.params.swiftbar.chart, "\(bad) should not chart")
            XCTAssertFalse(r.diagnostics.isEmpty, "\(bad) should report why")
        }
    }

    func testAllZeroSeriesIsRejected() {
        let r = parse("x | donut=0,0,0")
        XCTAssertNil(r.params.swiftbar.chart)
        XCTAssertTrue(r.diagnostics.contains { $0.message.contains("sum to zero") })
    }

    func testEmptyValueIsRejected() {
        XCTAssertNil(chart("x | pie="))
    }

    func testZeroValuedSegmentIsKeptWhenOthersAreNot() {
        // A legitimate "this category is empty right now" — the series still has
        // a positive total, so it charts.
        let c = chart("x | pie=0,50,50")
        XCTAssertEqual(c?.values, [0, 50, 50])
        XCTAssertEqual(c?.fraction(at: 0), 0)
    }

    // MARK: - Labels

    func testLabelsAreParsedAndTrimmed() {
        let c = chart("x | pie=1,1,1 chartlabels=Docs, Photos ,Apps")
        XCTAssertEqual(c?.label(at: 0), "Docs")
        XCTAssertEqual(c?.label(at: 1), "Photos")
        XCTAssertEqual(c?.label(at: 2), "Apps")
    }

    func testBlankLabelKeepsLaterLabelsOnTheirOwnSegments() {
        let c = chart("x | pie=1,1,1 chartlabels=Docs,,Apps")
        XCTAssertEqual(c?.label(at: 0), "Docs")
        XCTAssertNil(c?.label(at: 1))
        XCTAssertEqual(c?.label(at: 2), "Apps")
    }

    func testExtraLabelsAreDropped() {
        let c = chart("x | pie=1,1 chartlabels=a,b,c,d")
        XCTAssertEqual(c?.labels.count, 2)
    }

    func testLabelsWithoutAChartAreReported() {
        let r = parse("x | chartlabels=a,b")
        XCTAssertNil(r.params.swiftbar.chart)
        XCTAssertTrue(r.diagnostics.contains { $0.message.contains("without pie=") })
    }

    // MARK: - Colors

    func testColorsOverridePaletteSlots() {
        let c = chart("x | pie=1,1 chartcolors=red,#00ff00")
        XCTAssertEqual(c?.color(at: 0), .named("red"))
        XCTAssertEqual(c?.color(at: 1), .rgb(r: 0, g: 0xff, b: 0, a: 255))
    }

    func testMissingColorsFallBackToTheirPaletteSlot() {
        let c = chart("x | pie=1,1,1 chartcolors=red")
        XCTAssertEqual(c?.color(at: 0), .named("red"))
        XCTAssertEqual(c?.color(at: 1), ChartPalette.slot(at: 1))
        XCTAssertEqual(c?.color(at: 2), ChartPalette.slot(at: 2))
    }

    func testColorsStayPositionalAcrossHoles() {
        // The bug a `compactMap` would introduce: dropping the unparseable
        // middle entry would slide `blue` onto segment 2.
        let c = chart("x | pie=1,1,1 chartcolors=red,notacolor,blue")
        XCTAssertEqual(c?.color(at: 0), .named("red"))
        XCTAssertEqual(c?.color(at: 1), ChartPalette.slot(at: 1))
        XCTAssertEqual(c?.color(at: 2), .named("blue"))
    }

    func testBlankColorEntryTakesItsPaletteSlotSilently() {
        let r = parse("x | pie=1,1,1 chartcolors=,,blue")
        XCTAssertEqual(r.params.swiftbar.chart?.color(at: 0), ChartPalette.slot(at: 0))
        XCTAssertEqual(r.params.swiftbar.chart?.color(at: 2), .named("blue"))
        XCTAssertFalse(r.diagnostics.contains { $0.message.contains("chartcolors=") })
    }

    func testUnparseableColorIsReported() {
        let r = parse("x | pie=1,1 chartcolors=red,#zzz")
        XCTAssertTrue(r.diagnostics.contains { $0.message.contains("chartcolors=") })
    }

    // MARK: - Folding

    func testLongSeriesFoldsIntoOtherRatherThanTruncating() {
        // Ten segments: the first seven survive, the last three are summed so
        // the shares still add up to the plugin's own total.
        let r = parse("x | pie=1,2,3,4,5,6,7,8,9,10")
        let c = r.params.swiftbar.chart
        XCTAssertEqual(c?.values.count, ChartParams.maxSegments)
        XCTAssertEqual(c?.values.prefix(7).map { $0 }, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(c?.values.last, 27)          // 8 + 9 + 10
        XCTAssertEqual(c?.total, 55)                // unchanged by folding
        XCTAssertEqual(c?.isFolded, true)
        XCTAssertEqual(c?.label(at: 7), ChartParams.otherLabel)
        XCTAssertEqual(c?.color(at: 7), ChartPalette.other)
        XCTAssertTrue(r.diagnostics.contains { $0.message.contains("folded") })
    }

    func testExactlyMaxSegmentsIsNotFolded() {
        let c = chart("x | pie=1,1,1,1,1,1,1,1")
        XCTAssertEqual(c?.values.count, 8)
        XCTAssertEqual(c?.isFolded, false)
        XCTAssertNil(c?.label(at: 7))
    }

    func testFoldingDropsLabelsAndColorsPastTheKeptSegments() {
        let c = chart("x | pie=1,1,1,1,1,1,1,1,1 chartlabels=a,b,c,d,e,f,g,h,i chartcolors=red,red,red,red,red,red,red,red,red")
        XCTAssertEqual(c?.label(at: 7), ChartParams.otherLabel, "the folded tail is not segment 8's label")
        XCTAssertEqual(c?.color(at: 7), ChartPalette.other)
        XCTAssertEqual(c?.label(at: 6), "g")
    }

    // MARK: - Accessibility

    func testAccessibilitySummaryNamesEverySegment() {
        let c = chart("x | pie=50,25,25 chartlabels=Docs,Photos")
        XCTAssertEqual(c?.accessibilitySummary(), "Docs 50%, Photos 25%, Segment 3 25%")
    }

    // MARK: - Palette

    func testPaletteHasEightNonRepeatingSlots() {
        XCTAssertEqual(ChartPalette.slots.count, ChartParams.maxSegments)
        let light = ChartPalette.slots.map(\.light)
        XCTAssertEqual(Set(light.map { String(describing: $0) }).count, light.count, "slots must not repeat a hue")
    }

    func testPaletteSlotsClampRatherThanCycle() {
        // A ninth segment can never exist (folding caps at 8), but if one ever
        // reached here it must not wrap around onto slot 1's color.
        XCTAssertEqual(ChartPalette.slot(at: 99), ChartPalette.slot(at: 7))
        XCTAssertEqual(ChartPalette.slot(at: -3), ChartPalette.slot(at: 0))
    }

    func testDarkSlotsDifferWhereTheSurfaceDemandsIt() {
        XCTAssertNotEqual(ChartPalette.slot(at: 0, surface: .light), ChartPalette.slot(at: 0, surface: .dark))
    }

    func testPaletteColorIgnoresOverrides() {
        let c = chart("x | pie=1,1 chartcolors=red,red")
        XCTAssertEqual(c?.color(at: 0), .named("red"))
        XCTAssertEqual(c?.paletteColor(at: 0), ChartPalette.slot(at: 0))
    }

    // MARK: - Interaction with other params

    func testChartCoexistsWithAccessoryPlacementAndTooltip() {
        let p = parse("x | donut=1,2 accessory=leading tooltip=hi").params
        XCTAssertEqual(p.swiftbar.chart?.kind, .donut)
        XCTAssertEqual(p.swiftbar.accessory, .leading)
        XCTAssertEqual(p.swiftbar.tooltip, "hi")
    }

    func testChartIsNotReportedAsAnUnknownParam() {
        for key in ["pie", "donut", "stackedbar", "chartlabels", "chartcolors"] {
            let r = parse("x | pie=1,1 \(key)=1,1")
            XCTAssertFalse(
                r.diagnostics.contains { $0.message.contains("unknown parameter") },
                "\(key)= should be a known param"
            )
        }
    }
}
