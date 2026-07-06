import XCTest
@testable import VeeCatalog

/// Stubs URLSession responses so the network-hardening logic in
/// GitHubCatalogClient can be tested without hitting the network.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class CatalogClientNetworkTests: XCTestCase {
    private func makeClient() -> GitHubCatalogClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return GitHubCatalogClient(session: URLSession(configuration: config))
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
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data(#"{"tree":[{"path":"System/cpu.5s.sh","type":"blob"}]}"#.utf8)
        let entries = try await makeClient().fetchIndex()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.filename, "cpu.5s.sh")
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
