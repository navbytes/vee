import Foundation

/// A minimal secret-token storage seam owned by **VeeApp**.
///
/// VeeApp's dependency graph is `VeeEngine / VeeServices / VeeFuzzy /
/// VeeProtocol` — it deliberately does NOT depend on `VeeKeychain`. So rather
/// than reach for `VeeKeychain.SecretStore` here, the settings UI writes plugin
/// tokens through this small protocol. The executable (`main.swift`, wired up
/// later) adapts the real `VeeKeychain` store to it; the test suite uses
/// `InMemoryTokenStore`.
///
/// Conceptually a token is keyed by a `plugin` id and an `account` (matching the
/// keychain's `pluginId` + `account` axes; the namespace — e.g. `"tokens"` — is
/// the adapter's concern, fixed for the settings surface). The settings window
/// only ever needs these three operations.
public protocol TokenStoring: AnyObject {
    /// The stored token for `plugin`/`account`, or `nil` if none exists.
    func token(plugin: String, account: String) -> String?
    /// Store (or overwrite) the token. An empty string is treated as "clear" so
    /// the secure field can erase a token by submitting blank.
    func setToken(_ token: String, plugin: String, account: String)
    /// Remove the token (deleting a missing one is a no-op).
    func deleteToken(plugin: String, account: String)
}

public extension TokenStoring {
    /// True when a non-empty token is stored for `plugin`/`account`. Lets the UI
    /// show a "set / not set" affordance without exposing the secret value.
    func hasToken(plugin: String, account: String) -> Bool {
        !(token(plugin: plugin, account: account) ?? "").isEmpty
    }
}

/// In-memory `TokenStoring` for tests and previews. Keys mirror the keychain's
/// composite key (plugin + account); not persisted anywhere.
public final class InMemoryTokenStore: TokenStoring {
    private struct Key: Hashable {
        let plugin: String
        let account: String
    }
    private var items: [Key: String] = [:]

    public init() {}

    public func token(plugin: String, account: String) -> String? {
        items[Key(plugin: plugin, account: account)]
    }

    public func setToken(_ token: String, plugin: String, account: String) {
        let key = Key(plugin: plugin, account: account)
        // Empty string clears, mirroring the secure field's "erase" gesture.
        if token.isEmpty { items[key] = nil } else { items[key] = token }
    }

    public func deleteToken(plugin: String, account: String) {
        items[Key(plugin: plugin, account: account)] = nil
    }
}
