import XCTest
@testable import VeeCatalog

/// Stubs URLSession responses so the network-hardening logic in
/// GitHubCatalogClient can be tested without hitting the network.
///
/// URL-aware: the manifest URL (`vee-catalog.json`) gets its own status/body so
/// a store's manifest-probe path is separable from the tree/source path. By
/// default the manifest 404s (as the real xbar catalog does), so `fetchIndex`
/// falls back to the tree.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var manifestStatus = 404
    nonisolated(unsafe) static var manifestBody = Data()

    static func reset() {
        status = 200; body = Data(); manifestStatus = 404; manifestBody = Data()
    }

    // URLProtocol requires these to be `class func` overrides.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class
    override func stopLoading() {}
    override func startLoading() {
        let isManifest = request.url?.lastPathComponent == "vee-catalog.json"
        let status = isManifest ? Self.manifestStatus : Self.status
        let body = isManifest ? Self.manifestBody : Self.body
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class CatalogClientNetworkTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// The built-in xbar store — never probed for a manifest.
    private func makeClient() -> GitHubCatalogClient {
        GitHubCatalogClient(session: session())
    }

    /// A custom (non-built-in) store, so the manifest-probe path is exercised.
    private func makeCustomClient() -> GitHubCatalogClient {
        let config = StoreConfig(
            id: StoreID("acme"), displayName: "Acme", kind: .github,
            apiHost: URL(string: "https://api.github.com"),
            rawHost: URL(string: "https://raw.githubusercontent.com"),
            owner: "acme", repo: "plugins"
        )
        return GitHubCatalogClient(config: config, tokenProvider: nil, session: session())
    }

    func testNon200StatusThrows() async {
        StubURLProtocol.status = 403
        StubURLProtocol.body = Data(#"{"message":"rate limited"}"#.utf8)
        do {
            _ = try await makeClient().fetchIndex()
            XCTFail("expected an httpStatus error")
        } catch let error as CatalogError {
            XCTAssertEqual(error, .httpStatus(403))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testValid200Parses() async throws {
        // No manifest (404) → falls back to the tree convention.
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"tree":[{"path":"System/cpu.5s.sh","type":"blob"}]}"#.utf8)
        let entries = try await makeClient().fetchIndex()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.filename, "cpu.5s.sh")
    }

    func testManifestIsPreferredOverTree() async throws {
        // A present manifest wins; the tree body would parse to a different plugin.
        StubURLProtocol.manifestStatus = 200
        StubURLProtocol.manifestBody = Data(#"{"vee_catalog":1,"plugins":[{"path":"Oncall/pager.1m.py"}]}"#.utf8)
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"tree":[{"path":"System/cpu.5s.sh","type":"blob"}]}"#.utf8)
        let entries = try await makeCustomClient().fetchIndex()
        XCTAssertEqual(entries.map(\.filename), ["pager.1m.py"])
    }

    func testMalformedManifestSurfacesInsteadOfSilentFallback() async {
        StubURLProtocol.manifestStatus = 200
        StubURLProtocol.manifestBody = Data("not json".utf8)
        do {
            _ = try await makeCustomClient().fetchIndex()
            XCTFail("expected the malformed manifest to surface")
        } catch let error as CatalogManifestParser.ManifestError {
            XCTAssertEqual(error, .malformed)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testOversizedSourceThrows() async {
        StubURLProtocol.status = 200
        // 9 MB exceeds the 8 MB source cap.
        StubURLProtocol.body = Data(count: 9 * 1024 * 1024)
        let entry = CatalogEntry(path: "A/x.5s.sh", category: "A", filename: "x.5s.sh", rawURL: URL(string: "https://raw.example/x")!)
        do {
            _ = try await makeClient().fetchSource(entry)
            XCTFail("expected responseTooLarge")
        } catch let error as CatalogError {
            guard case .responseTooLarge = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
