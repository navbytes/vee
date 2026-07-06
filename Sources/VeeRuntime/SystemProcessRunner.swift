import Foundation
import VeeCore

/// Production `ProcessRunning` backed by Foundation `Process`.
///
/// Correctness notes (these keep long-running use leak- and deadlock-free):
/// - stdout and stderr are each drained to EOF by a dedicated background read,
///   so a plugin that writes more than the pipe buffer never blocks the child.
/// - the parent's write-end handles are closed after launch, so the reads see
///   EOF the moment the child exits (otherwise `readToEnd` would hang forever).
/// - the run resumes exactly once, after both reads finish *and* the process
///   terminates, so no trailing output is lost.
/// - a timeout terminates the child (SIGTERM, then SIGKILL after a grace period).
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ invocation: ProcessInvocation) async throws -> ProcessOutcome {
        try await withCheckedThrowingContinuation { continuation in
            ProcessRun(invocation: invocation, continuation: continuation).start()
        }
    }
}

/// Drains a pipe handle to EOF while capping how much is kept in memory. A plugin
/// that spews output for the whole timeout window (e.g. `yes`) would otherwise
/// buffer hundreds of MB before the timeout fires — breaking the bounded-memory
/// guarantee. Beyond `cap` we keep reading (so the child never blocks on a full
/// pipe) but stop accumulating; the captured output is truncated at `cap`.
extension ProcessRun {
    /// 8 MB is orders of magnitude beyond any real menu render.
    static let maxCapturedBytes = 8 * 1024 * 1024

    static func boundedDrain(_ handle: FileHandle, cap: Int) -> Data {
        var accumulated = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break } // EOF
            if accumulated.count < cap {
                accumulated.append(chunk.prefix(cap - accumulated.count))
            }
        }
        return accumulated
    }
}

/// Owns the mutable, non-`Sendable` machinery for one run and coordinates the
/// three completion signals (stdout drained, stderr drained, process exited)
/// so the continuation resumes exactly once. `@unchecked Sendable`: all shared
/// state is guarded by `lock`.
private final class ProcessRun: @unchecked Sendable {
    private let invocation: ProcessInvocation
    private let continuation: CheckedContinuation<ProcessOutcome, Error>

    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()

    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var exitCode: Int32 = 0
    private var timedOut = false
    private var pending = 3 // stdout read, stderr read, termination
    private var resumed = false
    private var timeoutItem: DispatchWorkItem?
    /// Keeps this instance alive for the duration of the run (nothing else holds
    /// a strong reference once `start()` returns). Cleared when we resume.
    private var selfRetain: ProcessRun?

    init(invocation: ProcessInvocation, continuation: CheckedContinuation<ProcessOutcome, Error>) {
        self.invocation = invocation
        self.continuation = continuation
    }

    func start() {
        selfRetain = self
        process.executableURL = URL(fileURLWithPath: invocation.launchPath)
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        if let wd = invocation.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.terminationHandler = { [weak self] proc in
            self?.complete { $0.exitCode = proc.terminationStatus }
        }

        do {
            try process.run()
        } catch {
            resumeFailure(VeeError.launchFailed(
                pluginID: PluginID(path: invocation.launchPath),
                reason: error.localizedDescription))
            return
        }

        // Close the parent's copy of the write ends so the reads below hit EOF
        // when the child exits (the child keeps its own dup'd descriptors).
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        DispatchQueue.global().async { [weak self] in
            let data = ProcessRun.boundedDrain(outHandle, cap: ProcessRun.maxCapturedBytes)
            self?.complete { $0.outData = data }
        }
        DispatchQueue.global().async { [weak self] in
            let data = ProcessRun.boundedDrain(errHandle, cap: ProcessRun.maxCapturedBytes)
            self?.complete { $0.errData = data }
        }

        if let timeout = invocation.timeout {
            let item = DispatchWorkItem { [weak self] in self?.enforceTimeout() }
            lock.withLock { timeoutItem = item }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
    }

    private func enforceTimeout() {
        guard process.isRunning else { return }
        lock.withLock { timedOut = true }
        process.terminate() // SIGTERM
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.process.isRunning else { return }
            kill(self.process.processIdentifier, SIGKILL)
        }
    }

    /// Applies one completion signal under the lock and resumes once all three
    /// have arrived.
    private func complete(_ apply: (ProcessRun) -> Void) {
        var outcome: ProcessOutcome?
        lock.lock()
        apply(self)
        pending -= 1
        if !resumed, pending == 0 {
            resumed = true
            outcome = ProcessOutcome(
                standardOutput: String(decoding: outData, as: UTF8.self),
                standardError: String(decoding: errData, as: UTF8.self),
                exitCode: exitCode,
                timedOut: timedOut)
        }
        let item = timeoutItem
        lock.unlock()

        if let outcome {
            item?.cancel()
            continuation.resume(returning: outcome)
            selfRetain = nil // allow deallocation now the run is done
        }
    }

    private func resumeFailure(_ error: Error) {
        let shouldResume: Bool = lock.withLock {
            if resumed { return false }
            resumed = true
            return true
        }
        if shouldResume {
            continuation.resume(throwing: error)
            selfRetain = nil
        }
    }
}
