import Foundation
import FluidProtocol

/// Keeps one plugin alive and turns its messages into state the UI can show.
///
/// The supervisor owns the helper process: it says hello, fires the manifest's
/// triggers, forwards the user's events, remembers the latest tree per surface,
/// and restarts the helper with backoff when it exits unexpectedly. The last
/// trees stay on screen through a restart, so a crash shows as a brief stale
/// moment rather than an empty panel.
///
/// Process events are funnelled through one `AsyncStream` and handled in the
/// order they arrived, so a render can never be overtaken by an older one.
public actor PluginSupervisor {
    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case running
        case restarting(attempt: Int, inSeconds: Double)
        case failed(String)
    }

    public enum Update: Sendable {
        case state(State)
        case render(Surface, ViewNode)
        case log(LogLevel, String)
    }

    public nonisolated let executable: URL
    public nonisolated let manifest: Manifest
    private let policy: BackoffPolicy
    private let environment: [String: String]?
    private let onUpdate: @Sendable (Update) -> Void

    public private(set) var state: State = .stopped
    public private(set) var views: [Surface: ViewNode] = [:]
    public private(set) var restarts = 0
    /// How many host messages the current helper has finished handling. Tools
    /// and tests wait on it instead of guessing with sleeps.
    public private(set) var settledCount = 0

    private var process: PluginProcess?
    private var generation = 0
    private var consecutiveFailures = 0
    private var startedAt = ContinuousClock.now
    private var stopping = false
    private var consumer: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var pendingRestart: Task<Void, Never>?

    public init(executable: URL, manifest: Manifest, policy: BackoffPolicy = .standard, environment: [String: String]? = nil, onUpdate: @escaping @Sendable (Update) -> Void = { _ in }) {
        self.executable = executable
        self.manifest = manifest
        self.policy = policy
        self.environment = environment
        self.onUpdate = onUpdate
    }

    /// Reads the plugin's manifest, then returns a supervisor for it (not yet started).
    public static func make(executable: URL, policy: BackoffPolicy = .standard, environment: [String: String]? = nil, onUpdate: @escaping @Sendable (Update) -> Void = { _ in }) throws -> PluginSupervisor {
        let manifest = try PluginProcess.readManifest(executable: executable)
        return PluginSupervisor(executable: executable, manifest: manifest, policy: policy, environment: environment, onUpdate: onUpdate)
    }

    public func start() {
        stopping = false
        spawn()
    }

    /// Stops the helper and every timer. Safe to call more than once.
    public func stop() {
        stopping = true
        pendingRestart?.cancel()
        ticker?.cancel()
        process?.terminate()
        process = nil
        setState(.stopped)
    }

    public func send(_ message: HostMessage) {
        guard state == .running || state == .starting else { return }
        process?.send(message)
    }

    /// A user event: a click, a toggle, a filtered row.
    public func event(_ action: ActionID, value: EventValue? = nil) {
        send(.event(action: action, value: value))
    }

    public func refresh() {
        send(.trigger(reason: .manual))
    }

    /// The Mac woke from sleep. Only plugins that asked for `.wake` hear it.
    public func wake() {
        if manifest.triggers.contains(.wake) { send(.trigger(reason: .wake)) }
    }

    public func setVisible(_ surface: Surface, _ visible: Bool) {
        send(.visibility(surface: surface, visible: visible))
    }

    /// Messages the host sends a fresh helper before anything else: `hello`,
    /// plus a launch trigger when the manifest asks for one.
    public nonisolated var startupMessageCount: Int {
        manifest.triggers.contains(.launch) ? 2 : 1
    }

    // MARK: - Process lifecycle

    private func spawn() {
        generation += 1
        let current = generation
        setState(.starting)
        let helper = PluginProcess(executable: executable, environment: environment)
        let (events, continuation) = AsyncStream.makeStream(of: PluginProcess.Event.self)
        do {
            try helper.start { continuation.yield($0) }
        } catch {
            continuation.finish()
            onUpdate(.log(.error, "could not launch \(executable.lastPathComponent): \(error)"))
            handleExit(status: -1, generation: current)
            return
        }
        process = helper
        startedAt = .now
        settledCount = 0
        consumer = Task { [weak self] in
            for await event in events {
                await self?.handle(event, generation: current)
            }
        }
        let offered = manifest.surfaces.filter(Surface.allCases.contains)
        helper.send(.hello(protocolVersion: FluidProtocolVersion.current, surfaces: offered))
        if manifest.triggers.contains(.launch) {
            helper.send(.trigger(reason: .launch))
        }
        startTicker()
    }

    private func startTicker() {
        ticker?.cancel()
        guard let interval = manifest.refreshInterval else { return }
        let seconds = max(1, interval)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.send(.trigger(reason: .interval))
            }
        }
    }

    private func handle(_ event: PluginProcess.Event, generation eventGeneration: Int) {
        guard eventGeneration == generation else { return }
        switch event {
        case .message(.ready(let version)):
            if version != FluidProtocolVersion.current {
                onUpdate(.log(.warning, "plugin speaks protocol \(version), host speaks \(FluidProtocolVersion.current)"))
            }
            setState(.running)
        case .message(.render(let surface, let root)):
            views[surface] = root
            onUpdate(.render(surface, root))
        case .message(.log(let level, let message)):
            onUpdate(.log(level, message))
        case .message(.settled):
            settledCount += 1
        case .stderr(let line):
            onUpdate(.log(.debug, line))
        case .undecodable(let line):
            onUpdate(.log(.warning, "unreadable message from plugin: \(line.prefix(200))"))
        case .exit(let status):
            handleExit(status: status, generation: eventGeneration)
        }
    }

    private func handleExit(status: Int32, generation exitGeneration: Int) {
        guard exitGeneration == generation else { return }
        ticker?.cancel()
        process = nil
        if stopping {
            setState(.stopped)
            return
        }
        if ContinuousClock.now - startedAt > .seconds(policy.stableAfter) {
            consecutiveFailures = 0
        }
        consecutiveFailures += 1
        guard let delay = policy.delay(afterFailures: consecutiveFailures) else {
            setState(.failed("exited with status \(status), \(consecutiveFailures) times in a row"))
            return
        }
        onUpdate(.log(.warning, "plugin exited with status \(status); restarting in \(delay)s"))
        setState(.restarting(attempt: consecutiveFailures, inSeconds: delay))
        pendingRestart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.restart(after: exitGeneration)
        }
    }

    private func restart(after exitGeneration: Int) {
        guard !stopping, exitGeneration == generation else { return }
        restarts += 1
        spawn()
    }

    private func setState(_ newState: State) {
        guard newState != state else { return }
        state = newState
        onUpdate(.state(newState))
    }
}
