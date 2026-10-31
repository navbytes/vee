/// What a plugin declares about itself before it ever runs.
///
/// The host reads it by launching the plugin with `--manifest`, so the
/// declaration lives in the plugin's own Swift source and is type-checked with
/// it. The host uses it to decide which surfaces to give the plugin, when to
/// wake it, and — from `capabilities` — which sandbox entitlements to sign it
/// with and what to show on the install sheet.
public struct Manifest: Codable, Equatable, Sendable {
    /// Reverse-DNS, stable for the life of the plugin: `dev.navbytes.pr-cockpit`.
    public var id: String
    public var name: String
    public var version: String
    public var surfaces: [Surface]
    public var triggers: [Trigger]
    public var capabilities: [Capability]

    public init(id: String, name: String, version: String = "0.1.0", surfaces: [Surface] = [.menuBar, .panel], triggers: [Trigger] = [.launch], capabilities: [Capability] = []) {
        self.id = id
        self.name = name
        self.version = version
        self.surfaces = surfaces
        self.triggers = triggers
        self.capabilities = capabilities
    }

    /// The shortest periodic trigger, if any — what the host schedules.
    public var refreshInterval: Double? {
        triggers.compactMap { trigger -> Double? in
            if case .every(let seconds) = trigger { return seconds }
            return nil
        }.min()
    }
}

/// When the host asks a plugin to `refresh()`.
public enum Trigger: Codable, Hashable, Sendable {
    /// Right after the plugin starts (and after every restart).
    case launch
    /// Periodically. Values under one second are raised to one second.
    case every(seconds: Double)
    /// When the Mac wakes from sleep.
    case wake

    public static func every(_ duration: Duration) -> Trigger {
        let (seconds, attoseconds) = duration.components
        return .every(seconds: max(1, Double(seconds) + Double(attoseconds) / 1e18))
    }

    public static func minutes(_ count: Double) -> Trigger { .every(seconds: max(1, count * 60)) }
}

/// What a plugin may touch. Declared here, enforced by the sandbox entitlements
/// the host signs the plugin with, and shown to the user before install.
public enum Capability: Codable, Hashable, Sendable {
    /// Outgoing connections. The OS sandbox can only switch the network on or
    /// off; the host lists the domains so the user knows what to expect.
    case network(hosts: [String])
    /// Folders the user grants read/write access to.
    case files(paths: [String])
    /// Commands the plugin may run.
    case run(commands: [String])
    /// A named secret the plugin reads (phase 0: from its environment).
    case secret(name: String)

    public static func network(_ hosts: String...) -> Capability { .network(hosts: hosts) }
}
