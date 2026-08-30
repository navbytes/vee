import XCTest
@testable import VeeCatalog

final class StoreRegistryTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var registry: StoreRegistry!
    private var tokenStores: [StoreID: InMemoryStoreTokenStore] = [:]

    override func setUp() {
        super.setUp()
        suiteName = "vee.storeregistry.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        tokenStores = [:]
        // Keeps tests off the real Keychain, and returns the same instance
        // per id so a test can read back what `remove()` did to it.
        registry = StoreRegistry(defaults: defaults, makeTokenStore: { [weak self] id in
            self?.tokenStore(for: id) ?? InMemoryStoreTokenStore()
        })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func tokenStore(for id: StoreID) -> InMemoryStoreTokenStore {
        if let existing = tokenStores[id] { return existing }
        let store = InMemoryStoreTokenStore()
        tokenStores[id] = store
        return store
    }

    private func userStore(_ id: String, enabled: Bool = true) -> StoreConfig {
        StoreConfig(id: StoreID(id), displayName: id, kind: .github,
                    apiHost: URL(string: "https://api.github.com"),
                    rawHost: URL(string: "https://raw.githubusercontent.com"),
                    owner: "acme", repo: id)
    }

    // MARK: - Baseline

    /// No seeding call, no prior state: both built-ins are present, enabled,
    /// vee-plugins before xbar (default store lists first).
    func testEmptyRegistryHasBothBuiltInsVeePluginsBeforeXbar() {
        let stores = registry.stores()
        XCTAssertEqual(stores.map(\.id), [BuiltInStores.veePluginsID, BuiltInStores.xbarID])
        XCTAssertTrue(stores[0].isEnabled)
        XCTAssertTrue(stores[0].isBuiltIn)
        XCTAssertTrue(stores[1].isEnabled)
        XCTAssertTrue(stores[1].isBuiltIn)
    }

    // MARK: - User stores

    func testAddUserStoreAppearsBeforeBuiltIns() throws {
        try registry.add(userStore("acme-internal"))
        let stores = registry.stores()
        XCTAssertEqual(stores.map(\.id.rawValue), ["acme-internal", "com.vee.store.vee-plugins", "com.vee.store.xbar"])
        XCTAssertTrue(stores[0].isEnabled)
    }

    func testAddDuplicateThrows() throws {
        try registry.add(userStore("dup"))
        XCTAssertThrowsError(try registry.add(userStore("dup"))) { error in
            XCTAssertEqual(error as? StoreRegistryError, .duplicateID("dup"))
        }
    }

    /// The Add-store sheet mints a random id every time, so a duplicate repo
    /// is never caught by the id check above — dedup has to look at identity
    /// (kind + normalized owner/repo) instead. Also covers the case- and
    /// `.git`-suffix normalization the fix calls for.
    func testAddRejectsSameRepoUnderADifferentID() throws {
        try registry.add(StoreConfig(
            id: StoreID("user-aaaaaaaa"), displayName: "Acme Plugins", kind: .github,
            owner: "Acme", repo: "Vee-Plugins"
        ))
        let dup = StoreConfig(
            id: StoreID("user-bbbbbbbb"), displayName: "Acme Plugins Again", kind: .github,
            owner: "acme", repo: "vee-plugins.git"
        )
        XCTAssertThrowsError(try registry.add(dup)) { error in
            XCTAssertEqual(error as? StoreRegistryError, .duplicateStore("Acme Plugins"))
        }
        XCTAssertEqual(registry.userStores().count, 1)
    }

    /// Identity dedup also has to catch a repo that duplicates the built-in
    /// catalog at its ref, not just another user store.
    func testAddRejectsDuplicateOfBuiltInCatalog() {
        let dup = StoreConfig(
            id: StoreID("user-cccccccc"), displayName: "My xbar mirror", kind: .github,
            owner: "MATRYER", repo: "xbar-plugins", ref: "main"
        )
        XCTAssertThrowsError(try registry.add(dup)) { error in
            XCTAssertEqual(error as? StoreRegistryError, .duplicateStore("Public xbar catalog"))
        }
    }

    /// Same dedup, the http/local branch: identity is the normalized baseURL.
    func testAddRejectsSameHTTPRootByNormalizedBaseURL() throws {
        try registry.add(StoreConfig(
            id: StoreID("user-dddddddd"), displayName: "Acme HTTP", kind: .http,
            baseURL: URL(string: "https://store.acme.corp/vee")!
        ))
        let dup = StoreConfig(
            id: StoreID("user-eeeeeeee"), displayName: "Acme HTTP Again", kind: .http,
            baseURL: URL(string: "https://STORE.acme.corp/vee/")!
        )
        XCTAssertThrowsError(try registry.add(dup)) { error in
            XCTAssertEqual(error as? StoreRegistryError, .duplicateStore("Acme HTTP"))
        }
    }

    /// Only the host folds case — a server path can be case-sensitive, so
    /// `/CatalogA` and `/cataloga` must stay distinct roots, not dedupe.
    func testAddAllowsHTTPRootsDifferingOnlyInPathCase() throws {
        try registry.add(StoreConfig(
            id: StoreID("user-ffffffff"), displayName: "Catalog A", kind: .http,
            baseURL: URL(string: "https://store.acme.corp/CatalogA")!
        ))
        XCTAssertNoThrow(try registry.add(StoreConfig(
            id: StoreID("user-gggggggg"), displayName: "catalog a, lowercase", kind: .http,
            baseURL: URL(string: "https://store.acme.corp/cataloga")!
        )))
        XCTAssertEqual(registry.userStores().count, 2)
    }

    /// The blocking case: two different GitHub Enterprise *servers* commonly
    /// standardize repo names across staging/prod instances. Same owner/repo
    /// but a different host must be allowed, not falsely deduped.
    func testAddAllowsSameGHERepoOnDifferentHosts() throws {
        try registry.add(StoreConfig(
            id: StoreID("user-11111111"), displayName: "Staging GHE", kind: .githubEnterprise,
            apiHost: URL(string: "https://ghe-staging.acme.corp/api/v3")!,
            rawHost: URL(string: "https://ghe-staging.acme.corp/raw")!,
            owner: "platform", repo: "vee-plugins"
        ))
        XCTAssertNoThrow(try registry.add(StoreConfig(
            id: StoreID("user-22222222"), displayName: "Prod GHE", kind: .githubEnterprise,
            apiHost: URL(string: "https://ghe-prod.acme.corp/api/v3")!,
            rawHost: URL(string: "https://ghe-prod.acme.corp/raw")!,
            owner: "platform", repo: "vee-plugins"
        )))
        XCTAssertEqual(registry.userStores().count, 2)
    }

    /// The same GHE server, same owner/repo (case- and `.git`-insensitively)
    /// still dedupes — the host discriminator doesn't defeat the original fix.
    func testAddRejectsSameGHERepoOnSameHost() throws {
        try registry.add(StoreConfig(
            id: StoreID("user-33333333"), displayName: "Platform Plugins", kind: .githubEnterprise,
            apiHost: URL(string: "https://ghe.acme.corp/api/v3")!,
            rawHost: URL(string: "https://ghe.acme.corp/raw")!,
            owner: "platform", repo: "vee-plugins"
        ))
        let dup = StoreConfig(
            id: StoreID("user-44444444"), displayName: "Platform Plugins Again", kind: .githubEnterprise,
            apiHost: URL(string: "https://GHE.acme.corp/api/v3")!,
            rawHost: URL(string: "https://ghe.acme.corp/raw")!,
            owner: "Platform", repo: "vee-plugins.git"
        )
        XCTAssertThrowsError(try registry.add(dup)) { error in
            XCTAssertEqual(error as? StoreRegistryError, .duplicateStore("Platform Plugins"))
        }
    }

    /// Product call: the same repo at two different refs (stable vs beta) is
    /// a legitimately distinct catalog and must be addable under both.
    func testAddAllowsSameRepoAtADifferentRef() throws {
        try registry.add(StoreConfig(
            id: StoreID("user-66666666"), displayName: "Acme Stable", kind: .github,
            owner: "acme", repo: "vee-plugins", ref: "main"
        ))
        XCTAssertNoThrow(try registry.add(StoreConfig(
            id: StoreID("user-77777777"), displayName: "Acme Beta", kind: .github,
            owner: "acme", repo: "vee-plugins", ref: "beta"
        )))
        XCTAssertEqual(registry.userStores().count, 2)
    }

    /// Dedup has to cover managed (MDM) stores too — a user shouldn't be able
    /// to add a twin of an org-provisioned store under their own id.
    func testAddRejectsDuplicateOfManagedStore() {
        installManaged([[
            "id": "acme-mdm", "displayName": "Acme MDM", "kind": "github",
            "apiHost": "https://api.github.com", "rawHost": "https://raw.githubusercontent.com",
            "owner": "acme", "repo": "vee-plugins"
        ]])
        let dup = StoreConfig(
            id: StoreID("user-88888888"), displayName: "Sneaky twin", kind: .github,
            owner: "Acme", repo: "vee-plugins"
        )
        XCTAssertThrowsError(try registry.add(dup)) { error in
            XCTAssertEqual(error as? StoreRegistryError, .duplicateStore("Acme MDM"))
        }
    }

    /// A present-but-undecodable `vee.customStores` blob (corrupt bytes, or a
    /// schema drift missing a since-added required field) must not be
    /// silently treated as empty and overwritten — that would wipe every
    /// existing custom store the next time the user adds/removes/updates one.
    func testAddRefusesToOverwriteCorruptUserStoresBlob() throws {
        let corrupt = Data("{\"oops\":\"not a store array\"}".utf8)
        defaults.set(corrupt, forKey: "vee.customStores")

        XCTAssertThrowsError(try registry.add(userStore("new"))) { error in
            XCTAssertEqual(error as? StoreRegistryError, .corruptUserStores)
        }
        // Refused to persist: the undecodable bytes are untouched, not
        // clobbered with a fresh single-store array containing only "new".
        XCTAssertEqual(defaults.data(forKey: "vee.customStores"), corrupt)
    }

    /// `remove`/`update` must fail closed the same way `add` does — the bug
    /// wasn't specific to `add`, it was the shared read-modify-write.
    func testRemoveRefusesToOverwriteCorruptUserStoresBlob() throws {
        try registry.add(userStore("keep"))
        let corrupt = Data("{\"oops\":\"not a store array\"}".utf8)
        defaults.set(corrupt, forKey: "vee.customStores")

        XCTAssertThrowsError(try registry.remove(StoreID("keep"))) { error in
            XCTAssertEqual(error as? StoreRegistryError, .corruptUserStores)
        }
        XCTAssertEqual(defaults.data(forKey: "vee.customStores"), corrupt)
    }

    func testUpdateRefusesToOverwriteCorruptUserStoresBlob() throws {
        try registry.add(userStore("keep"))
        let corrupt = Data("{\"oops\":\"not a store array\"}".utf8)
        defaults.set(corrupt, forKey: "vee.customStores")

        var edited = userStore("keep")
        edited.displayName = "Renamed"
        XCTAssertThrowsError(try registry.update(edited)) { error in
            XCTAssertEqual(error as? StoreRegistryError, .corruptUserStores)
        }
        XCTAssertEqual(defaults.data(forKey: "vee.customStores"), corrupt)
    }

    /// Happy-path complement to the corrupt-blob tests above: a normal,
    /// decodable multi-store blob survives an unrelated `add()` intact —
    /// proves the read-modify-write in `add()` doesn't drop what it didn't
    /// touch, not just that it refuses to run over corrupt bytes.
    func testAddPreservesExistingMultiStoreBlobAcrossAnotherAdd() throws {
        try registry.add(userStore("one"))
        try registry.add(userStore("two"))

        try registry.add(userStore("three"))

        XCTAssertEqual(Set(registry.userStores().map(\.id.rawValue)), ["one", "two", "three"])
    }

    /// `loadUserStoresOrThrow` (exercised here via `userStores()` for reads
    /// and `add()` for the throwing mutator path) must treat an absent key,
    /// explicit zero-byte `Data`, and a valid empty-array blob identically —
    /// all safe/empty — and throw only for a present, non-empty,
    /// undecodable one (covered separately above).
    func testAbsentZeroByteAndEmptyArrayUserStoresAllReadAsEmpty() throws {
        // Absent key (nothing ever written).
        XCTAssertEqual(registry.userStores(), [])
        try registry.add(userStore("a"))
        try registry.remove(StoreID("a"))

        // Explicit zero-byte Data under the key.
        defaults.set(Data(), forKey: "vee.customStores")
        XCTAssertEqual(registry.userStores(), [])
        try registry.add(userStore("b"))
        try registry.remove(StoreID("b"))

        // Explicit, validly-decodable empty-array JSON.
        defaults.set(Data("[]".utf8), forKey: "vee.customStores")
        XCTAssertEqual(registry.userStores(), [])
        XCTAssertNoThrow(try registry.add(userStore("c")))
    }

    func testCannotAddOrRemoveBuiltIn() {
        var xbar = BuiltInStores.xbar
        xbar.displayName = "hijack"
        XCTAssertThrowsError(try registry.add(xbar)) { XCTAssertEqual($0 as? StoreRegistryError, .builtInImmutable) }
        XCTAssertThrowsError(try registry.remove(BuiltInStores.xbarID)) { XCTAssertEqual($0 as? StoreRegistryError, .builtInImmutable) }
    }

    func testCannotAddOrRemoveVeePluginsBuiltIn() {
        var veePlugins = BuiltInStores.veePlugins
        veePlugins.displayName = "hijack"
        XCTAssertThrowsError(try registry.add(veePlugins)) { XCTAssertEqual($0 as? StoreRegistryError, .builtInImmutable) }
        XCTAssertThrowsError(try registry.remove(BuiltInStores.veePluginsID)) { XCTAssertEqual($0 as? StoreRegistryError, .builtInImmutable) }
        XCTAssertThrowsError(try registry.update(veePlugins)) { XCTAssertEqual($0 as? StoreRegistryError, .builtInImmutable) }
    }

    func testRemoveUserStore() throws {
        try registry.add(userStore("temp"))
        try registry.remove(StoreID("temp"))
        XCTAssertEqual(registry.stores().map(\.id), [BuiltInStores.veePluginsID, BuiltInStores.xbarID])
    }

    /// `remove()` used to only clear the disabled flag, despite a comment
    /// claiming it dropped the token too — the actual cleanup lived solely in
    /// the Settings UI's model, so any other caller orphaned the Keychain
    /// secret. The registry itself must drop it.
    func testRemoveDropsTheStoreToken() throws {
        try registry.add(userStore("s"))
        tokenStore(for: StoreID("s")).set("secret-token")

        try registry.remove(StoreID("s"))

        XCTAssertNil(tokenStore(for: StoreID("s")).token(), "remove() must drop the store's token, not just its disabled flag")
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
        XCTAssertEqual(registry.enabledStores().map(\.id), [BuiltInStores.veePluginsID])
        // Re-enabling restores it.
        registry.setEnabled(true, id: BuiltInStores.xbarID)
        XCTAssertEqual(registry.enabledStores().map(\.id), [BuiltInStores.veePluginsID, BuiltInStores.xbarID])
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

    func testManagedStoreIsForceEnabledAndReadOnly() throws {
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

    func testDisablePublicStoreHidesBothBuiltIns() {
        defaults.set(true, forKey: "vee.disablePublicStore")
        let stores = registry.stores()
        XCTAssertFalse(stores.contains { $0.id == BuiltInStores.xbarID })
        XCTAssertFalse(stores.contains { $0.id == BuiltInStores.veePluginsID })
    }

    // MARK: - Default-store seeding (xbar disabled by default on a fresh install)

    /// A fresh install: `vee.hasCompletedFirstRun` is absent (still false),
    /// so the seed disables xbar. vee-plugins is untouched (stays enabled).
    func testSeedOnFreshInstallDisablesXbarOnly() {
        registry.seedDefaultStoresIfNeeded()
        let stores = registry.stores()
        XCTAssertFalse(stores.first { $0.id == BuiltInStores.xbarID }!.isEnabled)
        XCTAssertTrue(stores.first { $0.id == BuiltInStores.veePluginsID }!.isEnabled)
    }

    /// An existing install: `vee.hasCompletedFirstRun` is already true (set
    /// by a prior launch, before this seed existed) — xbar must stay enabled.
    func testSeedOnExistingInstallLeavesXbarEnabled() {
        defaults.set(true, forKey: "vee.hasCompletedFirstRun")
        registry.seedDefaultStoresIfNeeded()
        XCTAssertTrue(registry.stores().first { $0.id == BuiltInStores.xbarID }!.isEnabled)
    }

    /// One-shot: a second call (e.g. a later launch) doesn't reapply — a user
    /// who re-enabled xbar after the first seed isn't silently flipped back.
    func testSeedOnlyAppliesOnce() {
        registry.seedDefaultStoresIfNeeded()
        registry.setEnabled(true, id: BuiltInStores.xbarID)
        registry.seedDefaultStoresIfNeeded()
        XCTAssertTrue(registry.stores().first { $0.id == BuiltInStores.xbarID }!.isEnabled)
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
