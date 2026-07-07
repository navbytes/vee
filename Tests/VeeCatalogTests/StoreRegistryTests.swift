import XCTest
@testable import VeeCatalog

final class StoreRegistryTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var registry: StoreRegistry!

    override func setUp() {
        super.setUp()
        suiteName = "vee.storeregistry.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        registry = StoreRegistry(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func userStore(_ id: String, enabled: Bool = true) -> StoreConfig {
        StoreConfig(id: StoreID(id), displayName: id, kind: .github,
                    apiHost: URL(string: "https://api.github.com"),
                    rawHost: URL(string: "https://raw.githubusercontent.com"),
                    owner: "acme", repo: id)
    }

    // MARK: - Baseline

    func testEmptyRegistryHasOnlyBuiltInXbar() {
        let stores = registry.stores()
        XCTAssertEqual(stores.map(\.id), [BuiltInStores.xbarID])
        XCTAssertTrue(stores[0].isEnabled)
        XCTAssertTrue(stores[0].isBuiltIn)
    }

    // MARK: - User stores

    func testAddUserStoreAppearsBeforeBuiltIn() throws {
        try registry.add(userStore("acme-internal"))
        let stores = registry.stores()
        XCTAssertEqual(stores.map(\.id.rawValue), ["acme-internal", "com.vee.store.xbar"])
        XCTAssertTrue(stores[0].isEnabled)
    }

    func testAddDuplicateThrows() throws {
        try registry.add(userStore("dup"))
        XCTAssertThrowsError(try registry.add(userStore("dup"))) { error in
            XCTAssertEqual(error as? StoreRegistryError, .duplicateID("dup"))
        }
    }

    func testCannotAddOrRemoveBuiltIn() {
        var xbar = BuiltInStores.xbar
        xbar.displayName = "hijack"
        XCTAssertThrowsError(try registry.add(xbar)) { XCTAssertEqual($0 as? StoreRegistryError, .builtInImmutable) }
        XCTAssertThrowsError(try registry.remove(BuiltInStores.xbarID)) { XCTAssertEqual($0 as? StoreRegistryError, .builtInImmutable) }
    }

    func testRemoveUserStore() throws {
        try registry.add(userStore("temp"))
        try registry.remove(StoreID("temp"))
        XCTAssertEqual(registry.stores().map(\.id), [BuiltInStores.xbarID])
    }

    func testUpdateUserStore() throws {
        try registry.add(userStore("s"))
        var edited = userStore("s")
        edited.displayName = "Renamed"
        try registry.update(edited)
        XCTAssertEqual(registry.userStores().first?.displayName, "Renamed")
    }

    // MARK: - Enable / disable

    func testDisableBuiltInHidesItFromEnabled() {
        registry.setEnabled(false, id: BuiltInStores.xbarID)
        XCTAssertFalse(registry.stores().first { $0.id == BuiltInStores.xbarID }!.isEnabled)
        XCTAssertTrue(registry.enabledStores().isEmpty)
        // Re-enabling restores it.
        registry.setEnabled(true, id: BuiltInStores.xbarID)
        XCTAssertEqual(registry.enabledStores().map(\.id), [BuiltInStores.xbarID])
    }

    func testDisableUserStore() throws {
        try registry.add(userStore("s"))
        registry.setEnabled(false, id: StoreID("s"))
        XCTAssertFalse(registry.stores().first { $0.id == StoreID("s") }!.isEnabled)
    }

    // MARK: - Managed stores (MDM)

    private func installManaged(_ dicts: [[String: Any]]) {
        defaults.set(dicts, forKey: "vee.managedStores")
    }

    func testManagedStoreIsForceEnabledAndReadOnly() {
        installManaged([[
            "id": "acme-mdm", "displayName": "Acme MDM", "kind": "githubEnterprise",
            "apiHost": "https://ghe.acme.corp/api/v3", "rawHost": "https://ghe.acme.corp/raw",
            "owner": "platform", "repo": "vee-plugins", "requireSignature": true
        ]])
        let managed = registry.stores().first { $0.id == StoreID("acme-mdm") }
        let store = try XCTUnwrap(managed)
        XCTAssertTrue(store.isManaged)
        XCTAssertTrue(store.isEnabled)
        XCTAssertTrue(store.requireSignature)

        // Force-enabled: setEnabled is a no-op.
        registry.setEnabled(false, id: StoreID("acme-mdm"))
        XCTAssertTrue(registry.stores().first { $0.id == StoreID("acme-mdm") }!.isEnabled)

        // Read-only: can't add/remove/update.
        XCTAssertThrowsError(try registry.remove(StoreID("acme-mdm"))) { XCTAssertEqual($0 as? StoreRegistryError, .managedImmutable) }
        XCTAssertThrowsError(try registry.update(userStore("acme-mdm"))) { XCTAssertEqual($0 as? StoreRegistryError, .managedImmutable) }
    }

    func testManagedShadowsUserStoreWithSameID() throws {
        try registry.add(userStore("shared"))
        installManaged([[
            "id": "shared", "displayName": "Managed Shared", "kind": "github",
            "apiHost": "https://api.github.com", "rawHost": "https://raw.githubusercontent.com",
            "owner": "corp", "repo": "shared"
        ]])
        let matches = registry.stores().filter { $0.id == StoreID("shared") }
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].isManaged)
        XCTAssertEqual(matches[0].displayName, "Managed Shared")
    }

    func testDisablePublicStoreHidesXbar() {
        defaults.set(true, forKey: "vee.disablePublicStore")
        XCTAssertFalse(registry.stores().contains { $0.id == BuiltInStores.xbarID })
    }
}

/// The catalog client attaches a bearer token only when the store opts into
/// token auth and a non-empty token is available.
final class CatalogClientAuthTests: XCTestCase {
    private func client(auth: StoreAuthMode, token: String?) -> GitHubCatalogClient {
        let config = StoreConfig(
            id: StoreID("acme"), displayName: "Acme", kind: .github,
            apiHost: URL(string: "https://api.github.com"),
            rawHost: URL(string: "https://raw.githubusercontent.com"),
            owner: "acme", repo: "plugins", authMode: auth
        )
        return GitHubCatalogClient(config: config, tokenProvider: InMemoryStoreTokenStore(token: token))
    }

    private let url = URL(string: "https://api.github.com/x")!

    func testTokenAuthAttachesBearer() {
        let req = client(auth: .token, token: "abc123").authorizedRequest(url)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testNoAuthNeverAttachesBearerEvenWithToken() {
        let req = client(auth: .none, token: "abc123").authorizedRequest(url)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testTokenAuthWithEmptyTokenAttachesNothing() {
        let req = client(auth: .token, token: nil).authorizedRequest(url)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testAcceptHeaderAlwaysSet() {
        let req = client(auth: .none, token: nil).authorizedRequest(url)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }
}
