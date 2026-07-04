import XCTest
@testable import VeeApp

final class URLActionRouterTests: XCTestCase {
    private func parse(_ string: String) -> URLAction {
        URLActionRouter.parse(URL(string: string)!)
    }

    func testRefreshAll() {
        XCTAssertEqual(parse("swiftbar://refreshallplugins"), .refreshAll)
        XCTAssertEqual(parse("vee://refreshall"), .refreshAll)
    }

    func testRefreshPluginByName() {
        XCTAssertEqual(parse("swiftbar://refreshplugin?name=cpu.5s.sh"), .refreshPlugin(name: "cpu.5s.sh"))
        XCTAssertEqual(parse("vee://refreshplugin?path=weather.1m.py"), .refreshPlugin(name: "weather.1m.py"))
    }

    func testEnableDisableToggle() {
        XCTAssertEqual(parse("swiftbar://enableplugin?name=x"), .enablePlugin(name: "x"))
        XCTAssertEqual(parse("swiftbar://disableplugin?name=x"), .disablePlugin(name: "x"))
        XCTAssertEqual(parse("swiftbar://toggleplugin?name=x"), .togglePlugin(name: "x"))
    }

    func testNotify() {
        XCTAssertEqual(
            parse("swiftbar://notify?title=Hi&subtitle=Sub&body=There&href=https://example.com"),
            .notify(title: "Hi", subtitle: "Sub", body: "There", href: URL(string: "https://example.com"))
        )
        XCTAssertEqual(parse("swiftbar://notify?body=Only"), .notify(title: "", subtitle: "", body: "Only", href: nil))
    }

    func testUnknownAndWrongScheme() {
        XCTAssertEqual(parse("https://example.com"), .unknown)
        XCTAssertEqual(parse("swiftbar://bogusaction"), .unknown)
    }
}
