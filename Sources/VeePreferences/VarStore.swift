import Foundation

/// Persists a plugin's non-secret declared-variable values to a JSON sidecar
/// next to the plugin (`<plugin>.vars.json`) — the same convention SwiftBar
/// uses, so values are portable.
public struct VarStore {
    public let sidecarPath: String

    /// A sidecar that exists but doesn't decode as the expected
    /// `[String: String]` JSON — distinct from "absent" or "empty", both of
    /// which are safe to treat as no stored variables.
    public enum StoreError: Error, Equatable, Sendable {
        case corruptSidecar
    }

    public init(pluginPath: String) {
        self.sidecarPath = pluginPath + ".vars.json"
    }

    public func load() -> [String: String] {
        (try? loadOrThrow()) ?? [:]
    }

    /// Like `load()`, but fails closed: an absent or genuinely empty sidecar
    /// decodes to `[:]` (safe to proceed), while a *present but undecodable*
    /// one throws instead of silently being treated as empty. Callers that
    /// only read (`load()`, `value(for:)`) can ignore that distinction; `set`
    /// must not, since load→mutate→save over a swallowed decode failure would
    /// clobber every other stored variable for the plugin.
    private func loadOrThrow() throws -> [String: String] {
        guard let data = FileManager.default.contents(atPath: sidecarPath), !data.isEmpty else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw StoreError.corruptSidecar
        }
    }

    public func save(_ values: [String: String]) throws {
        let data = try JSONEncoder().encode(values)
        try data.write(to: URL(fileURLWithPath: sidecarPath), options: .atomic)
    }

    public func value(for name: String) -> String? {
        load()[name]
    }

    /// Sets (or clears, when `value` is nil) a single variable and rewrites the
    /// sidecar. Throws `StoreError.corruptSidecar` — without writing anything —
    /// if the existing sidecar is present but undecodable, rather than
    /// overwriting it with a single-key doc.
    public func set(_ value: String?, for name: String) throws {
        var values = try loadOrThrow()
        values[name] = value
        try save(values)
    }
}
