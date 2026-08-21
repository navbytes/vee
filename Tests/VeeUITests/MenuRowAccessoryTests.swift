import XCTest
@testable import VeeUI
import VeePluginFormat

/// The rich graphic a row carries is chosen by a pure function, so the
/// precedence — the part that must agree with what a click actually opens — is
/// asserted without rendering anything.
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
        guard case .progress(let progress, _) = kind else { return XCTFail("expected a gauge, got \(String(describing: kind))") }
        XCTAssertEqual(progress.fraction, 0.5)
    }

    func testSparklineIsRecognised() {
        let kind = MenuRowAccessory.kind(for: params { $0.sparkline = [1, 2, 3] })
        guard case .sparkline(let values, _) = kind else { return XCTFail("expected a sparkline, got \(String(describing: kind))") }
        XCTAssertEqual(values, [1, 2, 3])
    }

    func testAnEmptySparklineIsNotAnAccessory() {
        XCTAssertNil(MenuRowAccessory.kind(for: params { $0.sparkline = [] }))
    }

    func testChartIsRecognised() {
        let kind = MenuRowAccessory.kind(for: params { $0.swiftbar.chart = chart })
        guard case .chart(let resolved) = kind else { return XCTFail("expected a chart, got \(String(describing: kind))") }
        XCTAssertEqual(resolved.kind, .pie)
    }

    func testControlIsRecognised() {
        let kind = MenuRowAccessory.kind(for: params { $0.control = .toggle(on: true) })
        guard case .control(let control) = kind else { return XCTFail("expected a control, got \(String(describing: kind))") }
        XCTAssertEqual(control, .toggle(on: true))
    }

    /// The precedence must match `AppActionDispatcher`'s dispatch order, so the
    /// graphic a row draws never advertises a different surface than clicking
    /// the row opens.
    func testControlOutranksEveryDisplayOnlyGraphic() {
        let kind = MenuRowAccessory.kind(for: params {
            $0.control = .slider(min: 0, max: 10, value: 5)
            $0.progress = ProgressParams(fraction: 0.5)
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.chart = chart
        })
        guard case .control = kind else { return XCTFail("a control row must draw its control") }
    }

    func testProgressOutranksSparklineAndChart() {
        let kind = MenuRowAccessory.kind(for: params {
            $0.progress = ProgressParams(fraction: 0.5)
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.chart = chart
        })
        guard case .progress = kind else { return XCTFail("expected the gauge to win") }
    }

    func testSparklineOutranksChart() {
        let kind = MenuRowAccessory.kind(for: params {
            $0.sparkline = [1, 2, 3]
            $0.swiftbar.chart = chart
        })
        guard case .sparkline = kind else { return XCTFail("expected the sparkline to win") }
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
}
