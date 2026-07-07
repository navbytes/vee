import Foundation

/// The added/removed elements for one dimension of a plugin's trust footprint
/// (e.g. its network domains, or its declared capabilities).
///
/// Elements are kept sorted so the diff is deterministic and stable to display.
public struct TrustSetDiff<Element: Hashable & Comparable & Sendable>: Equatable, Sendable {
    /// Elements present in the *new* source but not the old one.
    public var added: [Element]
    /// Elements present in the *old* source but not the new one.
    public var removed: [Element]

    public init(added: [Element] = [], removed: [Element] = []) {
        self.added = added
        self.removed = removed
    }

    /// Whether this dimension changed between the two sources.
    public var hasChanges: Bool { !added.isEmpty || !removed.isEmpty }

    /// Diffs two collections into sorted added/removed sets. Duplicate and
    /// unordered input is normalised; only membership matters.
    static func between<Old: Sequence, New: Sequence>(old: Old, new: New) -> TrustSetDiff
    where Old.Element == Element, New.Element == Element {
        let oldSet = Set(old)
        let newSet = Set(new)
        return TrustSetDiff(
            added: newSet.subtracting(oldSet).sorted(),
            removed: oldSet.subtracting(newSet).sorted()
        )
    }
}

/// A single element added to, or removed from, a plugin's trust footprint by an
/// update. Carries the direction and a risk flag so the install gate can colour
/// and weight each change rather than rendering an undifferentiated list.
public struct TrustChange: Equatable, Sendable {
    public enum Direction: Sendable, Equatable { case added, removed }

    /// Whether this element appeared (`.added`) or disappeared (`.removed`).
    public var direction: Direction
    /// The dimension noun, e.g. `"capability"`, `"domain"`, `"filesystem write"`.
    public var noun: String
    /// The element itself, e.g. `"network"`, `"evil.tld"`, `"~"`.
    public var item: String
    /// True for additions that materially widen the plugin's reach (a new
    /// capability, filesystem-write path, secret, or external binary), so the UI
    /// can flag them more prominently than a benign change like a removed domain.
    public var isElevated: Bool

    public init(direction: Direction, noun: String, item: String, isElevated: Bool) {
        self.direction = direction
        self.noun = noun
        self.item = item
        self.isElevated = isElevated
    }
}

/// A structured diff of a plugin's *trust footprint* — its declared and detected
/// capabilities plus the network/filesystem/secret/exec details — between the
/// currently-installed source and an incoming update.
///
/// Vee shows this before overwriting an installed plugin in place, so a silent
/// supply-chain-style change ("this update adds filesystem-write and a new
/// domain") is surfaced rather than applied invisibly. Purely advisory and
/// entirely pure: it derives everything from the two source strings.
public struct TrustDiff: Equatable, Sendable {
    /// Capability changes, combining declared (`<vee.*>`) and heuristically
    /// detected capabilities.
    public var capabilities: TrustSetDiff<Capability>
    /// Declared network domains added/removed.
    public var networkDomains: TrustSetDiff<String>
    /// Declared `filesystem.read` paths added/removed.
    public var fsReadPaths: TrustSetDiff<String>
    /// Declared `filesystem.write` paths added/removed.
    public var fsWritePaths: TrustSetDiff<String>
    /// Declared secrets added/removed.
    public var secretsUsed: TrustSetDiff<String>
    /// Declared external binaries (`<vee.exec>`) added/removed.
    public var externalBinaries: TrustSetDiff<String>

    public init(
        capabilities: TrustSetDiff<Capability> = .init(),
        networkDomains: TrustSetDiff<String> = .init(),
        fsReadPaths: TrustSetDiff<String> = .init(),
        fsWritePaths: TrustSetDiff<String> = .init(),
        secretsUsed: TrustSetDiff<String> = .init(),
        externalBinaries: TrustSetDiff<String> = .init()
    ) {
        self.capabilities = capabilities
        self.networkDomains = networkDomains
        self.fsReadPaths = fsReadPaths
        self.fsWritePaths = fsWritePaths
        self.secretsUsed = secretsUsed
        self.externalBinaries = externalBinaries
    }

    /// True when any dimension of the trust footprint changed.
    public var hasChanges: Bool {
        capabilities.hasChanges || networkDomains.hasChanges || fsReadPaths.hasChanges
            || fsWritePaths.hasChanges || secretsUsed.hasChanges || externalBinaries.hasChanges
    }

