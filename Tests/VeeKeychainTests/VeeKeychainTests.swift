import XCTest
@testable import VeeKeychain
import VeeProtocol

/// Wave 1c suite for VeeKeychain (build plan §4).
///
/// Cases 1–7 run against `InMemorySecretStore` (the CI-tested implementation
/// and the test double) plus the pure service-string helper and the capability
/// predicate. Case 8 (`.keychainLive`) exercises the real `KeychainStore` and is
/// SKIPPED unless `VEE_KEYCHAIN_LIVE == "1"` because it may prompt for keychain
/// access on a developer machine / would fail in headless CI.
final class VeeKeychainTests: XCTestCase {

    // Shared fixtures
    private let pluginA = "com.vee.github"
    private let pluginB = "com.vee.jira"
    private let ns = "tokens"
    private let account = "default"

    // MARK: - Case 1: set then get round-trips

    func test_setThenGet_roundTrips() throws {
        let store = InMemorySecretStore()
        try store.set(pluginId: pluginA, namespace: ns, account: account, secret: "ghp_secret")
        XCTAssertEqual(
            try store.get(pluginId: pluginA, namespace: ns, account: account),
            "ghp_secret"
        )
    }

    // MARK: - Case 2: namespacing isolation (plugin A vs plugin B, same account)

    func test_namespacingIsolation_pluginsCannotReadEachOther() throws {
        let store = InMemorySecretStore()
        // Same namespace + same account name, different plugin ids.
        try store.set(pluginId: pluginA, namespace: ns, account: account, secret: "A-secret")
        try store.set(pluginId: pluginB, namespace: ns, account: account, secret: "B-secret")

        XCTAssertEqual(try store.get(pluginId: pluginA, namespace: ns, account: account), "A-secret")
        XCTAssertEqual(try store.get(pluginId: pluginB, namespace: ns, account: account), "B-secret")

        // Deleting A must not touch B (isolation holds across mutations too).
        try store.delete(pluginId: pluginA, namespace: ns, account: account)
        XCTAssertNil(try store.get(pluginId: pluginA, namespace: ns, account: account))
        XCTAssertEqual(try store.get(pluginId: pluginB, namespace: ns, account: account), "B-secret")
    }

    // MARK: - Case 2b: namespace isolation within one plugin

    func test_namespaceIsolation_withinSamePlugin() throws {
        let store = InMemorySecretStore()
        try store.set(pluginId: pluginA, namespace: "tokens", account: account, secret: "tok")
        try store.set(pluginId: pluginA, namespace: "refresh", account: account, secret: "ref")
        XCTAssertEqual(try store.get(pluginId: pluginA, namespace: "tokens", account: account), "tok")
        XCTAssertEqual(try store.get(pluginId: pluginA, namespace: "refresh", account: account), "ref")
    }

    // MARK: - Case 3: overwrite (mirrors errSecDuplicateItem -> SecItemUpdate)

    func test_overwrite_setOnExistingKeyUpdates() throws {
        let store = InMemorySecretStore()
        try store.set(pluginId: pluginA, namespace: ns, account: account, secret: "old")
        try store.set(pluginId: pluginA, namespace: ns, account: account, secret: "new")
        XCTAssertEqual(try store.get(pluginId: pluginA, namespace: ns, account: account), "new")
    }

    // MARK: - Case 4: delete removes; subsequent get -> nil

    func test_delete_removesAndSubsequentGetIsNil() throws {
        let store = InMemorySecretStore()
        try store.set(pluginId: pluginA, namespace: ns, account: account, secret: "x")
        try store.delete(pluginId: pluginA, namespace: ns, account: account)
        XCTAssertNil(try store.get(pluginId: pluginA, namespace: ns, account: account))
    }

    // MARK: - Case 4b: delete of a missing key is a no-op (not an error)

    func test_delete_missingKeyIsNoOp() throws {
        let store = InMemorySecretStore()
        XCTAssertNoThrow(try store.delete(pluginId: pluginA, namespace: ns, account: "nope"))
    }

    // MARK: - Case 5: get on missing key -> nil (not an error)

