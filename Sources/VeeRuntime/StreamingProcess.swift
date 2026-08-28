import Foundation
import VeeCore

/// Why a streaming plugin's process ended, when it ended badly.
///
/// A streaming plugin that dies gets restarted with backoff, so without this the
/// only trace of a plugin crash-looping on a typo was the restart message
/// itself: stderr went to `/dev/null` and a non-zero exit ended the stream
/// indistinguishably from a clean one. `stderr` is the tail of what the plugin
/// wrote, capped — an interpreter's stack trace is the thing worth seeing.
public struct StreamingPluginError: Error, Equatable, Sendable {
    public let exitCode: Int32
    public let standardError: String

    public init(exitCode: Int32, standardError: String) {
        self.exitCode = exitCode
        self.standardError = standardError
    }

    /// A one-line summary for a menu row or a restart message.
    public var summary: String {
        let trimmed = standardError
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .last
            .map(String.init)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return "exited with code \(exitCode)"
    }
}

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
    private let errPipe = Pipe()
    private let lock = NSLock()
    private var partial = Data()
    /// Bounded tail of the plugin's stderr, for the error a bad exit throws.
    private var capturedError = Data()
    /// The child's exit status, recorded by `terminationHandler`.
    ///
    /// Taken from Foundation's own callback rather than by calling
    /// `waitUntilExit()`/`terminationStatus` from the reader thread. `Process` is
    /// not thread-safe, and `cancel()` deliberately guards every access to it
    /// under `lock` for exactly that reason — a reader blocking inside
    /// `waitUntilExit()` while `cancel()` calls `terminate()` on the same object
    /// deadlocks, which is a hang rather than a failed test.
    private var exitStatus: Int32 = 0
    private let exited = DispatchSemaphore(value: 0)
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
        // Captured, not discarded. This used to be `FileHandle.nullDevice`, so a
        // streaming plugin that died on a syntax error or a missing interpreter
        // produced a menu that just said "restarting…" forever, with the actual
        // reason written to nowhere.
        process.standardError = errPipe
        // Set before `run()`: Foundation invokes this itself, so the status is
        // recorded without the reader ever touching `process`.
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            lock.withLock { exitStatus = finished.terminationStatus }
            exited.signal()
        }

        do {
            try process.run()
        } catch {
            finish(error: VeeError.launchFailed(pluginID: PluginID(path: invocation.launchPath), reason: error.localizedDescription))
            return
        }
        // Close the parent's write ends so the read loops see EOF at child exit.
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()

        // stderr drains on its own queue, and keeps draining after the cap is
        // reached: a child that fills the stderr pipe and gets no reader blocks
        // forever on write(2), which would hang the plugin rather than log it.
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { [self] in
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let n = read(errFD, &buffer, buffer.count)
                if n == 0 { break }
                if n < 0 {
                    if errno == EINTR { continue }
                    break
                }
                lock.withLock {
                    let room = Self.maxCapturedErrorBytes - capturedError.count
                    if room > 0 { capturedError.append(contentsOf: buffer[0..<Swift.min(n, room)]) }
                }
            }
            errDone.signal()
        }

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
            // stdout is at EOF, so the child has closed it. Wait for the exit
            // callback and the stderr drain — both bounded, because a stream
            // that never resolves must end as a finished stream, not a hang.
            _ = exited.wait(timeout: .now() + 5)
            _ = errDone.wait(timeout: .now() + 2)
            let status = lock.withLock { exitStatus }
            guard status != 0 else {
                finish(error: nil)
                return
            }
            let stderrText = lock.withLock { String(decoding: capturedError, as: UTF8.self) }
            finish(error: StreamingPluginError(exitCode: status, standardError: stderrText))
        }
    }

    /// Cap on the retained stderr tail. Big enough for an interpreter's stack
    /// trace, small enough that a plugin looping on an error can't grow it
    /// without bound.
    private static let maxCapturedErrorBytes = 64 * 1024

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
            // ponytail: closes (not `dup2`-to-`/dev/null`) despite the brief
            // fd-number-reuse window this leaves — see the matching note atop
            // SystemProcessRunner.swift. A blocking read() already parked in
            // the kernel is bound to the file description it resolved at
            // syscall entry, not the fd-table slot, so `dup2`-ing the slot
            // elsewhere doesn't wake it; only `close()` reliably does. Tried
            // `dup2` here first — it turned this test from stable into a
            // one-fd-per-cycle leak (the parked reader, and everything it
            // retains, never released), so reverted.
            try? self.outPipe.fileHandleForReading.close()
        }

        finish(error: nil)
    }
}
