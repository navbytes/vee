import Foundation
import VeeProtocol

/// Plugin-declared preferences — the native side of Vee's Raycast-style
/// configuration model.
///
/// The application core hardcodes NO credential of its own. What is configurable
/// is entirely what each installed plugin DECLARED in its manifest
/// (``PluginPreference``). This file provides:
///
///   • `PreferenceValueStoring` — persistence for non-secret values.
///   • `PluginPreferencesStore` — the generic engine: routes secrets to the
///     Keychain (`TokenStoring`) and the rest to a `PreferenceValueStoring`,
///     resolves runtime values, and answers "is this command configured?".
///   • `PluginPreferenceProviding` — the narrow seam `AppCoordinator` depends on.
///
/// The Settings UI writes through `PluginPreferencesStore`; the coordinator reads
/// through `PluginPreferenceProviding` — neither ever names a specific service.

// MARK: - Non-secret value persistence

/// Persistence for NON-secret preference values (textfield / checkbox / dropdown).
/// Secret (`.password`) values never come here — they go to `TokenStoring`
/// (Keychain). Stored as `JSONValue` so a checkbox round-trips as a bool and a
/// textfield/dropdown as a string.
public protocol PreferenceValueStoring: AnyObject {
    func value(pluginId: String, name: String) -> JSONValue?
    func setValue(_ value: JSONValue, pluginId: String, name: String)
    func removeValue(pluginId: String, name: String)
}

/// `UserDefaults`-backed plain store. Keys are namespaced per plugin so two
/// extensions may declare the same preference `name` without colliding.
public final class UserDefaultsPreferenceStore: PreferenceValueStoring {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ pluginId: String, _ name: String) -> String { "vee.pref.\(pluginId).\(name)" }

    public func value(pluginId: String, name: String) -> JSONValue? {
        guard let data = defaults.data(forKey: key(pluginId, name)) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
    public func setValue(_ value: JSONValue, pluginId: String, name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key(pluginId, name))
    }
    public func removeValue(pluginId: String, name: String) {
        defaults.removeObject(forKey: key(pluginId, name))
    }
}

/// In-memory plain store for tests and previews.
public final class InMemoryPreferenceStore: PreferenceValueStoring {
    private var items: [String: JSONValue] = [:]
    public init() {}
    private func key(_ p: String, _ n: String) -> String { "\(p)\u{0}\(n)" }
    public func value(pluginId: String, name: String) -> JSONValue? { items[key(pluginId, name)] }
    public func setValue(_ value: JSONValue, pluginId: String, name: String) { items[key(pluginId, name)] = value }
    public func removeValue(pluginId: String, name: String) { items[key(pluginId, name)] = nil }
}

// MARK: - Coordinator seam

/// What `AppCoordinator` depends on to gate + resolve a plugin activation. Kept
/// minimal so the coordinator stays unit-testable against a fake.
public protocol PluginPreferenceProviding: AnyObject {
    /// Resolved (name → value) preferences for a command — the plugin's declared
    /// specs merged with the user's stored values and declared defaults. Delivered
    /// to the plugin in `ActivateParams.preferences`.
    func resolvedValues(pluginId: String, command: String) -> [String: JSONValue]
    /// Whether every REQUIRED preference for the command is satisfied (a stored,
    /// non-empty value or a default). When false the host shows "Setup required"
    /// instead of activating.
    func isConfigured(pluginId: String, command: String) -> Bool
}

// MARK: - The generic store

/// The generic, plugin-driven preferences engine. Knows nothing about any
/// specific service: it operates purely on the `PluginPreference`s each installed
/// plugin declared. Secrets (`.password`) are stored in the Keychain via
/// `TokenStoring`; all other values in a `PreferenceValueStoring`.
public final class PluginPreferencesStore: PluginPreferenceProviding {
    private let manifestsById: [String: PluginManifest]
    private let secrets: TokenStoring
    private let plain: PreferenceValueStoring

