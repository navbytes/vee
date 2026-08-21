import XCTest
@testable import VeeApp
@testable import VeeCLI
import VeePluginFormat

/// The contract between `vee dev --push` and the app that receives it.
///
/// `PushTarget` builds a `vee://setephemeralplugin` URL in `VeeCLI`;
/// `URLActionRouter` parses it in `VeeApp`. Nothing else links the two modules,
/// so a rename of a query parameter on either side would break `--push` with no
/// compile error and no failing test. This closes that seam by running a real
/// menu through both halves.
final class DevPushRoundTripTests: XCTestCase {
    private func route(_ urlString: String) -> URLAction {
        guard let url = URL(string: urlString) else { return .unknown }
        return URLActionRouter.parse(url)
    }

    /// A menu using the characters that would break a naive encoder.
    func testAPushedMenuArrivesAtTheRouterByteForByte() throws {
        let menu = """
        CPU 42% & rising | color=red sfimage=cpu
        ---
        Item #1 | href=https://x.test/a?b=c+d
        Nested | color=#ff8800
        -- Child | tooltip="a b"
        """
        let target = PushTarget(path: "/tmp/plugins/cpu.10s.sh")
        let urlString = try XCTUnwrap(PushTarget.url(key: target.key, content: menu, exitAfter: PushTarget.safetyNetExpiry))

        guard case .setEphemeralPlugin(let name, let content, let exitAfter) = route(urlString) else {
            return XCTFail("expected setEphemeralPlugin, got \(route(urlString))")
        }
        XCTAssertEqual(name, "dev:cpu.10s.sh")
        XCTAssertEqual(content, menu, "the menu must survive encode → route unchanged")
        XCTAssertEqual(exitAfter, Double(PushTarget.safetyNetExpiry))
    }

    /// What the router hands the app must parse back into the same menu the
    /// author saw in their terminal.
    func testRoutedContentParsesIntoTheSameMenu() throws {
        let menu = "Build ✅ | color=green\n---\nOpen log | href=https://ci.test/log\nRetry | bash=/usr/bin/make param1=retry\n"
        let urlString = try XCTUnwrap(PushTarget.url(key: "dev:ci.sh", content: menu, exitAfter: nil))
        guard case .setEphemeralPlugin(_, let content, _) = route(urlString) else {
            return XCTFail("expected setEphemeralPlugin")
        }

        let direct = OutputParser.parse(menu)
        let viaURL = OutputParser.parse(content)
        XCTAssertEqual(direct, viaURL, "a round trip through the URL must not change the parsed menu")
    }

    /// The limitation `vee dev --push` warns about, asserted rather than assumed:
    /// the app defangs ephemeral content, so a previewed `bash=` row is visible
    /// but inert. `PushTarget.containsShellAction` is what decides whether the
    /// loop prints that warning, so the two must agree.
    func testShellActionsAreStrippedByTheAppAndTheLoopWarnsAboutIt() throws {
        let menu = "Status | shell=/bin/rm\n---\nRun | bash=/usr/bin/curl\n-- Deep | shell=/bin/sh\n"
        let urlString = try XCTUnwrap(PushTarget.url(key: "dev:x.sh", content: menu, exitAfter: nil))
        guard case .setEphemeralPlugin(_, let content, _) = route(urlString) else {
            return XCTFail("expected setEphemeralPlugin")
        }

        let parsed = OutputParser.parse(content)
        XCTAssertTrue(PushTarget.containsShellAction(parsed), "the loop must detect that a warning is warranted")

        let stripped = AppController.strippingShellActions(parsed)
        XCTAssertFalse(PushTarget.containsShellAction(stripped), "the app must defang every shell action it renders")
    }

    /// Teardown has to be recognisable to the router too, or a preview would
    /// outlive the loop that made it.
    func testTeardownUrlRoutesToAnExpiringEmptyItem() throws {
        let urlString = try XCTUnwrap(PushTarget.url(key: "dev:cpu.10s.sh", content: "", exitAfter: 1))
        guard case .setEphemeralPlugin(let name, let content, let exitAfter) = route(urlString) else {
            return XCTFail("expected setEphemeralPlugin")
        }
        XCTAssertEqual(name, "dev:cpu.10s.sh")
        XCTAssertTrue(content.isEmpty)
        XCTAssertEqual(exitAfter, 1)
    }
}
