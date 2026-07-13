import Foundation
import VeeCore

/// Launches a long-lived process and streams its stdout as lines until it exits.
public protocol StreamingProcessRunning: Sendable {
    func lines(_ invocation: ProcessInvocation) -> AsyncThrowingStream<String, Error>
}

/// Production streaming runner backed by `Process`.
public struct SystemStreamingRunner: StreamingProcessRunning {
    /// Grace period between SIGTERM and the SIGKILL escalation in `cancel()`.
    /// Overridable so tests can exercise the escalation path without waiting
    /// out the production duration on every run.
    private let killGracePeriod: TimeInterval

    public init(killGracePeriod: TimeInterval = 2.5) {
        self.killGracePeriod = killGracePeriod
    }

    public func lines(_ invocation: ProcessInvocation) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let proc = StreamingProc(invocation: invocation, continuation: continuation, killGracePeriod: killGracePeriod)
            continuation.onTermination = { _ in proc.cancel() }
            proc.start()
        }
    }
}

/// Owns the non-`Sendable` process machinery for one streaming run, splitting
/// incoming data into lines. `@unchecked Sendable`: state is guarded by `lock`.
private final class StreamingProc: @unchecked Sendable {
    private let invocation: ProcessInvocation
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let killGracePeriod: TimeInterval

    private let process = Process()
    private let outPipe = Pipe()
    private let lock = NSLock()
    private var partial = Data()
    private var finished = false
    /// Guards against re-logging `maxLineBytes` truncation on every subsequent
    /// chunk of a stream that keeps emitting with no newlines.
    private var loggedLineTruncation = false
    private var selfRetain: StreamingProc?

    init(invocation: ProcessInvocation, continuation: AsyncThrowingStream<String, Error>.Continuation, killGracePeriod: TimeInterval) {
        self.invocation = invocation
        self.continuation = continuation
        self.killGracePeriod = killGracePeriod
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
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            finish(error: VeeError.launchFailed(pluginID: PluginID(path: invocation.launchPath), reason: error.localizedDescription))
            return
        }
        // Close the parent's write end so the read loop sees EOF at child exit.
        try? outPipe.fileHandleForWriting.close()

        // Single dedicated reader. Raw read(2) rather than `availableData`: it
        // lets a stalled read be unblocked by *closing* the handle from another
        // thread (the read returns -1 and the loop ends) without
        // `availableData`'s exception-on-error behavior — the escape hatch
        // `cancel()`'s escalation relies on (mirrors SystemProcessRunner's
        // boundedDrain, which documents the same hazard).
        let fd = outPipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global().async { [self] in
            let bufferSize = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while true {
                let n = read(fd, &buffer, bufferSize)
                if n == 0 { break } // EOF
                if n < 0 {
                    if errno == EINTR { continue } // transient interrupt: retry
                    break // closed / error: end the read loop
                }
                ingest(Data(buffer[0..<n]))
            }
            finish(error: nil)
        }
    }

    /// A single line with no terminating newline would otherwise grow `partial`
    /// without limit. 1 MB for one menu line is already pathological.
    private static let maxLineBytes = 1 * 1024 * 1024

    private func ingest(_ data: Data) {
        var linesToYield: [String] = []
        var shouldLogTruncation = false
        lock.withLock {
            partial.append(data)
            while let nl = partial.firstIndex(of: 0x0A) {
                // Tolerate CRLF line endings: strip exactly one trailing "\r" so
                // a Windows-authored streaming plugin's `~~~\r` still matches
                // StreamAccumulator's separator.
                let lineEnd = (nl > partial.startIndex && partial[nl - 1] == 0x0D) ? nl - 1 : nl
                let lineData = partial[partial.startIndex..<lineEnd]
                linesToYield.append(String(decoding: lineData, as: UTF8.self))
                partial.removeSubrange(partial.startIndex...nl)
            }
            // Bound a pathological no-newline stream: flush the oversized partial
            // as a line so memory stays bounded.
            if partial.count > Self.maxLineBytes {
                linesToYield.append(String(decoding: partial, as: UTF8.self))
                partial.removeAll(keepingCapacity: false)
                // Once per process is enough to flag a misbehaving plugin
                // without flooding the log if it keeps streaming with no newlines.
                if !loggedLineTruncation {
                    loggedLineTruncation = true
                    shouldLogTruncation = true
                }
            }
        }
        for line in linesToYield { continuation.yield(line) }
        // Logged (rather than folded silently into the yielded content, which
        // would corrupt whatever the plugin was mid-emitting) — matches the
        // "record it instead of dropping it silently" treatment
        // SystemProcessRunner gives its own 8 MB capture cap.
        if shouldLogTruncation {
            VeeLog.make("streaming").warning("output line truncated at 1 MB")
        }
    }

    private func finish(error: Error?) {
        let alreadyFinished: Bool = lock.withLock {
            if finished { return true }
            finished = true
            return false
        }
        guard !alreadyFinished else { return }

        // Emit any trailing partial line (output with no final newline).
        let tail: String? = lock.withLock {
            guard !partial.isEmpty else { return nil }
            let s = String(decoding: partial, as: UTF8.self)
            partial.removeAll()
            return s
        }
        if let tail { continuation.yield(tail) }

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
        selfRetain = nil
    }

    func cancel() {
        // Guard the Process access under the same lock the reader uses, so a
        // cancel racing the reader's natural EOF can't interleave on `process`.
        // The pid is captured now (while we know the process was ours to
        // signal) rather than re-read later, and never signalled unless it's
        // strictly positive — `kill(0, …)` targets the whole process group and
        // `kill(-1, …)` targets every process the caller can signal.
        let pid: Int32? = lock.withLock {
            guard process.isRunning else { return nil }
            process.terminate() // SIGTERM
            return process.processIdentifier
        }

        // Always arm the escalation, even if the process had already exited by
        // the time we checked above: a grandchild that separately inherited the
        // write end of the pipe (e.g. the plugin backgrounded a helper before
        // exiting normally) can keep the reader parked with no live process of
        // ours left to signal. After the grace period, SIGKILL our specific
        // child if it's somehow still running, then force-close the read end
        // regardless — that's what actually unblocks the reader in the
        // grandchild case, since killing our child doesn't touch it.
        DispatchQueue.global().asyncAfter(deadline: .now() + killGracePeriod) { [weak self] in
            guard let self else { return }
            if let pid, pid > 0 {
                let stillRunning: Bool = self.lock.withLock { self.process.isRunning }
                if stillRunning { kill(pid, SIGKILL) }
            }
            try? self.outPipe.fileHandleForReading.close()
        }

        finish(error: nil)
    }
}
