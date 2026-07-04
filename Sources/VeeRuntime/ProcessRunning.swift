import Foundation

/// A subprocess to launch.
public struct ProcessInvocation: Sendable, Equatable {
    public var launchPath: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String?
    /// Wall-clock deadline; the process is terminated (SIGTERM→SIGKILL) if it
    /// runs longer. `nil` means no timeout.
    public var timeout: TimeInterval?

    public init(launchPath: String, arguments: [String] = [], environment: [String: String] = [:], workingDirectory: String? = nil, timeout: TimeInterval? = nil) {
        self.launchPath = launchPath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }
}

/// The result of running a subprocess.
public struct ProcessOutcome: Sendable, Equatable {
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32
    public var timedOut: Bool

    public init(standardOutput: String, standardError: String, exitCode: Int32, timedOut: Bool) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}

/// Abstraction over subprocess execution so `PluginExecutor` can be unit-tested
/// with a fake and never spawns a real process in unit tests.
public protocol ProcessRunning: Sendable {
    func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome
}
