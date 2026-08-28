import XCTest
import AppKit
@testable import VeeApp

/// `webvieww=`/`webviewh=` come straight from plugin stdout and used to reach
/// `NSWindow(contentRect:)` unbounded. A window larger than the display puts its
/// own title bar and close button off-screen — a window the user cannot dismiss.
@MainActor
final class WebViewWindowSizeTests: XCTestCase {
    private let screen = NSSize(width: 1440, height: 900)

    func testOversizeRequestIsBoundedByTheScreen() {
        let size = WebViewPresenter.windowSize(width: 99999, height: 99999, screen: screen)
        XCTAssertEqual(size.width, screen.width)
        XCTAssertEqual(size.height, screen.height)
    }

    func testNegativeAndZeroAreRaisedToAUsableMinimum() {
        let size = WebViewPresenter.windowSize(width: -500, height: 0, screen: screen)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testOrdinarySizesPassThroughUnchanged() {
        let size = WebViewPresenter.windowSize(width: 800, height: 600, screen: screen)
        XCTAssertEqual(size, NSSize(width: 800, height: 600))
    }

    func testDefaultsWhenUndeclared() {
        XCTAssertEqual(WebViewPresenter.windowSize(width: nil, height: nil, screen: screen),
                       NSSize(width: 640, height: 480))
    }

    /// NaN would propagate through the window geometry into AppKit.
    func testNonFiniteFallsBackToTheDefault() {
        let size = WebViewPresenter.windowSize(width: .nan, height: .infinity, screen: screen)
        XCTAssertEqual(size, NSSize(width: 640, height: 480))
    }
}
