import Foundation

/// Persists a plugin's non-secret declared-variable values to a JSON sidecar
/// next to the plugin (`<plugin>.vars.json`) — the same convention SwiftBar
/// uses, so values are portable.
public struct VarStore {
    public let sidecarPath: String

    public init(pluginPath: String) {
        self.sidecarPath = pluginPath + ".vars.json"
    }

    public func load() -> [String: String] {
        guard let data = FileManager.default.contents(atPath: sidecarPath),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    public func save(_ values: [String: String]) throws {
        let data = try JSONEncoder().encode(values)
        try data.write(to: URL(fileURLWithPath: sidecarPath), options: .atomic)
    }

    public func value(for name: String) -> String? {
        load()[name]
    }

    /// Sets (or clears, when `value` is nil) a single variable and rewrites the
    /// sidecar.
    public func set(_ value: String?, for name: String) throws {
        var values = load()
        values[name] = value
        try save(values)
    }
}
