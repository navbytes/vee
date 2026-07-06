import XCTest
@testable import VeePluginFormat

final class URLSchemeTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testSafeToOpenBlocksDangerousSchemes() {
        for blocked in ["file:///Users/me/.ssh/id_rsa", "javascript:alert(1)", "data:text/html,<h1>x", "vbscript:x", "blob:https://x/y"] {
            XCTAssertFalse(URLScheme.isSafeToOpen(url(blocked)), "\(blocked) should be blocked")
        }
    }

    func testSafeToOpenAllowsWebMailAndCustomAppSchemes() {
        // Compatibility: custom app deep links (shortcuts:, things:, etc.) still open.
        for ok in ["https://example.com", "http://example.com/x", "mailto:a@b.com", "shortcuts://run-shortcut?name=X", "things:///add?title=Y"] {
            XCTAssertTrue(URLScheme.isSafeToOpen(url(ok)), "\(ok) should be allowed")
        }
    }

    func testIsWebURLIsHTTPOnly() {
        XCTAssertTrue(URLScheme.isWebURL(url("https://example.com")))
        XCTAssertTrue(URLScheme.isWebURL(url("http://example.com")))
        for notWeb in ["file:///etc/passwd", "mailto:a@b.com", "shortcuts://x", "ftp://host/x"] {
            XCTAssertFalse(URLScheme.isWebURL(url(notWeb)), "\(notWeb) is not a web URL")
        }
    }

    func testParserDropsUnsafeHrefKeepsSafe() {
        let (_, pairs, _) = LineParser.splitTextAndParams("Open | href=file:///etc/passwd")
        XCTAssertNil(LineParser.mapParams(pairs).params.href)
        let (_, safePairs, _) = LineParser.splitTextAndParams("Open | href=https://example.com")
        XCTAssertEqual(LineParser.mapParams(safePairs).params.href?.absoluteString, "https://example.com")
    }

    func testParserRestrictsWebviewToHTTP() {
        let (_, pairs, _) = LineParser.splitTextAndParams("Open | webview=file:///etc/passwd")
        XCTAssertNil(LineParser.mapParams(pairs).params.swiftbar.webview)
        let (_, okPairs, _) = LineParser.splitTextAndParams("Open | webview=https://example.com")
        XCTAssertEqual(LineParser.mapParams(okPairs).params.swiftbar.webview?.absoluteString, "https://example.com")
    }

    func testJSONHrefIsSchemeFiltered() throws {
        let out = try XCTUnwrap(JSONOutputParser.parse(#"{"vee":1,"items":[{"text":"x","href":"file:///etc/passwd"}]}"#))
        guard case .item(let i) = out.body[0] else { return XCTFail("expected item") }
        XCTAssertNil(i.params.href)
    }
}
