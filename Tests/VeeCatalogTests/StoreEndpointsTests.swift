import XCTest
@testable import VeeCatalog

/// Locks the built-in xbar store to the exact URLs Vee used before custom stores
/// existed (regression), and covers endpoint derivation for the other kinds.
final class StoreEndpointsTests: XCTestCase {
    private let samplePath = "System/CPU/cpu.5s.sh"

    // MARK: - Built-in xbar reproduces the original literals

    func testXbarTreeURLIsUnchanged() {
        let e = StoreEndpoints(BuiltInStores.xbar)
        XCTAssertEqual(
            e.treeURL?.absoluteString,
            "https://api.github.com/repos/matryer/xbar-plugins/git/trees/main?recursive=1"
        )
    }

    func testXbarRawBaseIsUnchanged() {
        let e = StoreEndpoints(BuiltInStores.xbar)
        XCTAssertEqual(e.rawBase, "https://raw.githubusercontent.com/matryer/xbar-plugins/main/")
    }

    func testXbarRawURLIsUnchanged() {
        let e = StoreEndpoints(BuiltInStores.xbar)
        XCTAssertEqual(
            e.rawURL(path: samplePath)?.absoluteString,
            "https://raw.githubusercontent.com/matryer/xbar-plugins/main/System/CPU/cpu.5s.sh"
        )
    }

    func testXbarCommitsURLIsUnchanged() {
        let e = StoreEndpoints(BuiltInStores.xbar)
        XCTAssertEqual(
            e.commitsURL(path: samplePath)?.absoluteString,
            "https://api.github.com/repos/matryer/xbar-plugins/commits?path=System/CPU/cpu.5s.sh&per_page=1"
        )
    }

    func testXbarManifestURL() {
        let e = StoreEndpoints(BuiltInStores.xbar)
        XCTAssertEqual(
            e.manifestURL?.absoluteString,
            "https://raw.githubusercontent.com/matryer/xbar-plugins/main/vee-catalog.json"
        )
    }

    // MARK: - GitHub Enterprise

    func testEnterpriseHostsAreHonored() {
        let config = StoreConfig(
            id: StoreID("acme"),
            displayName: "Acme",
            kind: .githubEnterprise,
            apiHost: URL(string: "https://ghe.acme.corp/api/v3"),
            rawHost: URL(string: "https://ghe.acme.corp/raw"),
            owner: "platform",
            repo: "vee-plugins",
            ref: "release"
        )
        let e = StoreEndpoints(config)
        XCTAssertEqual(e.treeURL?.absoluteString, "https://ghe.acme.corp/api/v3/repos/platform/vee-plugins/git/trees/release?recursive=1")
        XCTAssertEqual(e.rawBase, "https://ghe.acme.corp/raw/platform/vee-plugins/release/")
    }

    // MARK: - Static HTTP and local mirrors (no git API)

    func testHTTPStoreHasNoGitEndpoints() {
        let config = StoreConfig(
            id: StoreID("static"),
            displayName: "Static",
            kind: .http,
            baseURL: URL(string: "https://store.acme.corp/vee/")
        )
        let e = StoreEndpoints(config)
        XCTAssertNil(e.treeURL)
        XCTAssertNil(e.commitsURL(path: samplePath))
        // Trailing slash on the host is normalized, not doubled.
        XCTAssertEqual(e.rawBase, "https://store.acme.corp/vee/")
        XCTAssertEqual(e.manifestURL?.absoluteString, "https://store.acme.corp/vee/vee-catalog.json")
    }

    func testLocalFileStore() {
        let config = StoreConfig(
            id: StoreID("mirror"),
            displayName: "Mirror",
            kind: .local,
            baseURL: URL(string: "file:///opt/vee/store")
        )
        let e = StoreEndpoints(config)
        XCTAssertNil(e.treeURL)
        XCTAssertEqual(e.rawURL(path: "Oncall/pager.1m.py")?.absoluteString, "file:///opt/vee/store/Oncall/pager.1m.py")
        XCTAssertEqual(e.manifestURL?.absoluteString, "file:///opt/vee/store/vee-catalog.json")
    }
}

/// The store dimension flows through the tree parser and disambiguates entries.
final class CatalogParserStoreTests: XCTestCase {
    private let treeJSON = Data("""
    {"tree":[{"path":"System/CPU/cpu.5s.sh","type":"blob"}]}
    """.utf8)

    func testDefaultParseKeepsXbarStoreAndBase() throws {
        let entry = try XCTUnwrap(CatalogParser.parse(treeJSON: treeJSON).first)
        XCTAssertEqual(entry.storeID, BuiltInStores.xbarID)
        XCTAssertEqual(entry.rawURL.absoluteString, "https://raw.githubusercontent.com/matryer/xbar-plugins/main/System/CPU/cpu.5s.sh")
        XCTAssertEqual(entry.id, "com.vee.store.xbar#System/CPU/cpu.5s.sh")
    }

    func testCustomStoreBaseAndIDFlowThrough() throws {
        let entry = try XCTUnwrap(
            CatalogParser.parse(treeJSON: treeJSON, repoBase: "https://ghe.acme.corp/raw/platform/vee-plugins/main/", storeID: StoreID("acme")).first
        )
        XCTAssertEqual(entry.storeID, StoreID("acme"))
        XCTAssertEqual(entry.rawURL.absoluteString, "https://ghe.acme.corp/raw/platform/vee-plugins/main/System/CPU/cpu.5s.sh")
        XCTAssertEqual(entry.id, "acme#System/CPU/cpu.5s.sh")
    }
}
