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
            .notify(title: "Hi", subtitle: "Sub", body: "There", href: URL(string: "https://example.com"), pluginID: nil)
        )
        XCTAssertEqual(parse("swiftbar://notify?body=Only"), .notify(title: "", subtitle: "", body: "Only", href: nil, pluginID: nil))
    }

    func testNotifyCarriesPluginID() {
        XCTAssertEqual(
            parse("swiftbar://notify?plugin=cpu.5s.sh&body=High"),
            .notify(title: "", subtitle: "", body: "High", href: nil, pluginID: "cpu.5s.sh")
        )
        // An empty plugin param is treated as absent (no plugin context).
        XCTAssertEqual(
            parse("swiftbar://notify?plugin=&body=Hi"),
            .notify(title: "", subtitle: "", body: "Hi", href: nil, pluginID: nil)
        )
    }

    func testAddPlugin() {
        XCTAssertEqual(
            parse("swiftbar://addplugin?src=https://example.com/x.5m.sh"),
            .addPlugin(src: URL(string: "https://example.com/x.5m.sh")!)
        )
        // Missing/invalid src is not actionable.
        XCTAssertEqual(parse("swiftbar://addplugin"), .unknown)
    }

    func testSetEphemeralPlugin() {
        XCTAssertEqual(
            parse("swiftbar://setephemeralplugin?name=build&content=Done&exitafter=5"),
            .setEphemeralPlugin(name: "build", content: "Done", exitAfter: 5)
        )
        XCTAssertEqual(
            parse("swiftbar://setephemeralplugin?content=Hi"),
            .setEphemeralPlugin(name: "", content: "Hi", exitAfter: nil)
        )
    }

    func testUnknownAndWrongScheme() {
        XCTAssertEqual(parse("https://example.com"), .unknown)
        XCTAssertEqual(parse("swiftbar://bogusaction"), .unknown)
    }
}
