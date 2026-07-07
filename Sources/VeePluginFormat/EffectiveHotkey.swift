import Foundation

/// Resolves which global hotkey (if any) a plugin should actually register,
/// combining the plugin's declared `<vee.shortcut>` with the user's per-plugin
/// override (disable / rebind). Pure and unit-tested so the precedence — the
/// heart of the "controllable hotkey" feature — is verified without the UI.
public enum EffectiveHotkey {
    public enum Resolution: Equatable, Sendable {
        /// The plugin declares no hotkey — nothing to control or register.
        case none
        /// The user turned the (declared) hotkey off.
        case disabled
        /// The user's custom binding doesn't parse into a valid shortcut.
        case invalid
        /// Register this shortcut.
        case use(HotKeySpec)
    }

    /// Precedence: a plugin with no declared hotkey is never controllable; a
    /// user "off" wins; a custom binding (when present) overrides the declared
    /// one, and an unparseable custom binding is surfaced as `.invalid` rather
    /// than silently falling back.
    public static func resolve(declared: HotKeySpec?, userDisabled: Bool, customBinding: String?) -> Resolution {
        guard let declared else { return .none }
        if userDisabled { return .disabled }
        if let customBinding, !customBinding.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = HotKeySpec.parse(customBinding) else { return .invalid }
            return .use(parsed)
        }
        return .use(declared)
    }
}
