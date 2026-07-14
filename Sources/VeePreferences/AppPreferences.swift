import Foundation

/// App-wide (not per-plugin) preferences, backed by `UserDefaults`. Currently
/// tracks which plugins the user has disabled.
/// `@unchecked Sendable`: `UserDefaults` is thread-safe.
public final class AppPreferences: @unchecked Sendable {
    public static let shared = AppPreferences()

    private let defaults: UserDefaults
    private let disabledKey = "vee.disabledPluginIDs"
    private let directoryKey = "vee.pluginsDirectory"
    private let hotkeyOffKey = "vee.hotkeyDisabledPluginIDs"
    private let hotkeyCustomKey = "vee.hotkeyCustomBindings"
    private let firstRunDoneKey = "vee.hasCompletedFirstRun"
    private let compactMenuBarKey = "vee.compactMenuBar"
    private let searchAllHotkeyEnabledKey = "vee.searchAllHotkeyEnabled"
    private let searchAllHotkeyComboKey = "vee.searchAllHotkeyCombo"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Opt-in "compact menu bar" (issue #45 — menu-bar crowding): collapses
    /// every plugin's status item into a submenu of one shared Vee status
    /// item, instead of one item per plugin. Default off — zero behavior
    /// change until a user opts in.
    public var compactMenuBar: Bool {
        get { defaults.bool(forKey: compactMenuBarKey) }
        set {
            defaults.set(newValue, forKey: compactMenuBarKey)
            // Lets every already-running `StatusItemController` switch
            // presentation live — see `StatusItemController.reconcileMode()`.
            NotificationCenter.default.post(name: Self.compactMenuBarDidChangeNotification, object: nil)
        }
    }

    /// Posted whenever `compactMenuBar` changes, from any `AppPreferences`
    /// instance. Carries no payload — observers re-read the (possibly
    /// injected) instance they already hold to decide what changed.
    public static let compactMenuBarDidChangeNotification = Notification.Name("vee.compactMenuBarDidChange")

    /// Whether the app has completed its first-run onboarding. Used to open
    /// Discover once for a brand-new user with an empty plugins folder.
    public var hasCompletedFirstRun: Bool {
        get { defaults.bool(forKey: firstRunDoneKey) }
        set { defaults.set(newValue, forKey: firstRunDoneKey) }
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

    // MARK: - Per-plugin global-hotkey override

    /// Whether the user has turned off this plugin's declared search hotkey.
    public func isHotkeyDisabled(_ id: String) -> Bool {
        Set(defaults.stringArray(forKey: hotkeyOffKey) ?? []).contains(id)
    }

    public func setHotkeyDisabled(_ disabled: Bool, id: String) {
        var ids = Set(defaults.stringArray(forKey: hotkeyOffKey) ?? [])
        if disabled { ids.insert(id) } else { ids.remove(id) }
        defaults.set(Array(ids), forKey: hotkeyOffKey)
    }

    /// A user-chosen replacement combination (e.g. `"cmd+shift+j"`) for this
    /// plugin's hotkey, or `nil` to use the plugin's declared one.
    public func hotkeyBinding(_ id: String) -> String? {
        (defaults.dictionary(forKey: hotkeyCustomKey) as? [String: String])?[id]
    }

    public func setHotkeyBinding(_ binding: String?, id: String) {
        var map = (defaults.dictionary(forKey: hotkeyCustomKey) as? [String: String]) ?? [:]
        if let binding, !binding.isEmpty { map[id] = binding } else { map.removeValue(forKey: id) }
        defaults.set(map, forKey: hotkeyCustomKey)
    }

    // MARK: - Cross-plugin "Search All Plugins" hotkey

    /// Whether the user opted into the app-level global hotkey that opens the
    /// cross-plugin search panel. Unlike a plugin's declared `<vee.shortcut>`
    /// (on by default once declared), there is no default combination to
    /// squat here, so this defaults to `false` — inert until the user both
    /// enables it and supplies a combo.
    public var searchAllHotkeyEnabled: Bool {
        get { defaults.bool(forKey: searchAllHotkeyEnabledKey) }
        set { defaults.set(newValue, forKey: searchAllHotkeyEnabledKey) }
    }

    /// The user-chosen combination (e.g. `"cmd+shift+/"`) for the cross-plugin
    /// search hotkey, or `nil` when never set.
    public var searchAllHotkeyCombo: String? {
        get { defaults.string(forKey: searchAllHotkeyComboKey) }
        set { defaults.set(newValue, forKey: searchAllHotkeyComboKey) }
    }
}
