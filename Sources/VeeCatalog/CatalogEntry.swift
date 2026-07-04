import Foundation

/// A plugin available in the shared xbar/SwiftBar catalog
/// (`matryer/xbar-plugins`).
public struct CatalogEntry: Identifiable, Sendable, Equatable {
    /// Repo-relative path, e.g. `System/CPU/cpu_percent.5s.sh`.
    public var path: String
    /// The category (top-level directory), e.g. `System`.
    public var category: String
    /// The plugin's filename, e.g. `cpu_percent.5s.sh`.
    public var filename: String
    /// Where to download the raw script from.
    public var rawURL: URL

    public var id: String { path }

    public init(path: String, category: String, filename: String, rawURL: URL) {
        self.path = path
        self.category = category
        self.filename = filename
        self.rawURL = rawURL
    }
}