    func test_getMissingKey_returnsNil() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.get(pluginId: pluginA, namespace: ns, account: account))
    }

    // MARK: - Case 6: service-string construction is EXACTLY com.vee.<pluginId>.<namespace>

    func test_serviceString_isExactlyComVeePluginNamespace() {
        XCTAssertEqual(
            keychainServiceString(pluginId: "com.vee.github", namespace: "tokens"),
            "com.vee.com.vee.github.tokens"
        )
        XCTAssertEqual(
            keychainServiceString(pluginId: "acme", namespace: "default"),
            "com.vee.acme.default"
        )
        // Order/format guard: prefix + pluginId + dot + namespace, nothing else.
        XCTAssertEqual(
            keychainServiceString(pluginId: "p", namespace: "n"),
            "com.vee.p.n"
        )
    }

    // MARK: - Case 7: capability gate

    func test_capabilityGate_rejectsNamespaceNotInCapabilities() {
        let caps = Capabilities(keychainNamespaces: ["tokens"])
        XCTAssertTrue(isKeychainNamespacePermitted("tokens", capabilities: caps))
        XCTAssertFalse(isKeychainNamespacePermitted("refresh", capabilities: caps))
        // Empty capabilities = default-deny (nothing permitted).
        XCTAssertFalse(isKeychainNamespacePermitted("tokens", capabilities: Capabilities()))
    }

    func test_capabilityGate_capabilityCheckedStore_rejectsUndeclaredNamespace() throws {
        let caps = Capabilities(keychainNamespaces: ["tokens"])
        let store = CapabilityCheckedSecretStore(
            backing: InMemorySecretStore(),
            capabilities: caps
        )

        // Permitted namespace round-trips.
        try store.set(pluginId: pluginA, namespace: "tokens", account: account, secret: "ok")
        XCTAssertEqual(try store.get(pluginId: pluginA, namespace: "tokens", account: account), "ok")

        // Undeclared namespace is rejected on both set and get.
        XCTAssertThrowsError(
            try store.set(pluginId: pluginA, namespace: "refresh", account: account, secret: "no")
        ) { error in
            XCTAssertTrue(error is KeychainError, "expected KeychainError, got \(error)")
            if case KeychainError.namespaceNotPermitted(let n) = error {
                XCTAssertEqual(n, "refresh")
            } else {
                XCTFail("expected .namespaceNotPermitted, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try store.get(pluginId: pluginA, namespace: "refresh", account: account)
        )
    }

    // MARK: - Case 8: LIVE real-Keychain round-trip (skipped unless VEE_KEYCHAIN_LIVE=1)

    func test_keychainLive_addCopyUpdateDelete() throws {
        guard ProcessInfo.processInfo.environment["VEE_KEYCHAIN_LIVE"] == "1" else {
            throw XCTSkip("Live keychain test skipped: set VEE_KEYCHAIN_LIVE=1 to run (may prompt for access).")
        }

        let store = KeychainStore()
        // Use a unique plugin id so we never collide with a real user item.
        let livePlugin = "com.vee.test.\(UUID().uuidString)"
        let liveNs = "live"
        let liveAccount = "ci"

        // Clean slate, then teardown guarantees removal even on failure.
        try? store.delete(pluginId: livePlugin, namespace: liveNs, account: liveAccount)
        defer { try? store.delete(pluginId: livePlugin, namespace: liveNs, account: liveAccount) }

        // get on missing -> nil
        XCTAssertNil(try store.get(pluginId: livePlugin, namespace: liveNs, account: liveAccount))

        // add (SecItemAdd)
        try store.set(pluginId: livePlugin, namespace: liveNs, account: liveAccount, secret: "first")
        // copy (SecItemCopyMatching)
        XCTAssertEqual(try store.get(pluginId: livePlugin, namespace: liveNs, account: liveAccount), "first")

        // update (errSecDuplicateItem -> SecItemUpdate)
        try store.set(pluginId: livePlugin, namespace: liveNs, account: liveAccount, secret: "second")
        XCTAssertEqual(try store.get(pluginId: livePlugin, namespace: liveNs, account: liveAccount), "second")

        // delete (SecItemDelete)
        try store.delete(pluginId: livePlugin, namespace: liveNs, account: liveAccount)
        XCTAssertNil(try store.get(pluginId: livePlugin, namespace: liveNs, account: liveAccount))
    }
}
