import Foundation

/// Parses `<vee.*>` capability declarations from a plugin's source.
///
/// ```
/// <vee.capabilities>network,secrets</vee.capabilities>
/// <vee.network>api.github.com, *.example.com</vee.network>
/// <vee.filesystem.read>~/Documents</vee.filesystem.read>
/// <vee.filesystem.write>~/Library/Application Support/Vee</vee.filesystem.write>
/// <vee.secrets>GITHUB_TOKEN</vee.secrets>
/// <vee.exec>git, curl</vee.exec>
/// ```
public enum TrustParser {
    // Compile-time-constant pattern; cannot fail at runtime.
    // swiftlint:disable:next force_try
    private static let tag = try! NSRegularExpression(
        pattern: "<vee\\.([a-zA-Z.]+)>([\\s\\S]*?)</vee\\.\\1>",
        options: []
    )

    public static func parse(source: String) -> TrustDeclaration {
        var declaration = TrustDeclaration()
        let ns = source as NSString

        for match in tag.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let value = ns.substring(with: match.range(at: 2))
            let items = list(value)

            switch key {
            case "capabilities":
                for name in items {
                    if let capability = Capability(rawValue: name.lowercased()) {
                        declaration.capabilities.insert(capability)
                    }
                }
            case "network":
                declaration.networkDomains = items
            case "filesystem.read":
                declaration.fsReadPaths = items
            case "filesystem.write":
                declaration.fsWritePaths = items
            case "secrets":
                declaration.secretsUsed = items
            case "exec":
                declaration.externalBinaries = items
            default:
                break
            }
        }

        // Infer capabilities implied by the detail tags.
        if !declaration.networkDomains.isEmpty { declaration.capabilities.insert(.network) }
        if !declaration.fsReadPaths.isEmpty || !declaration.fsWritePaths.isEmpty { declaration.capabilities.insert(.filesystem) }
        if !declaration.secretsUsed.isEmpty { declaration.capabilities.insert(.secrets) }
        if !declaration.externalBinaries.isEmpty { declaration.capabilities.insert(.exec) }

        return declaration
    }

    private static func list(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
