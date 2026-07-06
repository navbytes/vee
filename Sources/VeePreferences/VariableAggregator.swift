import Foundation
import VeeCore
import VeePluginFormat

/// A lightweight description of an installed plugin handed to the aggregator.
/// Decoupled from `VeeRuntime.DiscoveredPlugin` on purpose so the aggregation is
/// pure and unit-testable with hand-built fakes (no filesystem, no runtime).
public struct AggregatablePlugin: Sendable, Equatable {
    public let id: PluginID
    public let name: String
    public let path: String

    public init(id: PluginID, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

/// One plugin's contribution to the app-wide Variables editor: its display
/// identity plus the declared `<xbar.var>` variables it exposes. The Variables
/// window renders one section per group.
public struct PluginVariableGroup: Identifiable, Sendable, Equatable {
    public let pluginID: PluginID
    public let pluginName: String
    public let pluginPath: String
    public let declarations: [VarDeclaration]

    public var id: String { pluginID.rawValue }

    /// Declarations that must be masked and stored in the Keychain.
    public var secretDeclarations: [VarDeclaration] { declarations.filter(\.isSecret) }
    /// Declarations stored in the plaintext `.vars.json` sidecar.
    public var plainDeclarations: [VarDeclaration] { declarations.filter { !$0.isSecret } }

    public init(pluginID: PluginID, pluginName: String, pluginPath: String, declarations: [VarDeclaration]) {
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.pluginPath = pluginPath
        self.declarations = declarations
    }
}

/// Reads the declared variables of a single plugin. Production reads the file
/// and parses its header; tests inject a fake so the aggregation can be
/// exercised without touching disk.
public protocol VariableDeclarationReading: Sendable {
    func declarations(for plugin: AggregatablePlugin) -> [VarDeclaration]
}

/// The production reader: loads a plugin's source and returns its parsed
/// `<xbar.var>` / `<swiftbar.var>` declarations.
public struct HeaderVariableReader: VariableDeclarationReading {
    public init() {}

    public func declarations(for plugin: AggregatablePlugin) -> [VarDeclaration] {
        // `try?` flattens the throwing, non-optional `String(contentsOfFile:)`
        // to `String?`, so `?? ""` yields the empty source on read failure.
        let source = (try? String(contentsOfFile: plugin.path, encoding: .utf8)) ?? ""
        return HeaderParser.parse(source: source).vars
    }
}

/// Pure, order-preserving aggregation across every installed plugin: read each
/// plugin's declared variables and emit one `PluginVariableGroup` per plugin
/// that declares at least one. Plugins with no configurable variables are
/// omitted so the editor lists only plugins the user can actually configure.
///
/// This is the cross-plugin config surface that supersedes xbar's per-plugin
/// `xbar.var` GUI. Inputs (the plugin list and the reader) are injected so the
/// logic can be tested with fakes.
public enum VariableAggregator {
    public static func aggregate(
        plugins: [AggregatablePlugin],
        reader: VariableDeclarationReading
    ) -> [PluginVariableGroup] {
        plugins.compactMap { plugin in
            let declarations = reader.declarations(for: plugin)
            guard !declarations.isEmpty else { return nil }
            return PluginVariableGroup(
                pluginID: plugin.id,
                pluginName: plugin.name,
                pluginPath: plugin.path,
                declarations: declarations
            )
        }
    }
}
