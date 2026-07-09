import XCTest
@testable import VeeCatalog

final class CatalogManifestTests: XCTestCase {
    private let rawBase = "https://ghe.acme.corp/raw/platform/vee-plugins/main/"
    private let storeID = StoreID("acme")

    private let manifest = Data("""
    {
      "vee_catalog": 1,
      "name": "Acme Internal Tools",
      "updated": "2026-07-01T00:00:00Z",
      "signing_key": "MCowBQ",
      "plugins": [
        { "path": "Oncall/pager.1m.py", "title": "PagerDuty On-call",
          "min_macos": "26.0", "sha256": "9f2b", "signature": "sig==" },
        { "path": "Deployment/deploy.30s.sh", "category": "Deploy", "deprecated": true }
      ]
    }
    """.utf8)

    func testParsesEntriesWithMetadata() throws {
        let entries = try CatalogManifestParser.parse(manifest, storeID: storeID, rawBase: rawBase)
        XCTAssertEqual(entries.count, 2)

        let pager = try XCTUnwrap(entries.first { $0.filename == "pager.1m.py" })
        XCTAssertEqual(pager.storeID, storeID)
        XCTAssertEqual(pager.category, "Oncall")               // inferred from path
        XCTAssertEqual(pager.manifestTitle, "PagerDuty On-call")
        XCTAssertEqual(pager.declaredSHA256, "9f2b")
        XCTAssertEqual(pager.signature, "sig==")
        XCTAssertEqual(pager.minMacOS, "26.0")
        XCTAssertEqual(pager.rawURL.absoluteString, rawBase + "Oncall/pager.1m.py")
        XCTAssertEqual(pager.lastUpdated, ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))

        let deploy = try XCTUnwrap(entries.first { $0.filename == "deploy.30s.sh" })
        XCTAssertEqual(deploy.category, "Deploy")               // explicit category wins
        XCTAssertTrue(deploy.deprecated)
    }

    func testParsesDeclaredSurface() throws {
        let manifest = Data("""
        {
          "vee_catalog": 1,
          "plugins": [
            { "path": "Dash/revenue.15m.sh", "surface": "widget" },
            { "path": "System/cpu.5s.sh", "surface": "both" },
            { "path": "Net/ping.10s.sh" }
          ]
        }
        """.utf8)
        let entries = try CatalogManifestParser.parse(manifest, storeID: storeID, rawBase: rawBase)
        XCTAssertEqual(entries.first { $0.filename == "revenue.15m.sh" }?.manifestSurface, "widget")
        XCTAssertEqual(entries.first { $0.filename == "cpu.5s.sh" }?.manifestSurface, "both")
        // Absent surface stays nil (zero-config convention).
        XCTAssertNil(entries.first { $0.filename == "ping.10s.sh" }?.manifestSurface)
    }

    func testUnknownVersionRejected() {
        let future = Data(#"{ "vee_catalog": 2, "plugins": [] }"#.utf8)
        XCTAssertThrowsError(try CatalogManifestParser.parse(future, storeID: storeID, rawBase: rawBase)) {
            XCTAssertEqual($0 as? CatalogManifestParser.ManifestError, .unsupportedVersion(2))
        }
    }

    func testMalformedRejected() {
        XCTAssertThrowsError(try CatalogManifestParser.parse(Data("nope".utf8), storeID: storeID, rawBase: rawBase)) {
            XCTAssertEqual($0 as? CatalogManifestParser.ManifestError, .malformed)
        }
    }
}
