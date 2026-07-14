import XCTest
import AppKit
@testable import VeeMenu

/// Covers the selection-highlight helper and VoiceOver accessibility exposure
/// shared by `ProgressMenuItemView`/`SparklineMenuItemView` — the parts of D5/D6
/// not already exercised end-to-end via `MenuBuilderTests` or the render smoke
/// tests.
@MainActor
final class MenuRowAccessibilityAndHighlightTests: XCTestCase {
    // MARK: - menuRowHighlightPath (D6)

    // `NSMenuItem.isHighlighted` is AppKit-managed and read-only — true only
    // while the item is highlighted during live menu tracking (hover/arrow-key
    // focus) — so a unit test can't drive a real `NSMenu` into that state.
    // `menuRowHighlightPath` is the pure function `draw(_:)` calls with that
    // bit, extracted so the decision/geometry stays testable without one; the
    // one-line AppKit glue (`enclosingMenuItem?.isHighlighted`, read at
    // `draw(_:)` time) is verified by inspection instead.
    func testHighlightPathNilWhenNotHighlighted() {
        XCTAssertNil(menuRowHighlightPath(highlighted: false, in: NSRect(x: 0, y: 0, width: 200, height: 22)))
    }

    func testHighlightPathPresentWhenHighlighted() {
        XCTAssertNotNil(menuRowHighlightPath(highlighted: true, in: NSRect(x: 0, y: 0, width: 200, height: 22)))
    }

    func testHighlightPathNilForDegenerateBounds() {
        XCTAssertNil(menuRowHighlightPath(highlighted: true, in: .zero))
    }

    // MARK: - ProgressMenuItemView accessibility (D5)

    func testProgressViewAccessibilityLabelAndValue() {
        let view = ProgressMenuItemView(
            title: NSAttributedString(string: "Budget"), fraction: 0.72,
            fillColor: .controlAccentColor, trackColor: .tertiaryLabelColor, barWidth: 120, barHeight: 6)
        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityLabel(), "Budget")
        XCTAssertEqual(view.accessibilityValue() as? String, "72%")
    }

    func testProgressViewAccessibilityValueRoundsRatherThanTruncates() {
        let view = ProgressMenuItemView(
            title: NSAttributedString(string: "x"), fraction: 0.726,
            fillColor: .controlAccentColor, trackColor: .tertiaryLabelColor, barWidth: 120, barHeight: 6)
        XCTAssertEqual(view.accessibilityValue() as? String, "73%")
    }

    func testProgressViewAccessibilityValueClampsOutOfRangeFraction() {
        let view = ProgressMenuItemView(
            title: NSAttributedString(string: "Over"), fraction: 1.5,
            fillColor: .controlAccentColor, trackColor: .tertiaryLabelColor, barWidth: 120, barHeight: 6)
        XCTAssertEqual(view.accessibilityValue() as? String, "100%")
    }

    // MARK: - SparklineMenuItemView accessibility (D5) + non-finite filtering (D9)

    func testSparklineViewAccessibilityReportsLatestValueAndTrend() {
        let up = SparklineMenuItemView(title: NSAttributedString(string: "Load"), values: [1, 2, 3, 4, 10], lineColor: .controlAccentColor)
        XCTAssertEqual(up.accessibilityLabel(), "Load")
        XCTAssertEqual(up.accessibilityValue() as? String, "10, trending up")

        let down = SparklineMenuItemView(title: NSAttributedString(string: "Load"), values: [10, 4, 1], lineColor: .controlAccentColor)
        XCTAssertEqual(down.accessibilityValue() as? String, "1, trending down")

        let flat = SparklineMenuItemView(title: NSAttributedString(string: "Load"), values: [5, 5, 5], lineColor: .controlAccentColor)
        XCTAssertEqual(flat.accessibilityValue() as? String, "5, flat")
    }

    func testSparklineViewSingleValueAccessibilityHasNoTrend() {
        let view = SparklineMenuItemView(title: NSAttributedString(string: "Load"), values: [42], lineColor: .controlAccentColor)
        XCTAssertEqual(view.accessibilityValue() as? String, "42")
    }

    /// D9: NaN/Inf are filtered on ingest. An all-non-finite series leaves
    /// nothing to plot — reported to VoiceOver as "No data" instead of a
    /// misleading number, and `drawChart` skips drawing entirely (no crash).
    func testSparklineViewFiltersAllNonFiniteAndReportsNoData() {
        let view = SparklineMenuItemView(title: NSAttributedString(string: "Load"), values: [.nan, .infinity, -.infinity], lineColor: .controlAccentColor)
        XCTAssertEqual(view.accessibilityValue() as? String, "No data")
        view.draw(view.bounds) // must not crash with nothing to plot
    }

    /// V2-review S1 regression: the VoiceOver summary runs eagerly in `init`
    /// on plugin-supplied data, and `String(Int(v))` traps on finite values
    /// ≥ ~9.2e18 — `sparkline=1,2,1e19` in a plugin's output must render a
    /// row, not abort the entire app when its menu opens.
    func testSparklineViewSurvivesHugeFiniteValues() {
        let view = SparklineMenuItemView(title: NSAttributedString(string: "Load"), values: [1, 2, 1e19], lineColor: .controlAccentColor)
        XCTAssertEqual(view.accessibilityValue() as? String, "\(String(format: "%.2f", 1e19)), trending up")
        view.draw(view.bounds) // geometry must also survive the magnitude
    }

    /// A NaN mixed into an otherwise-valid series is dropped, not propagated
    /// into the trend/value calculation.
    func testSparklineViewDropsOnlyTheNonFiniteEntries() {
        let view = SparklineMenuItemView(title: NSAttributedString(string: "Load"), values: [1, .nan, 3], lineColor: .controlAccentColor)
        XCTAssertEqual(view.accessibilityValue() as? String, "3, trending up")
    }
}
