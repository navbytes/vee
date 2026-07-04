import Foundation

/// Parses the GitHub Git-Trees API response for `matryer/xbar-plugins` into
/// catalog entries. Pure and testable (no network).
public enum CatalogParser {
    private static let repoBase = "https://raw.githubusercontent.com/matryer/xbar-plugins/main/"

    /// Top-level entries that are repo scaffolding, not plugin categories.
    private static let ignoredTopLevel: Set<String> = [
        ".github", "docs", "images", "assets",
    ]

    private static let ignoredExtensions: Set<String> = [
        "md", "markdown", "txt", "json", "png", "jpg", "jpeg", "gif", "svg",
        "yml", "yaml", "lock", "gitignore",
    ]

    private struct Tree: Decodable {
        let tree: [Node]
        struct Node: Decodable {
            let path: String
            let type: String
        }
    }

    public static func parse(treeJSON data: Data) throws -> [CatalogEntry] {
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
            guard let rawURL = URL(string: repoBase + node.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else { return nil }

            return CatalogEntry(path: node.path, category: category, filename: filename, rawURL: rawURL)
        }
        .sorted { $0.path < $1.path }
    }
}
