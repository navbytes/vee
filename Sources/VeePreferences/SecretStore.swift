import Foundation
import Security

/// Stores plugin secrets (tokens, passwords). Namespaced per plugin so one
/// plugin cannot read another's. Backed by the Keychain in production; an
/// in-memory implementation is used in tests.
public protocol SecretStoring: Sendable {
    func get(_ account: String) -> String?
    func set(_ value: String?, for account: String)
}

/// Keychain-backed secret store (`kSecClassGenericPassword`), keyed by a
/// per-plugin service name.
public struct KeychainSecretStore: SecretStoring {
    private let service: String

    public init(pluginID: String) {
        self.service = "com.vee.plugin.\(pluginID)"
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, for account: String) {
        guard let value, !value.isEmpty else {
            SecItemDelete(baseQuery(account) as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

/// In-memory secret store for tests. `@unchecked Sendable`: guarded by a lock.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func get(_ account: String) -> String? {
        lock.withLock { storage[account] }
    }

    public func set(_ value: String?, for account: String) {
        lock.withLock { storage[account] = value }
    }
}
