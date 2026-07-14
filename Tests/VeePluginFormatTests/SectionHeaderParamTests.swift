import XCTest
@testable import VeePluginFormat

/// Covers the Vee-native `header=` line param — a first-class section-header
/// row, as opposed to the `<vee.*>`/`<xbar.*>` plugin metadata tags covered by
/// `HeaderParserTests`.
final class SectionHeaderParamTests: XCTestCase {
    private func params(_ line: String) -> LineParams {
        let (_, pairs, _) = LineParser.splitTextAndParams(line)
        return LineParser.mapParams(pairs).params
    }

    func testTrueFromTruthyTokens() {
        for value in ["true", "1", "yes"] {
            XCTAssertEqual(params("Section | header=\(value)").swiftbar.header, true, "header=\(value)")
        }
    }

    func testFalseFromOtherTokens() {
        XCTAssertEqual(params("Section | header=false").swiftbar.header, false)
    }

    func testAbsentIsNil() {
        XCTAssertNil(params("Plain | color=red").swiftbar.header)
    }

    /// A header line's other params still parse (MenuBuilder is what ignores
    /// them at render time) — the parser itself doesn't special-case `header=`
    /// against other keys.
    func testOtherParamsStillParseAlongsideHeader() {
        let p = params("Section | header=true color=red href=https://example.com")
        XCTAssertEqual(p.swiftbar.header, true)
        XCTAssertEqual(p.color, .named("red"))
        XCTAssertNotNil(p.href)
    }
}
