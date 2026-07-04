import XCTest
@testable import VeePluginFormat

/// Helpers for unwrapping the menu tree in assertions.
extension MenuNode {
    var item: MenuItem? {
        if case .item(let i) = self { return i }
        return nil
    }
    var isSeparator: Bool {
        if case .separator = self { return true }
        return false
    }
}

extension Array where Element == MenuNode {
    /// The items in this node list (skipping separators).
    var items: [MenuItem] { compactMap(\.item) }
}
