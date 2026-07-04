import Foundation

/// App-wide (not per-plugin) preferences, backed by `UserDefaults`. Currently
/// tracks which plugins the user has disabled.
/// `@unchecked Sendable`: `UserDefaults` is thread-safe.
public final class AppPreferences: @unchecked Sendable {
    public static let shared = AppPreferences()

    private let defaults: UserDefaults
    private let disabledKey = "vee.disabledPluginIDs"
    private let directoryKey = "vee.pluginsDirectory"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A user-chosen plugins directory (e.g. an existing SwiftBar folder), or
    /// `nil` to use the default.
    public var pluginsDirectory: String? {
        get { defaults.string(forKey: directoryKey) }
        set { defaults.set(newValue, forKey: directoryKey) }
    }

    public func disabledIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: disabledKey) ?? [])
    }

    public func isDisabled(_ id: String) -> Bool {
        disabledIDs().contains(id)
    }

    public func setDisabled(_ disabled: Bool, id: String) {
        var ids = disabledIDs()
        if disabled { ids.insert(id) } else { ids.remove(id) }
        defaults.set(Array(ids), forKey: disabledKey)
    }
}
