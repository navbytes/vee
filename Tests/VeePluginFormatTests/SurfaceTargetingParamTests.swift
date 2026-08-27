import XCTest
@testable import VeePluginFormat

/// The two targeting params — `visibleOn=` (where a row exists) and
/// `searchable=` (whether a query can reach it) — at the parse layer, in both
/// authoring formats. What `MenuTree` then *does* with them is
/// `MenuTreeTests`'s business; this file only pins what the parsers record and
/// what they say when a declaration is unreadable.
final class SurfaceTargetingParamTests: XCTestCase {
    private func parse(_ line: String) -> (params: LineParams, diagnostics: [ParseDiagnostic]) {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs)
    }

    private func warnings(_ diagnostics: [ParseDiagnostic]) -> [String] {
        diagnostics.filter { $0.severity == .warning }.map(\.message)
    }

    // MARK: - visibleOn=

    func testACommaListBecomesTheSetOfSurfaces() {
        XCTAssertEqual(parse("Row | visibleOn=menu,window").params.swiftbar.visibleOn, [.menu, .window])
    }

    func testSurfacesAreCaseAndSpaceInsensitive() {
        XCTAssertEqual(parse("Row | visibleOn=\" Menu , CLI \"").params.swiftbar.visibleOn, [.menu, .cli])
    }

    func testAbsentIsNilWhichMeansEverySurface() {
        let params = parse("Row | color=red").params
        XCTAssertNil(params.swiftbar.visibleOn)
        for surface in MenuSurface.allCases {
            XCTAssertTrue(surface.shows(params), "\(surface) shows an untargeted row")
        }
    }

    /// Ignored, not fatal, and never silent — the parser's standing posture.
    func testAnUnknownSurfaceIsReportedAndDropped() {
        let (params, diagnostics) = parse("Row | visibleOn=menu,widget")
        XCTAssertEqual(params.swiftbar.visibleOn, [.menu])
        XCTAssertTrue(
            warnings(diagnostics).contains { $0.contains("visibleOn=") && $0.contains("widget") },
            "the dropped value is named"
        )
    }

    /// `widget` is deliberately not a surface: body rows never reach it.
    func testWidgetIsNotASurface() {
        XCTAssertNil(MenuSurface(rawValue: "widget"))
    }

    /// Hiding takes a whole subtree with it, so a declaration nobody can read is
    /// worth less than the row it would delete.
    func testADeclarationOfOnlyUnknownValuesLeavesTheRowVisibleEverywhere() {
        let (params, diagnostics) = parse("Row | visibleOn=widget,dock")
        XCTAssertNil(params.swiftbar.visibleOn)
        XCTAssertTrue(MenuSurface.menu.shows(params))
        XCTAssertTrue(
            warnings(diagnostics).contains { $0.contains("stays visible everywhere") },
            "the fallback itself is reported, not just the two bad values"
        )
    }

    func testAnEmptyDeclarationIsTreatedAsAbsent() {
        let (params, diagnostics) = parse("Row | visibleOn=")
        XCTAssertNil(params.swiftbar.visibleOn)
        XCTAssertTrue(warnings(diagnostics).isEmpty, "nothing was named, so nothing was dropped")
    }

    // MARK: - searchable=

    func testSearchableFalseIsRecorded() {
        XCTAssertEqual(parse("Row | searchable=false").params.swiftbar.searchable, false)
    }

    func testSearchableTruthyTokensMatchTheOtherBooleans() {
        for value in ["true", "1", "yes"] {
            XCTAssertEqual(parse("Row | searchable=\(value)").params.swiftbar.searchable, true, "searchable=\(value)")
        }
    }

    func testSearchableAbsentIsNil() {
        XCTAssertNil(parse("Row | color=red").params.swiftbar.searchable)
    }

    // MARK: - The dropdown= alias

    func testDropdownFalseAloneHidesTheRowOnEverySurface() {
        let params = parse("Row | dropdown=false").params
        for surface in MenuSurface.allCases {
            XCTAssertFalse(surface.shows(params), "\(surface) hides a dropdown=false row")
        }
    }

    func testVisibleOnWinsOverDropdownAndTheConflictIsReported() {
        let (params, diagnostics) = parse("Row | dropdown=false visibleOn=search")
        XCTAssertTrue(MenuSurface.search.shows(params), "the visibleOn list wins outright")
        XCTAssertFalse(MenuSurface.menu.shows(params))
        XCTAssertTrue(warnings(diagnostics).contains { $0.contains("visibleOn= wins") })
    }

    /// The discarded declaration leaves nothing behind: `dropdown=` is back in
    /// charge, so there is no conflict to report either.
    func testAnUnreadableVisibleOnDoesNotOverrideDropdown() {
        let (params, diagnostics) = parse("Row | dropdown=false visibleOn=widget")
        XCTAssertFalse(MenuSurface.menu.shows(params))
        XCTAssertFalse(warnings(diagnostics).contains { $0.contains("visibleOn= wins") })
    }

    // MARK: - The linter's key set

    func testBothKeysAreRecognisedByTheLinter() {
        XCTAssertTrue(LineParameterKeys.isRecognized("visibleOn"))
        XCTAssertTrue(LineParameterKeys.isRecognized("searchable"))
    }

    // MARK: - JSON, with identical semantics

    private func jsonItem(_ fields: String) -> (item: MenuItem, diagnostics: [ParseDiagnostic]) {
        guard let out = JSONOutputParser.parse("{\"vee\":1,\"items\":[{\"text\":\"Row\",\(fields)}]}"),
              case .item(let item)? = out.body.first else {
            fatalError("the fixture must parse as one item")
        }
        return (item, out.diagnostics)
    }

    func testJSONSpellsTheSameDeclarations() {
        let (item, _) = jsonItem("\"visibleOn\":[\"menu\",\"window\"],\"searchable\":false")
        XCTAssertEqual(item.params.swiftbar.visibleOn, [.menu, .window])
        XCTAssertEqual(item.params.swiftbar.searchable, false)
    }

    func testJSONDegradesOnUnknownSurfacesTheSameWay() {
        let (item, diagnostics) = jsonItem("\"visibleOn\":[\"menu\",\"widget\"]")
        XCTAssertEqual(item.params.swiftbar.visibleOn, [.menu])
        XCTAssertTrue(warnings(diagnostics).contains { $0.contains("widget") })

        let (allUnknown, fallbackDiagnostics) = jsonItem("\"visibleOn\":[\"widget\"]")
        XCTAssertNil(allUnknown.params.swiftbar.visibleOn)
        XCTAssertTrue(warnings(fallbackDiagnostics).contains { $0.contains("stays visible everywhere") })
    }

    func testJSONWithNoDeclarationTargetsNothing() {
        let (item, _) = jsonItem("\"color\":\"red\"")
        XCTAssertNil(item.params.swiftbar.visibleOn)
        XCTAssertNil(item.params.swiftbar.searchable)
    }
}
