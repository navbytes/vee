import Foundation

/// Thrown when a mutation targets a store the user doesn't own.
public enum StoreRegistryError: Error, Equatable, Sendable {
    /// Can't add/remove/edit the built-in public catalog.
    case builtInImmutable
    /// Can't add/remove/edit an MDM-managed store.
    case managedImmutable
    /// A store with this id already exists.
    case duplicateID(String)
    /// No user store with this id.
    case notFound(String)
}

/// The set of plugin stores available in Discover, assembled from three sources
/// and persisted in `UserDefaults`:
///
/// - **Managed** — read from the MDM-forced `vee.managedStores` key. Read-only
///   and force-enabled.
/// - **User** — stores the user added, persisted as JSON under `vee.customStores`.
/// - **Built-in** — the public xbar catalog, appended unless the managed
///   `vee.disablePublicStore` flag is set.
///
/// On an id collision a managed store wins. `@unchecked Sendable`: `UserDefaults`
/// is thread-safe.
public final class StoreRegistry: @unchecked Sendable {
    private let defaults: UserDefaults

    private let userStoresKey = "vee.customStores"
    private let managedStoresKey = "vee.managedStores"
    private let disablePublicKey = "vee.disablePublicStore"
    private let disabledIDsKey = "vee.disabledStoreIDs"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Assembled view

    /// The full store list: managed ⊕ user ⊕ built-in (unless disabled). Managed
    /// stores are force-enabled; a managed id shadows a user store with the same
    /// id. Order: managed first, then user, then the built-in catalog last.
    public func stores() -> [StoreConfig] {
        let managed = managedStores()
        let managedIDs = Set(managed.map(\.id))
        let disabled = disabledIDs()

        var result = managed

        for var store in userStores() where !managedIDs.contains(store.id) {
            store.isEnabled = !disabled.contains(store.id)
            result.append(store)
        }

        if !defaults.bool(forKey: disablePublicKey), !managedIDs.contains(BuiltInStores.xbarID) {
            var xbar = BuiltInStores.xbar
            xbar.isEnabled = !disabled.contains(BuiltInStores.xbarID)
            result.append(xbar)
        }
        return result
    }

    /// Just the enabled stores, for the Discover fetch.
    public func enabledStores() -> [StoreConfig] {
        stores().filter(\.isEnabled)
    }

    // MARK: - Managed (read-only)

    private func managedStores() -> [StoreConfig] {
        guard let raw = defaults.array(forKey: managedStoresKey) as? [[String: Any]] else { return [] }
        var seen: Set<StoreID> = []
        return raw.compactMap { StoreConfig(managedDictionary: $0) }
            .filter { seen.insert($0.id).inserted }  // first wins on duplicate id
    }

    // MARK: - User stores (mutable)

    /// Stores the user added (excludes managed and built-in).
    public func userStores() -> [StoreConfig] {
        guard let data = defaults.data(forKey: userStoresKey),
              let stores = try? JSONDecoder().decode([StoreConfig].self, from: data)
        else { return [] }
        return stores
    }

    /// Adds a user store. Rejects the built-in id, a managed id, or a duplicate.
    public func add(_ store: StoreConfig) throws {
        guard store.id != BuiltInStores.xbarID else { throw StoreRegistryError.builtInImmutable }
        guard !managedStores().contains(where: { $0.id == store.id }) else { throw StoreRegistryError.managedImmutable }
        var stores = userStores()
        guard !stores.contains(where: { $0.id == store.id }) else { throw StoreRegistryError.duplicateID(store.id.rawValue) }
        var normalized = store
        normalized.isBuiltIn = false
        normalized.isManaged = false
        stores.append(normalized)
        try writeUserStores(stores)
    }

    /// Removes a user store. Rejects built-in and managed ids.
    public func remove(_ id: StoreID) throws {
        guard id != BuiltInStores.xbarID else { throw StoreRegistryError.builtInImmutable }
        guard !managedStores().contains(where: { $0.id == id }) else { throw StoreRegistryError.managedImmutable }
        var stores = userStores()
        guard stores.contains(where: { $0.id == id }) else { throw StoreRegistryError.notFound(id.rawValue) }
        stores.removeAll { $0.id == id }
        try writeUserStores(stores)
        // Drop any token and the disabled flag for a store that no longer exists.
        setDisabled(false, id: id)
    }

    /// Replaces a user store's config. Rejects built-in and managed ids.
    public func update(_ store: StoreConfig) throws {
        guard store.id != BuiltInStores.xbarID else { throw StoreRegistryError.builtInImmutable }
        guard !managedStores().contains(where: { $0.id == store.id }) else { throw StoreRegistryError.managedImmutable }
        var stores = userStores()
        guard let idx = stores.firstIndex(where: { $0.id == store.id }) else { throw StoreRegistryError.notFound(store.id.rawValue) }
        var normalized = store
        normalized.isManaged = false
        normalized.isBuiltIn = false
        stores[idx] = normalized
        try writeUserStores(stores)
    }

    // MARK: - Enable / disable

    /// Enables or disables a store. Managed stores are force-enabled — this is a
    /// no-op for them. The built-in catalog and user stores are toggled via a
    /// persisted disabled-id set.
    public func setEnabled(_ enabled: Bool, id: StoreID) {
        guard !managedStores().contains(where: { $0.id == id }) else { return }
        setDisabled(!enabled, id: id)
    }

    private func disabledIDs() -> Set<StoreID> {
        Set((defaults.stringArray(forKey: disabledIDsKey) ?? []).map(StoreID.init))
    }

    private func setDisabled(_ disabled: Bool, id: StoreID) {
        var ids = disabledIDs()
        if disabled { ids.insert(id) } else { ids.remove(id) }
        defaults.set(ids.map(\.rawValue).sorted(), forKey: disabledIDsKey)
    }

    private func writeUserStores(_ stores: [StoreConfig]) throws {
        let data = try JSONEncoder().encode(stores)
        defaults.set(data, forKey: userStoresKey)
    }
}
