import Foundation
import VeeCore
import VeePluginFormat

/// Combines the sidecar (non-secret) and Keychain (secret) stores for one
/// plugin, resolving declared `<xbar.var>` values for display and for env
/// injection. Secret values live only in the Keychain; the sidecar never holds
/// them.
public struct PluginPreferences {
    public let declarations: [VarDeclaration]
    private let varStore: VarStore
    private let secretStore: SecretStoring

    public init(pluginPath: String, pluginID: PluginID, declarations: [VarDeclaration], secretStore: SecretStoring? = nil) {
        self.declarations = declarations
        self.varStore = VarStore(pluginPath: pluginPath)
        self.secretStore = secretStore ?? KeychainSecretStore(pluginID: pluginID.rawValue)
    }

    /// The current value for a declared variable: stored value, else its
    /// default.
    public func value(for declaration: VarDeclaration) -> String {
        let stored = declaration.isSecret
            ? secretStore.get(declaration.name)
            : varStore.value(for: declaration.name)
        return stored ?? declaration.defaultValue
    }

    public func setValue(_ value: String, for declaration: VarDeclaration) throws {
        if declaration.isSecret {
            secretStore.set(value, for: declaration.name)
        } else {
            try varStore.set(value, for: declaration.name)
        }
    }

    /// All declared variables resolved to their current values — injected into
    /// the plugin's environment at run time.
    public func environmentValues() -> [String: String] {
        var env: [String: String] = [:]
        for declaration in declarations {
            env[declaration.name] = value(for: declaration)
        }
        return env
    }
}
