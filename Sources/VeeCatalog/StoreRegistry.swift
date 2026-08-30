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
/// - **Built-in** — `vee-plugins` and the public xbar catalog, appended
///   unless the managed `vee.disablePublicStore` flag is set.
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
    /// VeePreferences' first-run flag, read directly: `VeeCatalog` doesn't
    /// depend on `VeePreferences`, and both read the same `UserDefaults` in
    /// production. Used only by `seedDefaultStoresIfNeeded()`.
    private let hasCompletedFirstRunKey = "vee.hasCompletedFirstRun"
    private let didSeedDefaultStoresKey = "vee.didSeedDefaultStores"

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
    /// id. Order: managed first, then user, then the built-in catalogs
    /// (`vee-plugins`, then `xbar`) last.
    public func stores() -> [StoreConfig] {
        let managed = managedStores()
        let managedIDs = Set(managed.map(\.id))
        let disabled = disabledIDs()

        var result = managed

        for var store in userStores() where !managedIDs.contains(store.id) {
            store.isEnabled = !disabled.contains(store.id)
            result.append(store)
        }

        if !defaults.bool(forKey: disablePublicKey) {
            for var builtIn in BuiltInStores.all where !managedIDs.contains(builtIn.id) {
                builtIn.isEnabled = !disabled.contains(builtIn.id)
                result.append(builtIn)
            }
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
    /// id, or a store whose (kind, repo, ref)/(kind, baseURL) identity
    /// already matches an existing user, built-in, or managed store under a
    /// different id.
    public func add(_ store: StoreConfig) throws {
        guard !BuiltInStores.allIDs.contains(store.id) else { throw StoreRegistryError.builtInImmutable }
        let managed = managedStores()
        guard !managed.contains(where: { $0.id == store.id }) else { throw StoreRegistryError.managedImmutable }
        var stores = try loadUserStoresOrThrow()
        guard !stores.contains(where: { $0.id == store.id }) else { throw StoreRegistryError.duplicateID(store.id.rawValue) }
        if let identity = store.storeIdentity,
           let clash = (BuiltInStores.all + stores + managed).first(where: { $0.storeIdentity == identity }) {
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
        guard !BuiltInStores.allIDs.contains(id) else { throw StoreRegistryError.builtInImmutable }
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
        guard !BuiltInStores.allIDs.contains(store.id) else { throw StoreRegistryError.builtInImmutable }
        guard !managedStores().contains(where: { $0.id == store.id }) else { throw StoreRegistryError.managedImmutable }
        var stores = try loadUserStoresOrThrow()
        guard let idx = stores.firstIndex(where: { $0.id == store.id }) else { throw StoreRegistryError.notFound(store.id.rawValue) }
        var normalized = store
        normalized.isManaged = false
        normalized.isBuiltIn = false
        stores[idx] = normalized
        try writeUserStores(stores)
    }

    // MARK: - Default-store seeding

    /// One-shot: on a genuinely fresh install, `xbar` ships disabled by
    /// default in favor of `vee-plugins`, Vee's new default catalog. An
    /// existing install — where `vee.hasCompletedFirstRun` is already `true`
    /// — keeps `xbar` enabled exactly as before, since `disabledIDs()` alone
    /// can't tell "never touched Stores" apart from "fresh install".
    ///
    /// Gated by its own one-shot flag, so calling this more than once (e.g.
    /// once per launch) only ever seeds on the first call. That first call
    /// MUST happen before `vee.hasCompletedFirstRun` is set — otherwise every
    /// install looks "existing" and `xbar` never gets seeded disabled.
    public func seedDefaultStoresIfNeeded() {
        guard !defaults.bool(forKey: didSeedDefaultStoresKey) else { return }
        defaults.set(true, forKey: didSeedDefaultStoresKey)
        guard !defaults.bool(forKey: hasCompletedFirstRunKey) else { return }
        setDisabled(true, id: BuiltInStores.xbarID)
    }

    // MARK: - Enable / disable

    /// Enables or disables a store. Managed stores are force-enabled — this is a
    /// no-op for them. The built-in catalogs and user stores are toggled via a
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
///
/// `kind` is always part of the identity, so a GitHub and a GitHub
/// Enterprise entry with the same owner/repo never collide. For
/// `.githubEnterprise` the (normalized) API host is *also* part of the
/// identity: orgs commonly standardize repo names across staging/prod GHE
/// instances, so owner/repo alone would falsely dedupe two different
/// servers. `ref` is part of the identity too — the same repo at two
/// different refs (e.g. a stable and a beta branch) is a legitimately
/// distinct catalog, not a duplicate.
private enum StoreIdentity: Hashable {
    case repo(StoreKind, apiHost: String, owner: String, repo: String, ref: String)
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
        case .github:
            guard let owner, let repo else { return nil }
            // No host component: `.github` always means api.github.com, so
            // comparing the actual `apiHost` field would only make identity
            // depend on whether a caller happened to fill it in, not on
            // anything that actually distinguishes stores.
            return .repo(kind, apiHost: "", owner: Self.normalized(owner), repo: Self.normalizedRepo(repo), ref: Self.normalizedRef(ref))
        case .githubEnterprise:
            guard let owner, let repo else { return nil }
            return .repo(
                kind, apiHost: apiHost.map(Self.normalizedURL) ?? "",
                owner: Self.normalized(owner), repo: Self.normalizedRepo(repo), ref: Self.normalizedRef(ref)
            )
        case .http, .local:
            guard let baseURL else { return nil }
            return .root(kind, baseURL: Self.normalizedURL(baseURL))
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

    /// Trimmed only — unlike owner/repo, a git ref/branch name is genuinely
    /// case-sensitive (`Release` and `release` can be two different
    /// branches), so lowercasing it risks a false-positive dedupe.
    private static func normalizedRef(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Host lowercased (DNS is case-insensitive) — scheme, port, and path are
    /// preserved as-is, since a server path can be case-sensitive (e.g.
    /// `/CatalogA` and `/cataloga` are different roots). Trailing slash(es)
    /// stripped either way.
    private static func normalizedURL(_ url: URL) -> String {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host() ?? "").lowercased()
        let port = url.port.map { ":\($0)" } ?? ""
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return "\(scheme)://\(host)\(port)\(path)"
    }
}
