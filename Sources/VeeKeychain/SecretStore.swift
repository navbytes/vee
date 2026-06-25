import Foundation
import VeeProtocol

#if canImport(Security)
import Security
#endif

// MARK: - Service-string construction

/// Builds the `kSecAttrService` value for a plugin's namespaced secret.
///
/// The service string is **exactly** `com.vee.<pluginId>.<namespace>`, the
/// composite key that isolates one plugin's (and one namespace's) secrets from
/// another's. This is a pure function so it can be asserted in tests without
/// touching the real Keychain (build plan §4 case 6).
///
/// - Note: The `com.vee.` prefix is always prepended, even when `pluginId` is
///   itself reverse-DNS (e.g. `com.vee.github` → `com.vee.com.vee.github.<ns>`),
///   matching the contract in `Capabilities.keychainNamespaces`.
public func keychainServiceString(pluginId: String, namespace: String) -> String {
    "com.vee.\(pluginId).\(namespace)"
}

// MARK: - Capability predicate (used by the Wave 2a bridge)

/// Capability gate: whether `namespace` is permitted for a plugin holding the
/// given `Capabilities`. The bridge calls this before any keychain access; a
/// namespace not listed in `Capabilities.keychainNamespaces` is denied
/// (default-deny — an empty list permits nothing). Build plan §4 case 7.
public func isKeychainNamespacePermitted(_ namespace: String,
                                         capabilities: Capabilities) -> Bool {
    capabilities.keychainNamespaces.contains(namespace)
}

public extension Capabilities {
    /// Convenience form of ``isKeychainNamespacePermitted(_:capabilities:)`` so
    /// the bridge can write `caps.permitsKeychainNamespace("tokens")`.
    func permitsKeychainNamespace(_ namespace: String) -> Bool {
        isKeychainNamespacePermitted(namespace, capabilities: self)
    }
}

// MARK: - Errors

/// Errors surfaced by the keychain layer. Capability denials are distinct from
/// underlying OS failures so the bridge can map them to the right JSON-RPC
/// error (`.capabilityDenied` vs `.internalError`).
public enum KeychainError: Error, Equatable, Sendable {
    /// The requested namespace is not declared in the plugin's capabilities.
    case namespaceNotPermitted(String)
    /// A `SecItem*` call failed with the given `OSStatus`.
    case unhandledStatus(OSStatus)
    /// A stored item was present but its data was not valid UTF-8.
    case malformedData
}

// MARK: - SecretStore protocol

/// Namespaced secret storage. Every item is keyed by the calling plugin's id +
/// a capability-declared namespace + an account, so one plugin cannot read
/// another's secrets (different `kSecAttrService` strings).
///
/// Conformers are `Sendable`: the engine/services targets (relaxed concurrency)
/// hold a `SecretStore` and call it from background queues.
public protocol SecretStore: Sendable {
    /// Returns the stored secret, or `nil` if no item exists (missing is not an
    /// error).
    func get(pluginId: String, namespace: String, account: String) throws -> String?
    /// Stores `secret`, overwriting any existing value for the same key.
    func set(pluginId: String, namespace: String, account: String, secret: String) throws
    /// Removes the secret. Deleting a missing key is a no-op (not an error).
    func delete(pluginId: String, namespace: String, account: String) throws
}

// MARK: - InMemorySecretStore

/// In-memory secret store — the CI-tested implementation and the test double.
///
/// Keys mirror the real Keychain's composite key: the pure service string
/// (`com.vee.<pluginId>.<namespace>`) plus the account. Namespacing isolation
/// (build plan §4 case 2) therefore falls out for free: plugin A and plugin B
/// produce different service strings even for the same account name.
///
/// Thread-safe via an internal lock; `@unchecked Sendable` because the mutable
/// dictionary is only ever touched while the lock is held.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private struct Key: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var items: [Key: String] = [:]

    public init() {}

    private func key(_ pluginId: String, _ namespace: String, _ account: String) -> Key {
        Key(service: keychainServiceString(pluginId: pluginId, namespace: namespace),
            account: account)
    }

    public func get(pluginId: String, namespace: String, account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return items[key(pluginId, namespace, account)]
    }

    public func set(pluginId: String, namespace: String, account: String, secret: String) throws {
        lock.lock(); defer { lock.unlock() }
        // Insert-or-overwrite mirrors errSecDuplicateItem -> SecItemUpdate.
        items[key(pluginId, namespace, account)] = secret
    }

    public func delete(pluginId: String, namespace: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[key(pluginId, namespace, account)] = nil
    }
}