    public init(manifests: [PluginManifest],
                secrets: TokenStoring,
                plain: PreferenceValueStoring = UserDefaultsPreferenceStore()) {
        self.manifestsById = Dictionary(manifests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.secrets = secrets
        self.plain = plain
    }

    /// Installed extensions sorted by display name — the Settings list.
    public var extensions: [PluginManifest] {
        manifestsById.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Manifest for an installed extension, if present.
    public func manifest(forPlugin pluginId: String) -> PluginManifest? { manifestsById[pluginId] }

    /// Every preference an extension declares (extension-level + all commands'),
    /// deduped by name preserving order — what the Settings form renders.
    public func declaredPreferences(forPlugin pluginId: String) -> [PluginPreference] {
        guard let m = manifestsById[pluginId] else { return [] }
        var byName: [String: PluginPreference] = [:]
        var order: [String] = []
        for pref in m.preferences + m.commands.flatMap(\.preferences) {
            if byName[pref.name] == nil { order.append(pref.name) }
            byName[pref.name] = pref
        }
        return order.compactMap { byName[$0] }
    }

    // MARK: stored value access (routes secret ↔ plain by declared type)

    /// The stored value for a preference (Keychain for `.password`, plain store
    /// otherwise), or nil when unset.
    public func storedValue(pluginId: String, preference: PluginPreference) -> JSONValue? {
        if preference.isSecret {
            guard let s = secrets.token(plugin: pluginId, account: preference.name), !s.isEmpty else { return nil }
            return .string(s)
        }
        return plain.value(pluginId: pluginId, name: preference.name)
    }

    /// Whether a non-empty value is stored (used by the form to show "saved"
    /// without revealing a secret).
    public func hasStoredValue(pluginId: String, preference: PluginPreference) -> Bool {
        switch storedValue(pluginId: pluginId, preference: preference) {
        case .some(.string(let s)): return !s.isEmpty
        case .some: return true
        case .none: return false
        }
    }

    /// Write a value through, routing by declared type. A nil/blank string clears it.
    public func setValue(_ value: JSONValue?, pluginId: String, preference: PluginPreference) {
        let isBlank: Bool
        switch value {
        case .none, .some(.null): isBlank = true
        case .some(.string(let s)): isBlank = s.isEmpty
        default: isBlank = false
        }
        if preference.isSecret {
            if isBlank {
                secrets.deleteToken(plugin: pluginId, account: preference.name)
            } else if case .some(.string(let s)) = value {
                secrets.setToken(s, plugin: pluginId, account: preference.name)
            }
        } else {
            if isBlank {
                plain.removeValue(pluginId: pluginId, name: preference.name)
            } else if let v = value {
                plain.setValue(v, pluginId: pluginId, name: preference.name)
            }
        }
    }

    // MARK: PluginPreferenceProviding

    public func resolvedValues(pluginId: String, command: String) -> [String: JSONValue] {
        guard let m = manifestsById[pluginId] else { return [:] }
        var out: [String: JSONValue] = [:]
        for pref in m.mergedPreferences(forCommand: command) {
            if let stored = storedValue(pluginId: pluginId, preference: pref) {
                out[pref.name] = stored
            } else if let def = pref.default {
                out[pref.name] = def
            }
        }
        return out
    }

    public func isConfigured(pluginId: String, command: String) -> Bool {
        // Unknown plugin → don't block (nothing was declared to require).
        guard let m = manifestsById[pluginId] else { return true }
        for pref in m.mergedPreferences(forCommand: command) where pref.required {
            let value = storedValue(pluginId: pluginId, preference: pref) ?? pref.default
            if !PluginPreferencesStore.isSatisfied(value) { return false }
        }
        return true
    }

    /// A required preference is satisfied by any non-null, non-blank value.
    static func isSatisfied(_ value: JSONValue?) -> Bool {
        switch value {
        case .none, .some(.null): return false
        case .some(.string(let s)): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }
}
