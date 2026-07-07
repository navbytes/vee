import Foundation

/// A stable identifier for a configured store (the built-in public catalog, an
/// enterprise's internal catalog, an air-gapped mirror, …).
public struct StoreID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// Where a store lives and how its index is reached.
public enum StoreKind: String, Codable, Sendable {
    /// A GitHub repo reached via `api.github.com` (public or private).
    case github
    /// A GitHub Enterprise Server repo reached via a customer API host.
    case githubEnterprise
    /// A plain static host serving a manifest + raw sources (requires a manifest).
    case http
    /// A `file://` directory — an air-gapped/on-prem mirror.
    case local
}

/// How loudly the install gate frames a store. This changes *framing and default
/// posture only* — it never enforces an OS sandbox and never hides a detected
/// capability. Consistent with Vee's advisory trust model.
public enum StoreTrustPolicy: String, Codable, Sendable {
    /// The public catalog: full warnings, no default action.
    case publicUntrusted
    /// An internally-reviewed source: streamlined framing, warnings still shown.
    case internalReviewed
}

/// Whether a store's requests carry credentials.
public enum StoreAuthMode: String, Codable, Sendable {
    case none
    /// A bearer token, sourced from the Keychain (never from managed defaults or
    /// the plugin environment).
    case token
}

/// Describes one plugin store. A `StoreConfig` is all a `GitHubCatalogClient`
/// (or the other clients) needs to know where to fetch an index and sources.
///
/// The public xbar catalog is itself a `StoreConfig` (``BuiltInStores/xbar``),
/// so with no custom store configured Vee behaves exactly as before.
public struct StoreConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: StoreID
    /// User-facing name shown in Discover and the Stores settings tab.
    public var displayName: String
    public var kind: StoreKind
    /// Whether the store appears in Discover. Managed stores are force-enabled.
    public var isEnabled: Bool
    /// The built-in public catalog — always present, not removable.
    public var isBuiltIn: Bool
    /// Delivered via MDM: read-only and force-enabled in the UI.
    public var isManaged: Bool

    // Location — which fields apply depends on `kind`.
    /// API base for `github`/`githubEnterprise` (e.g. `https://api.github.com`).
    public var apiHost: URL?
    /// Raw-content base for `github`/`githubEnterprise`
    /// (e.g. `https://raw.githubusercontent.com`).
    public var rawHost: URL?
    /// Repo owner for `github`/`githubEnterprise`.
    public var owner: String?
    /// Repo name for `github`/`githubEnterprise`.
    public var repo: String?
    /// Branch/tag/sha to read from. Defaults to `main`.
    public var ref: String
    /// Index + source root for `http`/`local` stores.
    public var baseURL: URL?
    /// Where the optional curation manifest lives, relative to the store root.
    public var manifestPath: String

    // Security posture.
    public var trustPolicy: StoreTrustPolicy
    public var authMode: StoreAuthMode
    /// Reject an unsigned or invalid-signature plugin at install. Client-side —
    /// a store cannot lower this.
    public var requireSignature: Bool
    /// A base64 Ed25519 public key pinned by policy, overriding any key the
    /// manifest advertises.
    public var pinnedSigningKey: String?

    public init(
        id: StoreID,
        displayName: String,
        kind: StoreKind,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        isManaged: Bool = false,
        apiHost: URL? = nil,
        rawHost: URL? = nil,
        owner: String? = nil,
        repo: String? = nil,
        ref: String = "main",
        baseURL: URL? = nil,
        manifestPath: String = "vee-catalog.json",
        trustPolicy: StoreTrustPolicy = .publicUntrusted,
        authMode: StoreAuthMode = .none,
        requireSignature: Bool = false,
        pinnedSigningKey: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.isManaged = isManaged
        self.apiHost = apiHost
        self.rawHost = rawHost
        self.owner = owner
        self.repo = repo
        self.ref = ref
        self.baseURL = baseURL
        self.manifestPath = manifestPath
        self.trustPolicy = trustPolicy
        self.authMode = authMode
        self.requireSignature = requireSignature
        self.pinnedSigningKey = pinnedSigningKey
    }
}

public extension StoreConfig {
    /// Builds a managed store from an MDM-delivered dictionary (the entries of
    /// the `vee.managedStores` defaults array). Returns `nil` if the required
    /// `id`, `displayName`, and a valid `kind` are missing. The result is always
    /// `isManaged: true` and force-enabled; secrets are never sourced here.
    init?(managedDictionary d: [String: Any]) {
        guard let idString = d["id"] as? String, !idString.isEmpty,
              let name = d["displayName"] as? String,
              let kindString = d["kind"] as? String,
              let kind = StoreKind(rawValue: kindString)
        else { return nil }

        func url(_ key: String) -> URL? {
            (d[key] as? String).flatMap(URL.init(string:))
        }

        self.init(
            id: StoreID(idString),
            displayName: name,
            kind: kind,
            isEnabled: true,
            isBuiltIn: false,
            isManaged: true,
            apiHost: url("apiHost"),
            rawHost: url("rawHost"),
            owner: d["owner"] as? String,
            repo: d["repo"] as? String,
            ref: (d["ref"] as? String) ?? "main",
            baseURL: url("baseURL"),
            manifestPath: (d["manifestPath"] as? String) ?? "vee-catalog.json",
            trustPolicy: (d["trustPolicy"] as? String).flatMap(StoreTrustPolicy.init(rawValue:)) ?? .internalReviewed,
            authMode: (d["authMode"] as? String).flatMap(StoreAuthMode.init(rawValue:)) ?? .none,
            requireSignature: (d["requireSignature"] as? Bool) ?? false,
            pinnedSigningKey: d["pinnedSigningKey"] as? String
        )
    }
}

/// The stores Vee ships with.
public enum BuiltInStores {
    /// The identifier of the built-in public xbar catalog.
    public static let xbarID = StoreID("com.vee.store.xbar")

    /// The public `matryer/xbar-plugins` catalog, expressed as a `StoreConfig`.
    /// Its endpoints reproduce the URLs Vee used before custom stores existed
    /// (see `StoreEndpoints`), so single-store behavior is unchanged.
    public static var xbar: StoreConfig {
        StoreConfig(
            id: xbarID,
            displayName: "Public xbar catalog",
            kind: .github,
            isEnabled: true,
            isBuiltIn: true,
            isManaged: false,
            apiHost: URL(string: "https://api.github.com"),
            rawHost: URL(string: "https://raw.githubusercontent.com"),
            owner: "matryer",
            repo: "xbar-plugins",
            ref: "main",
            trustPolicy: .publicUntrusted,
            authMode: .none
        )
    }
}