// MARK: - CapabilityCheckedSecretStore

/// Wraps any ``SecretStore`` and rejects access to namespaces not declared in a
/// fixed `Capabilities` value before delegating. This is the shape the Wave 2a
/// bridge will use to enforce the manifest at the keychain boundary; tested
/// here (build plan §4 case 7) so the predicate's behavior is pinned.
public final class CapabilityCheckedSecretStore: SecretStore, @unchecked Sendable {
    private let backing: any SecretStore
    private let capabilities: Capabilities

    public init(backing: any SecretStore, capabilities: Capabilities) {
        self.backing = backing
        self.capabilities = capabilities
    }

    private func requirePermitted(_ namespace: String) throws {
        guard isKeychainNamespacePermitted(namespace, capabilities: capabilities) else {
            throw KeychainError.namespaceNotPermitted(namespace)
        }
    }

    public func get(pluginId: String, namespace: String, account: String) throws -> String? {
        try requirePermitted(namespace)
        return try backing.get(pluginId: pluginId, namespace: namespace, account: account)
    }

    public func set(pluginId: String, namespace: String, account: String, secret: String) throws {
        try requirePermitted(namespace)
        try backing.set(pluginId: pluginId, namespace: namespace, account: account, secret: secret)
    }

    public func delete(pluginId: String, namespace: String, account: String) throws {
        try requirePermitted(namespace)
        try backing.delete(pluginId: pluginId, namespace: namespace, account: account)
    }
}

// MARK: - KeychainStore (real Security framework)

#if canImport(Security)

/// Real secret store backed by `kSecClassGenericPassword` items in the macOS
/// Keychain.
///
/// - `kSecAttrService` is exactly `com.vee.<pluginId>.<namespace>`.
/// - `kSecAttrAccount` is the account.
/// - `kSecAttrAccessible` is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
///   (SEC-6): plugin OAuth tokens / API keys must NOT migrate into encrypted
///   backups or to a restored/new device, so the item is pinned to this device.
/// - `set` adds via `SecItemAdd`; on `errSecDuplicateItem` it switches to
///   `SecItemUpdate`.
/// - `get` on a missing item returns `nil` (not an error).
///
/// Stateless and therefore trivially `Sendable`.
public struct KeychainStore: SecretStore {

    public init() {}

    /// Base query identifying a single item (class + service + account).
    private func baseQuery(pluginId: String, namespace: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceString(pluginId: pluginId, namespace: namespace),
            kSecAttrAccount as String: account,
        ]
    }

    /// The exact attribute dictionary `set` passes to `SecItemAdd` for a new
    /// item. Pure (no Keychain access) so a test can assert SEC-6 holds: the
    /// `kSecAttrAccessible` value is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    public func addQueryForTesting(pluginId: String, namespace: String,
                                   account: String, secret: String) -> [String: Any] {
        var addQuery = baseQuery(pluginId: pluginId, namespace: namespace, account: account)
        addQuery[kSecValueData as String] = Data(secret.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return addQuery
    }

    public func get(pluginId: String, namespace: String, account: String) throws -> String? {
        var query = baseQuery(pluginId: pluginId, namespace: namespace, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.malformedData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func set(pluginId: String, namespace: String, account: String, secret: String) throws {
        let data = Data(secret.utf8)
        let addQuery = addQueryForTesting(pluginId: pluginId, namespace: namespace,
                                          account: account, secret: secret)

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Item exists -> update its data in place.
            let matchQuery = baseQuery(pluginId: pluginId, namespace: namespace, account: account)
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(matchQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(updateStatus)
            }
        default:
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    public func delete(pluginId: String, namespace: String, account: String) throws {
        let query = baseQuery(pluginId: pluginId, namespace: namespace, account: account)
        let status = SecItemDelete(query as CFDictionary)
        // Deleting a missing item is a no-op, not an error.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }
}

#endif
