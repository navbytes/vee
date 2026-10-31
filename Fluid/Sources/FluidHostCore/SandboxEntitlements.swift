import Foundation
import FluidProtocol

/// Turns a manifest's capabilities into the App Sandbox entitlements its helper
/// is signed with, so the OS — not the honour system — limits what it touches.
///
/// The sandbox has no per-domain network switch: `network(hosts:)` can only
/// turn outgoing connections on. The host keeps the domain list for the install
/// sheet and for comparing against what the plugin actually connects to.
public enum SandboxEntitlements {
    public static func entitlements(for manifest: Manifest) -> [String: Bool] {
        var result = ["com.apple.security.app-sandbox": true]
        for capability in manifest.capabilities {
            switch capability {
            case .network:
                result["com.apple.security.network.client"] = true
            case .files:
                result["com.apple.security.files.user-selected.read-write"] = true
            case .run, .secret:
                // Children inherit the sandbox; secrets arrive from the host.
                break
            }
        }
        return result
    }

    public static func propertyList(for manifest: Manifest) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: entitlements(for: manifest), format: .xml, options: 0)
    }

    /// One line per capability, in words, for the install sheet and `fluidctl`.
    public static func summary(for manifest: Manifest) -> [String] {
        if manifest.capabilities.isEmpty {
            return ["No network, files, commands or secrets."]
        }
        return manifest.capabilities.map { capability in
            switch capability {
            case .network(let hosts): return "Connects to " + (hosts.isEmpty ? "the network" : hosts.joined(separator: ", "))
            case .files(let paths): return "Reads and writes " + paths.joined(separator: ", ")
            case .run(let commands): return "Runs " + commands.joined(separator: ", ")
            case .secret(let name): return "Reads the secret \(name)"
            }
        }
    }
}
