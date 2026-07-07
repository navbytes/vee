import XCTest
import VeeCatalog
@testable import VeeUI

/// Covers `StoresSettingsModel.add(_:token:)` (wave 6h): a stale token typed
/// while a different (token-auth) Kind was selected must never be keychained
/// onto a store whose own auth mode doesn't use one.
@MainActor
final class StoresSettingsModelTests: XCTestCase {
    /// A `StoreRegistry` backed by an ephemeral, uniquely-named `UserDefaults`
    /// suite so tests never touch the real user's preferences.
    private func makeRegistry() -> (registry: StoreRegistry, suiteName: String) {
        let suiteName = "vee-ui-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (StoreRegistry(defaults: defaults), suiteName)
    }

    func testAddDoesNotPersistTokenForNonTokenAuthStore() throws {
        let (registry, suiteName) = makeRegistry()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tokenStore = InMemoryStoreTokenStore()
        let model = StoresSettingsModel(registry: registry, makeTokenStore: { _ in tokenStore })
        // Simulates: Kind=GitHub with a pasted token, then Kind switched to
        // Local before Add — the config itself is correctly `.none`-authMode,
        // but a stale (non-nil) token string is still what the view has.
        let config = StoreConfig(
            id: StoreID("local-1"), displayName: "Local", kind: .local,
            baseURL: URL(fileURLWithPath: "/tmp/vee-store"), authMode: .none
        )

        try model.add(config, token: "stale-github-token")

        XCTAssertNil(tokenStore.token(), "a .none-authMode store must never get a persisted token, even if a stale value was passed")
    }

    func testAddPersistsTokenForTokenAuthStore() throws {
        let (registry, suiteName) = makeRegistry()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tokenStore = InMemoryStoreTokenStore()
        let model = StoresSettingsModel(registry: registry, makeTokenStore: { _ in tokenStore })
        let config = StoreConfig(
            id: StoreID("gh-1"), displayName: "GH", kind: .github,
            owner: "acme", repo: "plugins", authMode: .token
        )

        try model.add(config, token: "real-token")

        XCTAssertEqual(tokenStore.token(), "real-token", "a genuine token-auth store must still save its token")
    }

    /// An empty/whitespace-only token must not be saved even for a token-auth
    /// store (pre-existing `!token.isEmpty` guard, unchanged by this fix).
    func testAddWithEmptyTokenSavesNothing() throws {
        let (registry, suiteName) = makeRegistry()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tokenStore = InMemoryStoreTokenStore()
        let model = StoresSettingsModel(registry: registry, makeTokenStore: { _ in tokenStore })
        let config = StoreConfig(
            id: StoreID("gh-2"), displayName: "GH2", kind: .github,
            owner: "acme", repo: "plugins", authMode: .token
        )

        try model.add(config, token: "")

        XCTAssertNil(tokenStore.token())
    }
}