    /// True when the two sources have an identical trust footprint.
    public var isEmpty: Bool { !hasChanges }

    /// Plain-language, one-per-change lines describing the footprint delta —
    /// e.g. `"adds filesystem write: ~"`, `"adds domain: evil.tld"`,
    /// `"removes exec: git"`. Ordered by dimension, additions before removals.
    public var summaryLines: [String] {
        changes.map { change in
            "\(change.direction == .added ? "adds" : "removes") \(change.noun): \(change.item)"
        }
    }

    /// One structured entry per element that was added or removed, ordered by
    /// dimension (additions before removals within each). Unlike ``summaryLines``
    /// this keeps the direction and an ``TrustChange/isElevated`` risk flag
    /// separate so the UI can colour and weight each change instead of showing a
    /// flat wall of text.
    public var changes: [TrustChange] {
        var result: [TrustChange] = []
        func emit(_ noun: String, elevatedWhenAdded: Bool, added: [String], removed: [String]) {
            for item in added {
                result.append(TrustChange(direction: .added, noun: noun, item: item, isElevated: elevatedWhenAdded))
            }
            for item in removed {
                result.append(TrustChange(direction: .removed, noun: noun, item: item, isElevated: false))
            }
        }
        // Additions that materially widen what the plugin can reach are elevated;
        // a new domain on an already-networked plugin, or a read path, is not.
        emit("capability", elevatedWhenAdded: true,
             added: capabilities.added.map(\.rawValue), removed: capabilities.removed.map(\.rawValue))
        emit("domain", elevatedWhenAdded: false, added: networkDomains.added, removed: networkDomains.removed)
        emit("filesystem read", elevatedWhenAdded: false, added: fsReadPaths.added, removed: fsReadPaths.removed)
        emit("filesystem write", elevatedWhenAdded: true, added: fsWritePaths.added, removed: fsWritePaths.removed)
        emit("secret", elevatedWhenAdded: true, added: secretsUsed.added, removed: secretsUsed.removed)
        emit("exec", elevatedWhenAdded: true, added: externalBinaries.added, removed: externalBinaries.removed)
        return result
    }

    /// Diffs the trust footprint of an installed plugin source against an
    /// incoming update. Each dimension is derived by parsing the `<vee.*>`
    /// declaration; the capability dimension additionally folds in the static
    /// `SourceScan` (so a newly-added `curl` shows up even when undeclared).
    ///
    /// - Parameters:
    ///   - oldSource: the source currently installed on disk.
    ///   - newSource: the freshly-fetched catalog source about to overwrite it.
    public static func between(old oldSource: String, new newSource: String) -> TrustDiff {
        let oldDeclaration = TrustParser.parse(source: oldSource)
        let newDeclaration = TrustParser.parse(source: newSource)
        return between(
            old: oldDeclaration,
            new: newDeclaration,
            oldDetected: TrustAnalyzer.detectedCapabilities(inSource: oldSource),
            newDetected: TrustAnalyzer.detectedCapabilities(inSource: newSource)
        )
    }

    /// Diffs already-parsed declarations, folding the given detected capability
    /// sets into the capability dimension. Useful when the declaration and scan
    /// have already been computed by the caller.
    public static func between(
        old oldDeclaration: TrustDeclaration,
        new newDeclaration: TrustDeclaration,
        oldDetected: Set<Capability> = [],
        newDetected: Set<Capability> = []
    ) -> TrustDiff {
        TrustDiff(
            capabilities: .between(
                old: oldDeclaration.capabilities.union(oldDetected),
                new: newDeclaration.capabilities.union(newDetected)
            ),
            networkDomains: .between(old: oldDeclaration.networkDomains, new: newDeclaration.networkDomains),
            fsReadPaths: .between(old: oldDeclaration.fsReadPaths, new: newDeclaration.fsReadPaths),
            fsWritePaths: .between(old: oldDeclaration.fsWritePaths, new: newDeclaration.fsWritePaths),
            secretsUsed: .between(old: oldDeclaration.secretsUsed, new: newDeclaration.secretsUsed),
            externalBinaries: .between(old: oldDeclaration.externalBinaries, new: newDeclaration.externalBinaries)
        )
    }
}
