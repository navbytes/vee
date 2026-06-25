import Foundation
import VeeProtocol

/// Namespaced secret storage. Every item is keyed by the calling plugin's id +
/// a capability-declared namespace so one plugin cannot read another's secrets.
///
/// > Wave 1c worker: implement `InMemorySecretStore` (full logic, fully tested)
/// > and `KeychainStore` (real `kSecClassGenericPassword` via Security; service
/// > string `com.vee.<pluginId>.<namespace>`; `errSecDuplicateItem`→update) per
/// > build plan §4. Real-Keychain round-trip tagged `.keychainLive`. Tests first.
public protocol SecretStore {
    func get(pluginId: String, namespace: String, account: String) throws -> String?
    func set(pluginId: String, namespace: String, account: String, secret: String) throws
    func delete(pluginId: String, namespace: String, account: String) throws
}

/// In-memory test double and dev store.
public final class InMemorySecretStore: SecretStore {
    public init() {}
    // Wave 0 stub: real implementation lands in Wave 1c.
    public func get(pluginId: String, namespace: String, account: String) throws -> String? { nil }
    public func set(pluginId: String, namespace: String, account: String, secret: String) throws {}
    public func delete(pluginId: String, namespace: String, account: String) throws {}
}
