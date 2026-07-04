import Foundation

/// Heuristic static scan of a plugin's source to surface capabilities it appears
/// to use — so the install-time trust gate can warn when a plugin *does*
/// something it didn't *declare*. Advisory only; never blocks.
public extension TrustAnalyzer {
    /// Capabilities inferred from the source text (best-effort keyword scan).
    static func detectedCapabilities(inSource source: String) -> Set<Capability> {
        let lower = source.lowercased()
        var caps: Set<Capability> = []
        if lower.contains("curl ") || lower.contains("wget ") || lower.contains("http://")
            || lower.contains("https://") || lower.contains("nc ") || lower.contains("ncat ") {
            caps.insert(.network)
        }
        if lower.contains("security find-generic-password") || lower.contains("api_key")
            || lower.contains("api_token") || lower.contains("password") || lower.contains("secret") {
            caps.insert(.secrets)
        }
        if lower.contains("pbcopy") || lower.contains("pbpaste") {
            caps.insert(.clipboard)
        }
        return caps
    }

    /// Warnings for capabilities the source appears to use but the header did
    /// not declare.
    static func installWarnings(declaration: TrustDeclaration, source: String) -> [String] {
        let detected = detectedCapabilities(inSource: source)
        var warnings: [String] = []
        if detected.contains(.network) && !declaration.capabilities.contains(.network) {
            warnings.append("Appears to access the network but does not declare it.")
        }
        if detected.contains(.secrets) && !declaration.capabilities.contains(.secrets) {
            warnings.append("Appears to use credentials but does not declare them.")
        }
        if detected.contains(.clipboard) && !declaration.capabilities.contains(.clipboard) {
            warnings.append("Appears to access the clipboard but does not declare it.")
        }
        return warnings
    }
}
