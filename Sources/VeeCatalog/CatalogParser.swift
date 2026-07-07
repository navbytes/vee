import Foundation

/// Parses the GitHub Git-Trees API response for `matryer/xbar-plugins` into
/// catalog entries. Pure and testable (no network).
public enum CatalogParser {
    /// The public xbar catalog's raw-content base. Used as the default so callers
    /// that don't pass a store's `repoBase` keep the original behavior.
    public static let defaultRepoBase = "https://raw.githubusercontent.com/matryer/xbar-plugins/main/"

    /// Top-level entries that are repo scaffolding, not plugin categories.
    private static let ignoredTopLevel: Set<String> = [
        ".github", "docs", "images", "assets"
    ]

    private static let ignoredExtensions: Set<String> = [
        "md", "markdown", "txt", "json", "png", "jpg", "jpeg", "gif", "svg",
        "yml", "yaml", "lock", "gitignore"
    ]

    private struct Tree: Decodable {
        let tree: [Node]
        struct Node: Decodable {
            let path: String
            let type: String
        }
    }

    /// Parses a Git-Trees response into catalog entries.
    ///
    /// - Parameters:
    ///   - data: The Git-Trees API JSON.
    ///   - repoBase: The raw-content base (with trailing slash) to build source
    ///     URLs from. Defaults to the public xbar catalog so existing callers are
    ///     unchanged; a custom store passes `StoreEndpoints(config).rawBase`.
    ///   - storeID: Which store these entries belong to. Defaults to the built-in
    ///     xbar catalog.
    public static func parse(
        treeJSON data: Data,
        repoBase: String = CatalogParser.defaultRepoBase,
        storeID: StoreID = BuiltInStores.xbarID
    ) throws -> [CatalogEntry] {
        let tree = try JSONDecoder().decode(Tree.self, from: data)
        return tree.tree.compactMap { node -> CatalogEntry? in
            guard node.type == "blob" else { return nil }
            let components = node.path.split(separator: "/").map(String.init)
            // A plugin lives under a category directory: at least Category/file.
            guard components.count >= 2 else { return nil }
            let category = components[0]
            guard !ignoredTopLevel.contains(category) else { return nil }

            let filename = components[components.count - 1]
            guard !filename.hasPrefix(".") else { return nil }
            let ext = (filename as NSString).pathExtension.lowercased()
            guard !ignoredExtensions.contains(ext) else { return nil }
            guard let encoded = node.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let rawURL = URL(string: repoBase + encoded) else { return nil }

            return CatalogEntry(storeID: storeID, path: node.path, category: category, filename: filename, rawURL: rawURL)
        }
        .sorted { $0.path < $1.path }
    }

    private struct Commit: Decodable {
        let commit: Detail
        struct Detail: Decodable {
            let committer: Committer
            struct Committer: Decodable { let date: String }
        }
    }

    /// Parses the GitHub commits API response (`/commits?path=…&per_page=1`) and
    /// returns the first commit's committer date, or `nil` if the payload is
    /// empty or malformed. Pure and testable (no network).
    public static func parseLastCommitDate(commitsJSON data: Data) -> Date? {
        guard let commits = try? JSONDecoder().decode([Commit].self, from: data),
              let iso = commits.first?.commit.committer.date
        else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }
}
