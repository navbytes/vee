import Foundation
import Security

/// A token store that can also write — the settings UI saves a store's token
/// here; the catalog client only reads it via ``StoreTokenProviding``.
public protocol StoreTokenStoring: StoreTokenProviding {
    /// Stores `token` for the store, or clears it when `nil`/empty.
    func set(_ token: String?)
}

/// Keychain-backed store token (`kSecClassGenericPassword`), one service per
/// store. Mirrors `VeePreferences.KeychainSecretStore` but for an *app*
/// credential, kept out of any plugin's environment.
public struct KeychainStoreTokenStore: StoreTokenStoring {
    private let service: String
    private static let account = "token"

    public init(storeID: StoreID) {
        self.service = "com.vee.store.\(storeID.rawValue)"
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
    }

    public func token() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ token: String?) {
        guard let token, !token.isEmpty else {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery()
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}

/// In-memory token store for tests. `@unchecked Sendable`: guarded by a lock.
public final class InMemoryStoreTokenStore: StoreTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(token: String? = nil) { self.value = token }

    public func token() -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func set(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        value = (token?.isEmpty == true) ? nil : token
    }
}
