import Foundation
import VeePluginFormat

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
    private let hotkeyPresentationKey = "vee.hotkeyPresentations"
    private let firstRunDoneKey = "vee.hasCompletedFirstRun"
    private let compactMenuBarKey = "vee.compactMenuBar"
    private let secretPluginIDsKey = "vee.pluginsWithSecrets"
    private let seenPluginIDsKey = "vee.seenPluginIDs"
    private let pluginHomeKey = "vee.pluginHomeDirectories"
    private let detachedWindowPinnedKey = "vee.detachedWindowPinned"
    private let focusWindowsHotkeyKey = "vee.focusWindowsHotkey"

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

    /// Every plugin id with a stored hotkey-off flag — the enumerable
    /// companion to `isHotkeyDisabled(_:)`. Used by disk reconciliation
    /// (`AppController.reconcileDiskState`) to find candidate filenames whose
    /// file might no longer exist; production code only ever needs the
    /// per-id check above.
    public func hotkeyDisabledIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: hotkeyOffKey) ?? [])
    }

    /// Every plugin id with a stored custom hotkey binding — the enumerable
    /// companion to `hotkeyBinding(_:)`, for the same reconciliation use.
    /// Which presentation this plugin's hotkey opens. Absent means the default
    /// (the transient panel), so a plugin that declared a hotkey before this
    /// choice existed is unaffected.
    public func hotkeyPresentation(_ id: String) -> HotkeyPresentation {
        HotkeyPresentation.resolve((defaults.dictionary(forKey: hotkeyPresentationKey) as? [String: String])?[id])
    }

    public func setHotkeyPresentation(_ presentation: HotkeyPresentation, id: String) {
        var map = (defaults.dictionary(forKey: hotkeyPresentationKey) as? [String: String]) ?? [:]
        // Store only a departure from the default, so the map stays empty for
        // the overwhelming majority of plugins and `clearAllState` has less to
        // undo.
        if presentation == .default { map.removeValue(forKey: id) } else { map[id] = presentation.rawValue }
        defaults.set(map, forKey: hotkeyPresentationKey)
    }

    public func hotkeyBindingIDs() -> Set<String> {
        Set((defaults.dictionary(forKey: hotkeyCustomKey) as? [String: String] ?? [:]).keys)
    }

    /// Clears every stored preference for `id` — disabled flag, hotkey-off
    /// flag, custom hotkey binding, hotkey presentation, and the has-a-secret
    /// marker — leaving
    /// every other plugin's prefs untouched. Used when disk reconciliation
    /// confirms `id`'s file no longer exists (a manual delete, or an in-app
    /// delete); reuses the existing per-field mutators rather than touching
    /// `UserDefaults` directly, so this can never drift from them.
    public func clearAllState(id: String) {
        setDisabled(false, id: id)
        setHotkeyDisabled(false, id: id)
        setHotkeyBinding(nil, id: id)
        setHotkeyPresentation(.default, id: id)
        setHasSecret(false, id: id)
    }

    // MARK: - Has-a-secret marker

    /// Every plugin id that has (or, best-effort, once had) a Keychain
    /// secret stored through `PluginPreferences` — a lightweight marker so
    /// disk reconciliation can find a "secret-only" plugin (no disabled
    /// flag, vars, or provenance record — nothing else that would put it in
    /// `reconcileDiskState`'s candidate set) whose file has since
    /// disappeared. Not a source of truth for what's actually in the
    /// Keychain, only for "this filename is worth checking".
    public func secretPluginIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: secretPluginIDsKey) ?? [])
    }

    /// Marks (or unmarks) `id` as having a stored secret. `PluginPreferences
    /// .setValue` calls this with `true` whenever it stores a non-empty
    /// secret value; `clearAllState` is the only place that ever calls it
    /// with `false` (once disk reconciliation has confirmed `id`'s file is
    /// genuinely gone) — a plugin clearing ONE of several declared secret
    /// vars must not un-mark it while another might still be set, so the
    /// marker only ever turns off at GC time, never at a single-field clear.
    public func setHasSecret(_ hasSecret: Bool, id: String) {
        var ids = secretPluginIDs()
        if hasSecret { ids.insert(id) } else { ids.remove(id) }
        defaults.set(Array(ids), forKey: secretPluginIDsKey)
    }

    // MARK: - Plugins Vee has ever loaded

    /// Every plugin ID Vee has loaded at least once, across all launches.
    ///
    /// Exists for one job: clearing the launch-on-demand XPC activities that
    /// earlier versions registered per plugin (`LegacyBackgroundActivity`).
    /// Those live in launchd rather than in the app, so they outlive the plugin
    /// that created one — and an identifier can only be constructed from the
    /// plugin's ID. Without a record of IDs Vee has *seen*, a plugin deleted
    /// before the clearing shipped leaves an activity nothing can ever name,
    /// and the app stays un-quittable forever.
    ///
    /// Deliberately never pruned. A plugin's removal is exactly the case this
    /// exists to survive, so garbage-collecting an entry when its file
    /// disappears would delete the only thing that makes the fix reachable.
    /// It costs one short string per plugin ever installed.
    public func seenPluginIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: seenPluginIDsKey) ?? [])
    }

    /// Records `ids` as loaded. Idempotent, and writes nothing when every ID is
    /// already known — this runs for every plugin on every launch.
    public func recordSeenPlugins(_ ids: some Sequence<String>) {
        let known = seenPluginIDs()
        let merged = known.union(ids)
        guard merged != known else { return }
        defaults.set(Array(merged), forKey: seenPluginIDsKey)
    }

    // MARK: - Which folder a plugin's state belongs to

    /// The plugins folder `filename` was last seen in, or `nil` if Vee has
    /// never recorded one.
    ///
    /// Every other piece of per-plugin state — the disabled flag, hotkeys, the
    /// secret marker, and the Keychain service `com.vee.plugin.<filename>` — is
    /// keyed by filename alone, with no directory component. That is fine while
    /// there is one plugins folder and wrong the moment there are two: disk
    /// reconciliation (`AppController.reconcileDiskState`) lists ONE directory
    /// and treats every record it doesn't find there as a deleted plugin whose
    /// state, secrets included, should be destroyed. Pointing Vee at a
    /// different folder would therefore wipe the credentials of every plugin in
    /// the folder you just switched away from, while those files sit intact
    /// where you left them.
    ///
    /// This is the scope the identity key is missing: reconciliation only
    /// collects a record whose home is the folder it is actually looking at.
    public func pluginHome(_ filename: String) -> String? {
        (defaults.dictionary(forKey: pluginHomeKey) as? [String: String])?[filename]
    }

    /// Records `directory` as the home of every filename in `filenames`.
    /// Idempotent, and writes nothing when nothing moved — this runs on every
    /// reconciliation, which is every reload.
    public func recordPluginHomes(_ filenames: some Sequence<String>, directory: String) {
        var homes = (defaults.dictionary(forKey: pluginHomeKey) as? [String: String]) ?? [:]
        let before = homes
        for filename in filenames { homes[filename] = directory }
        guard homes != before else { return }
        defaults.set(homes, forKey: pluginHomeKey)
    }

    /// Drops `filename`'s home record. Called from `clearAllState` so a
    /// genuinely-collected plugin doesn't leave an entry behind forever.
    public func clearPluginHome(_ filename: String) {
        guard var homes = defaults.dictionary(forKey: pluginHomeKey) as? [String: String],
              homes.removeValue(forKey: filename) != nil else { return }
        defaults.set(homes, forKey: pluginHomeKey)
    }

    // MARK: - Detached-window pinning

    /// Whether this plugin's detached window floats above other applications.
    /// Absent means pinned — the state every new window opens in — so only a
    /// user who unpinned one ever has an entry here, and the map stays empty
    /// for everyone else.
    public func isDetachedWindowPinned(_ id: String) -> Bool {
        (defaults.dictionary(forKey: detachedWindowPinnedKey) as? [String: Bool])?[id] ?? true
    }

    public func setDetachedWindowPinned(_ pinned: Bool, id: String) {
        var map = (defaults.dictionary(forKey: detachedWindowPinnedKey) as? [String: Bool]) ?? [:]
        if pinned { map.removeValue(forKey: id) } else { map[id] = false }
        defaults.set(map, forKey: detachedWindowPinnedKey)
    }

    /// The app-level combination that brings every open detached window to the
    /// front, or `nil` for unbound. One string rather than the per-plugin
    /// binding map: there is exactly one of this hotkey, and it is app-level
    /// rather than any plugin's. Absent is the shipped state — a global
    /// combination is contested space, so Vee claims none until asked to.
    public var focusWindowsHotkey: String? {
        get { defaults.string(forKey: focusWindowsHotkeyKey) }
        set { defaults.set(newValue, forKey: focusWindowsHotkeyKey) }
    }

}
