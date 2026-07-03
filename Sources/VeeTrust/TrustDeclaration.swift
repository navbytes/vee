import Foundation

/// A capability a plugin may declare it uses. Advisory only — Vee never enforces
/// these (plugins run un-sandboxed); they drive the trust summary shown to the
/// user.
public enum Capability: String, Sendable, CaseIterable, Comparable {
    case network, filesystem, secrets, exec, clipboard, notifications

    public static func < (lhs: Capability, rhs: Capability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What a plugin declares (via `<vee.*>` header tags) that it touches.
public struct TrustDeclaration: Equatable, Sendable {
    public var capabilities: Set<Capability>
    public var networkDomains: [String]
    public var fsReadPaths: [String]
    public var fsWritePaths: [String]
    public var secretsUsed: [String]
    public var externalBinaries: [String]

    public init(capabilities: Set<Capability> = [], networkDomains: [String] = [], fsReadPaths: [String] = [], fsWritePaths: [String] = [], secretsUsed: [String] = [], externalBinaries: [String] = []) {
        self.capabilities = capabilities
        self.networkDomains = networkDomains
        self.fsReadPaths = fsReadPaths
        self.fsWritePaths = fsWritePaths
        self.secretsUsed = secretsUsed
        self.externalBinaries = externalBinaries
    }

    public var isEmpty: Bool {
        capabilities.isEmpty && networkDomains.isEmpty && fsReadPaths.isEmpty
            && fsWritePaths.isEmpty && secretsUsed.isEmpty && externalBinaries.isEmpty
    }
}

public enum TrustLevel: String, Sendable {
    /// Nothing declared — capabilities unknown.
    case undeclared
    /// Declared, but a declaration is incomplete (e.g. network without domains).
    case partial
    /// Fully declared.
    case declared
}

public enum Severity: Int, Sendable, Comparable {
    case low, medium, high
    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct TrustBadge: Equatable, Sendable {
    public var capability: Capability
    public var detail: String
    public var severity: Severity

    public init(capability: Capability, detail: String, severity: Severity) {
        self.capability = capability
        self.detail = detail
        self.severity = severity
    }
}

public struct TrustSummary: Equatable, Sendable {
    public var level: TrustLevel
    public var badges: [TrustBadge]
    public var warnings: [String]

    public init(level: TrustLevel, badges: [TrustBadge], warnings: [String]) {
        self.level = level
        self.badges = badges
        self.warnings = warnings
    }
}
