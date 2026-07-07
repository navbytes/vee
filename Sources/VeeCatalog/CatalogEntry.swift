import Foundation

/// A plugin available in the shared xbar/SwiftBar catalog
/// (`matryer/xbar-plugins`).
public struct CatalogEntry: Identifiable, Sendable, Equatable {
    /// Which store this entry came from. Defaults to the built-in xbar catalog so
    /// existing single-store call sites are unchanged.
    public var storeID: StoreID
    /// Repo-relative path, e.g. `System/CPU/cpu_percent.5s.sh`.
    public var path: String
    /// The category (top-level directory), e.g. `System`.
    public var category: String
    /// The plugin's filename, e.g. `cpu_percent.5s.sh`.
    public var filename: String
    /// Where to download the raw script from.
    public var rawURL: URL
    /// When the plugin was last changed upstream (last commit that touched
    /// `path`). Populated lazily — `nil` until fetched via
    /// ``CatalogFetching/fetchLastUpdated(_:)`` — because it costs one API call
    /// per plugin.
    public var lastUpdated: Date?
    /// Manifest-supplied title, if the store publishes a `vee-catalog.json`.
    /// `nil` under the zero-config convention (title is read lazily instead).
    public var manifestTitle: String?
    /// Manifest-supplied summary, if any.
    public var manifestSummary: String?
    /// Manifest-pinned lowercase-hex SHA-256 of the source. When present, the
    /// installer verifies the fetched source against it.
    public var declaredSHA256: String?
    /// Base64 Ed25519 signature over the source's SHA-256 bytes, if signed.
    public var signature: String?
    /// Minimum macOS version the plugin declares it needs (e.g. `26.0`).
    public var minMacOS: String?
    /// Whether the store marks this plugin deprecated.
    public var deprecated: Bool

    /// Unique across stores: two stores may carry the same repo-relative path.
    public var id: String { "\(storeID.rawValue)#\(path)" }

    public init(
        storeID: StoreID = BuiltInStores.xbarID,
        path: String,
        category: String,
        filename: String,
        rawURL: URL,
        lastUpdated: Date? = nil,
        manifestTitle: String? = nil,
        manifestSummary: String? = nil,
        declaredSHA256: String? = nil,
        signature: String? = nil,
        minMacOS: String? = nil,
        deprecated: Bool = false
    ) {
        self.storeID = storeID
        self.path = path
        self.category = category
        self.filename = filename
        self.rawURL = rawURL
        self.lastUpdated = lastUpdated
        self.manifestTitle = manifestTitle
        self.manifestSummary = manifestSummary
        self.declaredSHA256 = declaredSHA256
        self.signature = signature
        self.minMacOS = minMacOS
        self.deprecated = deprecated
    }
}
