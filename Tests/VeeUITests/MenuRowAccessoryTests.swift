import XCTest
@testable import VeeUI
import VeePluginFormat

/// The rich graphic a row carries is chosen by a pure function, so the
/// precedence — the part that must agree with what a click actually opens — is
/// asserted without rendering anything.
///
/// Display-graphic precedence itself now lives in `MenuTree.accessory` and is
/// covered by `MenuTreeTests`; what this suite pins is the part that is
/// genuinely this surface's own: a live control is drawn in place here, because
/// a window can host one where an `NSMenu` row cannot.
final class MenuRowAccessoryTests: XCTestCase {
    private func params(_ configure: (inout LineParams) -> Void) -> LineParams {
        var params = LineParams()
        configure(&params)
        return params
    }

    private let chart = ChartParams(kind: .pie, values: [1, 2, 3])

    func testAPlainRowCarriesNoAccessory() {
        XCTAssertNil(MenuRowAccessory.kind(for: params { $0.href = URL(string: "https://example.com") }))
    }

    func testProgressIsRecognised() {
        let kind = MenuRowAccessory.kind(for: params { $0.progress = ProgressParams(fraction: 0.5) })
        guard case .display(.progress(let progress, _)) = kind else {
            return XCTFail("expected a gauge, got \(String(describing: kind))")
        }
        XCTAssertEqual(progress.fraction, 0.5)
    }

    func testSparklineIsRecognised() {
        let kind = MenuRowAccessory.kind(for: params { $0.sparkline = [1, 2, 3] })
        guard case .display(.sparkline(let values, _, _)) = kind else {
            return XCTFail("expected a sparkline, got \(String(describing: kind))")
        }
        XCTAssertEqual(values, [1, 2, 3])
    }

    func testAnEmptySparklineIsNotAnAccessory() {
        XCTAssertNil(MenuRowAccessory.kind(for: params { $0.sparkline = [] }))
    }

    func testChartIsRecognised() {
        let kind = MenuRowAccessory.kind(for: params { $0.swiftbar.chart = chart })
        guard case .display(.chart(let resolved)) = kind else {
            return XCTFail("expected a chart, got \(String(describing: kind))")
        }
        XCTAssertEqual(resolved.kind, .pie)
    }

    func testControlIsRecognised() {
        let kind = MenuRowAccessory.kind(for: params { $0.control = .toggle(on: true) })
        guard case .control(let control) = kind else {
            return XCTFail("expected a control, got \(String(describing: kind))")
        }
        XCTAssertEqual(control, .toggle(on: true))
    }

    /// A live control is drawn in place of the row's display graphic **on this
    /// surface only**. The AppKit dropdown cannot host one, so it draws the
    /// display graphic and opens the control on click instead — the two
    /// surfaces still act on the same thing.
    func testControlIsDrawnInPlaceOfAnyDisplayGraphic() {
        let kind = MenuRowAccessory.kind(for: params {
            $0.control = .slider(min: 0, max: 10, value: 5)
            $0.progress = ProgressParams(fraction: 0.5)
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.chart = chart
        })
        guard case .control = kind else { return XCTFail("a control row must draw its control") }
    }

    /// Display-graphic precedence is not decided here — it is read from the
    /// shared model, so this asserts the delegation rather than a second copy
    /// of the rule.
    func testDisplayGraphicPrecedenceComesFromTheSharedModel() {
        let declared = params {
            $0.progress = ProgressParams(fraction: 0.5)
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.chart = chart
        }
        XCTAssertEqual(MenuRowAccessory.kind(for: declared), MenuTree.accessory(for: declared).map(MenuRowAccessory.Kind.display))
    }

    /// `sparklinecolor=`/`sparklinew=`/`sparklineh=` reach this row. They used
    /// to be dropped here while the AppKit row honoured them, so the same
    /// series drew at a different size and colour on the two surfaces.
    func testSparklineStyleReachesTheRow() {
        let kind = MenuRowAccessory.kind(for: params {
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.sparklineStyle = SparklineStyle(width: 140, height: 24, color: .named("teal"))
        })
        guard case .display(.sparkline(_, let style, _)) = kind else {
            return XCTFail("expected a sparkline, got \(String(describing: kind))")
        }
        XCTAssertEqual(style.effectiveWidth, 140)
        XCTAssertEqual(style.effectiveHeight, 24)
        XCTAssertEqual(style.color, .named("teal"))
    }

    /// The gauge's default dimensions live in the format layer precisely so the
    /// AppKit menu row and the SwiftUI window row measure the same bar.
    func testGaugeDefaultsComeFromTheSharedSource() {
        let declared = ProgressParams(fraction: 0.5, width: 200, height: 10)
        XCTAssertEqual(declared.effectiveWidth, 200)
        XCTAssertEqual(declared.effectiveHeight, 10)

        let bare = ProgressParams(fraction: 0.5)
        XCTAssertEqual(bare.effectiveWidth, ProgressParams.defaultWidth)
        XCTAssertEqual(bare.effectiveHeight, ProgressParams.defaultHeight)
    }

    /// A bare sparkline measures the shared default on this surface too — it
    /// used to be hardcoded to a different number here.
    func testSparklineDefaultsComeFromTheSharedSource() {
        let bare = SparklineStyle()
        XCTAssertEqual(bare.effectiveWidth, SparklineStyle.defaultWidth)
        XCTAssertEqual(bare.effectiveHeight, SparklineStyle.defaultHeight)
    }
}
