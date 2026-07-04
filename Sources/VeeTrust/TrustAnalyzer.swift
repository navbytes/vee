import Foundation

/// Turns a `TrustDeclaration` into a human-facing `TrustSummary` with severity
/// heuristics and warnings. Purely advisory.
public enum TrustAnalyzer {
    public static func analyze(_ declaration: TrustDeclaration) -> TrustSummary {
        guard !declaration.isEmpty else {
            return TrustSummary(level: .undeclared, badges: [], warnings: [])
        }

        var badges: [TrustBadge] = []
        var warnings: [String] = []
        var partial = false

        for capability in declaration.capabilities.sorted() {
            switch capability {
            case .network:
                let domains = declaration.networkDomains
                if domains.isEmpty {
                    badges.append(TrustBadge(capability: .network, detail: "any host (undeclared)", severity: .high))
                    warnings.append("Declares network access but lists no domains.")
                    partial = true
                } else {
                    let wildcard = domains.contains { $0.contains("*") }
                    badges.append(TrustBadge(capability: .network, detail: domains.joined(separator: ", "), severity: wildcard ? .medium : .low))
                    if wildcard { warnings.append("Uses a wildcard network domain.") }
                }
            case .filesystem:
                let reads = declaration.fsReadPaths
                let writes = declaration.fsWritePaths
                let broadWrite = writes.contains { isBroad($0) }
                let detail = "read: \(reads.isEmpty ? "—" : reads.joined(separator: ", ")); write: \(writes.isEmpty ? "—" : writes.joined(separator: ", "))"
                badges.append(TrustBadge(capability: .filesystem, detail: detail, severity: broadWrite ? .high : (writes.isEmpty ? .low : .medium)))
                if broadWrite { warnings.append("Writes to a broad filesystem location.") }
            case .secrets:
                let secrets = declaration.secretsUsed
                badges.append(TrustBadge(capability: .secrets, detail: secrets.isEmpty ? "uses secrets" : secrets.joined(separator: ", "), severity: .medium))
            case .exec:
                let bins = declaration.externalBinaries
                badges.append(TrustBadge(capability: .exec, detail: bins.isEmpty ? "external binaries" : bins.joined(separator: ", "), severity: .medium))
            case .clipboard:
                badges.append(TrustBadge(capability: .clipboard, detail: "clipboard", severity: .low))
            case .notifications:
                badges.append(TrustBadge(capability: .notifications, detail: "notifications", severity: .low))
            }
        }

        return TrustSummary(level: partial ? .partial : .declared, badges: badges, warnings: warnings)
    }

    /// A path is "broad" if it targets the home directory or filesystem root
    /// rather than a scoped subdirectory.
    private static func isBroad(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed == "~" || trimmed == "~/" || trimmed == "/" || trimmed == "*"
    }
}
