import Foundation

/// Thrown when a mutation targets a store the user doesn't own.
public enum StoreRegistryError: Error, Equatable, Sendable {
    /// Can't add/remove/edit the built-in public catalog.
    case builtInImmutable
    /// Can't add/remove/edit an MDM-managed store.
    case managedImmutable
    /// A store with this id already exists.
    case duplicateID(String)
    /// A different id, but the same effective store (same git repo, or same
    /// http/local root) as this existing store's display name.
    case duplicateStore(String)
    /// No user store with this id.
    case notFound(String)
    /// `vee.customStores` is present but doesn't decode as `[StoreConfig]`
    /// (corrupt bytes, or a schema-drifted/undecodable blob) — distinct from
    /// absent/empty, which is a safe, ordinary "no custom stores yet".
    case corruptUserStores
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
    private let makeTokenStore: (StoreID) -> StoreTokenStoring

    private let userStoresKey = "vee.customStores"
    private let managedStoresKey = "vee.managedStores"
    private let disablePublicKey = "vee.disablePublicStore"
    private let disabledIDsKey = "vee.disabledStoreIDs"

    public init(
        defaults: UserDefaults = .standard,
        makeTokenStore: @escaping (StoreID) -> StoreTokenStoring = { KeychainStoreTokenStore(storeID: $0) }
    ) {
        self.defaults = defaults
        self.makeTokenStore = makeTokenStore
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

    /// Stores the user added (excludes managed and built-in). An absent or
    /// empty blob is treated as "no custom stores yet". A present-but-
    /// undecodable blob is *also* reported as `[]` here — this is the read
    /// path used for display (`stores()`, called on every menu-bar refresh),
    /// which has no good way to surface an error. `add`/`remove`/`update`
    /// use `loadUserStoresOrThrow()` below instead, which fails closed.
    public func userStores() -> [StoreConfig] {
        (try? loadUserStoresOrThrow()) ?? []
    }

    /// Like `userStores()`, but throws `.corruptUserStores` instead of
    /// silently treating a present-but-undecodable blob as empty. Mutators
    /// must use this: a read(`[]`)-modify-write over a swallowed decode
    /// failure would overwrite every existing custom store with just the one
    /// being added/edited (see `VarStore.loadOrThrow`, the same fix for the
    /// plugin-vars sidecar).
    private func loadUserStoresOrThrow() throws -> [StoreConfig] {
        guard let data = defaults.data(forKey: userStoresKey), !data.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([StoreConfig].self, from: data)
        } catch {
            throw StoreRegistryError.corruptUserStores
        }
    }

    /// Adds a user store. Rejects the built-in id, a managed id, a duplicate
    /// id, or a store whose (kind, repo)/(kind, baseURL) identity already
    /// matches an existing user or built-in store under a different id.
    public func add(_ store: StoreConfig) throws {
        guard store.id != BuiltInStores.xbarID else { throw StoreRegistryError.builtInImmutable }
        guard !managedStores().contains(where: { $0.id == store.id }) else { throw StoreRegistryError.managedImmutable }
        var stores = try loadUserStoresOrThrow()
        guard !stores.contains(where: { $0.id == store.id }) else { throw StoreRegistryError.duplicateID(store.id.rawValue) }
        if let identity = store.storeIdentity,
           let clash = ([BuiltInStores.xbar] + stores).first(where: { $0.storeIdentity == identity }) {
            throw StoreRegistryError.duplicateStore(clash.displayName)
        }
        var normalized = store
        normalized.isBuiltIn = false
        normalized.isManaged = false
        stores.append(normalized)
        try writeUserStores(stores)
    }

    /// Removes a user store and drops its Keychain token. Rejects built-in
    /// and managed ids.
    public func remove(_ id: StoreID) throws {
        guard id != BuiltInStores.xbarID else { throw StoreRegistryError.builtInImmutable }
        guard !managedStores().contains(where: { $0.id == id }) else { throw StoreRegistryError.managedImmutable }
        var stores = try loadUserStoresOrThrow()
        guard stores.contains(where: { $0.id == id }) else { throw StoreRegistryError.notFound(id.rawValue) }
        stores.removeAll { $0.id == id }
        try writeUserStores(stores)
        // Drop the disabled flag and the Keychain token for a store that no
        // longer exists. Lives here (not just the Settings UI) so every
        // caller drops the secret — nothing routes around it and orphans
        // `com.vee.store.<id>`.
        setDisabled(false, id: id)
        makeTokenStore(id).set(nil)
    }

    /// Replaces a user store's config. Rejects built-in and managed ids.
    public func update(_ store: StoreConfig) throws {
        guard store.id != BuiltInStores.xbarID else { throw StoreRegistryError.builtInImmutable }
        guard !managedStores().contains(where: { $0.id == store.id }) else { throw StoreRegistryError.managedImmutable }
        var stores = try loadUserStoresOrThrow()
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

// MARK: - Duplicate identity

/// A store's effective identity for add-time dedup, independent of its id —
/// the Add-store sheet mints a random `user-<uuid>` id every time, so the
/// same repo or root would otherwise be addable under any number of ids.
/// `kind` is part of the identity: a GitHub and a GitHub Enterprise entry
/// with the same owner/repo never collide.
private enum StoreIdentity: Hashable {
    case repo(StoreKind, owner: String, repo: String)
    case root(StoreKind, baseURL: String)
}

private extension StoreConfig {
    /// `nil` when the store doesn't carry the fields its kind needs for a
    /// comparison — shouldn't happen for anything built by the Add-store
    /// sheet, but a hand-built `StoreConfig` (e.g. in a test) missing
    /// `owner`/`repo`/`baseURL` simply skips the dedup check rather than
    /// crashing or false-positiving.
    var storeIdentity: StoreIdentity? {
        switch kind {
        case .github, .githubEnterprise:
            guard let owner, let repo else { return nil }
            return .repo(kind, owner: Self.normalized(owner), repo: Self.normalizedRepo(repo))
        case .http, .local:
            guard let baseURL else { return nil }
            return .root(kind, baseURL: Self.normalized(baseURL.absoluteString))
        }
    }

    /// Case-insensitive, trailing-slash-insensitive.
    private static func normalized(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }

    /// `normalized`, plus a trailing `.git` suffix (as in `owner/repo.git`).
    private static func normalizedRepo(_ s: String) -> String {
        var t = normalized(s)
        if t.hasSuffix(".git") { t.removeLast(4) }
        return t
    }
}
