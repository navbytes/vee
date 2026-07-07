import Foundation
import Darwin
import VeeCore

/// Production `ProcessRunning` backed by `posix_spawn`.
///
/// Correctness notes (these keep long-running use leak- and deadlock-free):
/// - stdout and stderr are each drained to EOF by a dedicated background read,
///   so a plugin that writes more than the pipe buffer never blocks the child.
/// - the parent's write-end handles are closed after launch, so the reads see
///   EOF the moment the child exits (otherwise `readToEnd` would hang forever).
/// - the run resumes exactly once, after both reads finish *and* the process
///   terminates, so no trailing output is lost.
/// - a timeout terminates the child (SIGTERM, then SIGKILL after a grace
///   period). Each plugin is spawned as the leader of its own process group
///   (`POSIX_SPAWN_SETPGROUP`, see `PosixSpawn.launch`), so a timeout signals
///   the whole group (`killpg`) rather than just the direct child — anything
///   the plugin backgrounded (`sleep 900 &`, a stray `curl`) is reaped too.
///   This reaping is timeout-only: a plugin that exits normally but leaves a
///   detached helper running may intend that as a daemon (see
///   `enforceTimeout`'s doc comment).
/// - if a grandchild inherits stdout and keeps the pipe open after the child
///   exits (so the drains never see EOF), the run still completes: a short
///   drain-grace force-resumes and closes the read ends.
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
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let fd = handle.fileDescriptor
        // Raw `read(2)` rather than `availableData`: it lets a stalled drain be
        // unblocked by *closing* the handle from another thread (the read returns
        // -1 and the loop ends) without `availableData`'s exception-on-error
        // behavior — the escape hatch `forceResumeIfStalled` relies on.
        while true {
            let n = read(fd, &buffer, bufferSize)
            if n == 0 { break }                       // EOF
            if n < 0 {
                if errno == EINTR { continue }        // transient interrupt: retry
                break                                 // closed / error: end drain
            }
            if accumulated.count < cap {
                accumulated.append(contentsOf: buffer[0..<Swift.min(n, cap - accumulated.count)])
            }
        }
        return accumulated
    }

    /// `waitpid`'s raw status word is decoded via C macros — `WIFEXITED`,
    /// `WEXITSTATUS`, `WIFSIGNALED`, `WTERMSIG` — none of which are imported
    /// into Swift. This reproduces their standard bit layout explicitly, named
    /// per macro. Mirrors what `Process.terminationStatus` used to report
    /// either way (the exit code, or the signal number when killed); `timedOut`
    /// is what actually governs UX, this value is otherwise diagnostic.
    static func decodeExitStatus(_ status: Int32) -> Int32 {
        let wifexited = (status & 0x7f) == 0
        if wifexited {
            let wexitstatus = (status >> 8) & 0xff
            return wexitstatus
        }
        let wifsignaled = ((status & 0x7f) + 1) >> 1 > 0
        let wtermsig = status & 0x7f
        if wifsignaled {
            return wtermsig
        }
        // Unreachable via `waitpid(pid, &status, 0)` (no WUNTRACED/WCONTINUED
        // requested, so only exited-or-signaled statuses are ever produced).
        return status
    }
}

/// Raw `posix_spawn` mechanics, split out of `ProcessRun` so its spawn-time
/// setup (file actions, attributes, argv/envp) can be read start-to-finish
/// independent of the run's completion/timeout bookkeeping.
private enum PosixSpawn {
    /// Allocation failure while building a `strdup`-backed argv/envp array —
    /// the only way `withCStringArray` can fail (out of memory).
    private enum CStringArrayError: Error {
        case allocationFailed
    }

    /// Builds a NUL-terminated, `strdup`-backed C-string array (the shape
    /// `posix_spawn`'s argv/envp parameters need) from Swift strings, hands it
    /// to `body`, then frees every `strdup`'d pointer on every exit path —
    /// including a throw from `body`. `strdup` fails only on allocation
    /// failure; that is surfaced as a thrown error rather than silently
    /// dropped. (A `compactMap` here would silently shrink the array on a
    /// single failure and misalign every later argv/envp position — a worse
    /// outcome than failing loudly.)
    private static func withCStringArray<Result>(
        _ strings: [String],
        _ body: ([UnsafeMutablePointer<CChar>?]) throws -> Result
    ) throws -> Result {
        var pointers: [UnsafeMutablePointer<CChar>?] = []
        pointers.reserveCapacity(strings.count + 1)
        defer {
            for pointer in pointers where pointer != nil { free(pointer) }
        }
        for string in strings {
            guard let duplicate = strdup(string) else { throw CStringArrayError.allocationFailed }
            pointers.append(duplicate)
        }
        pointers.append(nil)
        return try body(pointers)
    }

    /// Spawns `invocation` as the leader of a brand-new process group (its
    /// pgid equals its own pid — see `ProcessRun.enforceTimeout`'s doc comment
    /// for why), wiring stdout/stderr onto the write-end fds the caller
    /// already owns and stdin onto `/dev/null`. A menu-bar app has no
    /// terminal to hand a plugin; leaving stdin inherited-and-open (as
    /// Foundation's `Process` did) is also unsafe under
    /// `POSIX_SPAWN_CLOEXEC_DEFAULT` below, which would otherwise leave fd 0
    /// closed and let the child's first unrelated `open()` silently land
    /// there.
    ///
    /// Returns the child's pid (always > 0) on success. Throws
    /// `VeeError.launchFailed` on any failure, having cleaned up everything
    /// it allocated itself — `outWriteFD`/`errWriteFD` remain the caller's
    /// responsibility either way (they're the caller's `Pipe`, not ours).
    static func launch(_ invocation: ProcessInvocation, outWriteFD: Int32, errWriteFD: Int32) throws -> pid_t {
        let devNullFD = open("/dev/null", O_RDONLY)
        guard devNullFD >= 0 else {
            throw VeeError.launchFailed(
                pluginID: PluginID(path: invocation.launchPath),
                reason: String(cString: strerror(errno)))
        }
        // The parent's copy is never read from; the child gets its own via the
        // dup2 file action below. Close it on every exit path — including
        // failure, since nothing else will.
        defer { close(devNullFD) }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, outWriteFD, 1)
        posix_spawn_file_actions_adddup2(&fileActions, errWriteFD, 2)
        posix_spawn_file_actions_adddup2(&fileActions, devNullFD, 0)
        if let workingDirectory = invocation.workingDirectory {
            posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }

        // POSIX_SPAWN_CLOEXEC_DEFAULT is an Apple extension (spawn.h, value
        // 0x4000) that closes every inherited fd in the child except the ones
        // the file actions above explicitly dup — named locally in case the
        // Swift importer doesn't expose the constant.
        let posixSpawnCloexecDefault: Int32 = 0x4000
        let flags = Int32(POSIX_SPAWN_SETPGROUP) | Int32(POSIX_SPAWN_SETSIGDEF) | Int32(POSIX_SPAWN_SETSIGMASK) | posixSpawnCloexecDefault
        posix_spawnattr_setflags(&attr, Int16(flags))
        // pgroup 0 uses setpgid's own semantics: the child becomes the leader
        // of a brand-new group whose pgid equals its own pid. This is what
        // lets `enforceTimeout`'s killpg reach every descendant without ever
        // being able to reach Vee's own group.
        posix_spawnattr_setpgroup(&attr, 0)
        // Reset inherited signal dispositions/mask — standard spawn hygiene,
        // independent of the pgroup change above.
        var sigDefault: sigset_t = 0
        sigfillset(&sigDefault)
        posix_spawnattr_setsigdefault(&attr, &sigDefault)
        var sigMask: sigset_t = 0
        sigemptyset(&sigMask)
        posix_spawnattr_setsigmask(&attr, &sigMask)

        // argv[0] is the launch path itself (plugins may read `$0`); envp
        // REPLACES the environment, same as Foundation's `Process.environment`
        // did — no merging with Vee's own process environment.
        let argv = [invocation.launchPath] + invocation.arguments
        let envp = invocation.environment.map { "\($0.key)=\($0.value)" }

        var pid: pid_t = 0
        let rc: Int32
        do {
            rc = try withCStringArray(argv) { rawArgv in
                try withCStringArray(envp) { rawEnvp in
                    posix_spawn(&pid, invocation.launchPath, &fileActions, &attr, rawArgv, rawEnvp)
                }
            }
        } catch {
            throw VeeError.launchFailed(
                pluginID: PluginID(path: invocation.launchPath),
                reason: "failed to allocate process arguments (out of memory)")
        }

        guard rc == 0 else {
            throw VeeError.launchFailed(
                pluginID: PluginID(path: invocation.launchPath),
                reason: String(cString: strerror(rc)))
        }
        return pid
    }
}

/// Owns the mutable, non-`Sendable` machinery for one run and coordinates the
/// three completion signals (stdout drained, stderr drained, process exited)
/// so the continuation resumes exactly once. `@unchecked Sendable`: all shared
/// state is guarded by `lock`.
private final class ProcessRun: @unchecked Sendable {
    private let invocation: ProcessInvocation
    private let continuation: CheckedContinuation<ProcessOutcome, Error>

    private let outPipe = Pipe()
    private let errPipe = Pipe()

    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var exitCode: Int32 = 0
    private var timedOut = false
    /// Set by the dedicated wait thread once the child has terminated
    /// (replaces the old `process.isRunning` check from the Foundation
    /// `Process`-backed implementation). Guarded the same way `resumed` is.
    private var exited = false
    /// The exact pid `posix_spawn` returned for this run. -1 (never a valid
    /// pid) until a successful spawn sets it; `enforceTimeout` guards every
    /// kill/killpg on `pid > 0`.
    private var pid: pid_t = -1
    private var pending = 3 // stdout read, stderr read, termination
    private var resumed = false
    private var timeoutItem: DispatchWorkItem?

    /// After the child exits, its pipes should reach EOF at once. If a grandchild
    /// inherited stdout (`daemon &`, a backgrounded `curl`), EOF may never arrive
    /// and the drain reads would block forever — hanging the awaiting refresh and
    /// leaking the read threads/fds. This bounds that wait.
    private static let drainGracePeriod: TimeInterval = 3
    /// Keeps this instance alive for the duration of the run (nothing else holds
    /// a strong reference once `start()` returns). Cleared when we resume.
    private var selfRetain: ProcessRun?

    init(invocation: ProcessInvocation, continuation: CheckedContinuation<ProcessOutcome, Error>) {
        self.invocation = invocation
        self.continuation = continuation
    }

    func start() {
        selfRetain = self

        let launchedPid: pid_t
        do {
            launchedPid = try PosixSpawn.launch(
                invocation,
                outWriteFD: outPipe.fileHandleForWriting.fileDescriptor,
                errWriteFD: errPipe.fileHandleForWriting.fileDescriptor)
        } catch {
            // Nothing was ever drained and nothing will be: close every fd we
            // hold — both ends of both pipes (PosixSpawn already closed its
            // own /dev/null fd via `defer`) — before surfacing the failure.
            // Foundation's `Process` deinit used to cover this implicitly;
            // owning the raw fds means we're responsible for it explicitly.
            try? outPipe.fileHandleForReading.close()
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForWriting.close()
            resumeFailure(error)
            return
        }
        lock.withLock { pid = launchedPid }

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

        // Dedicated blocking wait (replaces Process.terminationHandler):
        // posix_spawn has no completion callback, so we reap the child
        // ourselves.
        DispatchQueue.global().async { [weak self] in
            var status: Int32 = 0
            while waitpid(launchedPid, &status, 0) == -1 && errno == EINTR {}
            let decoded = ProcessRun.decodeExitStatus(status)
            self?.noteExited()
            self?.complete { $0.exitCode = decoded }
            self?.armDrainGrace()
        }

        if let timeout = invocation.timeout {
            let item = DispatchWorkItem { [weak self] in self?.enforceTimeout() }
            lock.withLock { timeoutItem = item }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
    }

    /// Marks the child as terminated. Read by `enforceTimeout`, on a
    /// different thread, to decide whether there is still a live
    /// process/group worth signaling.
    private func noteExited() {
        lock.withLock { exited = true }
    }

    /// Terminates a timed-out plugin AND every descendant it backgrounded, by
    /// signaling the whole process group `PosixSpawn.launch` made it the
    /// leader of (`POSIX_SPAWN_SETPGROUP` + `setpgroup(0)`). Reaping the group
    /// is timeout-only by design: a plugin that exits normally but leaves a
    /// detached helper running may intend that as a daemon, so a merely-slow
    /// drain (handled by `armDrainGrace` instead, which only force-completes
    /// and closes Vee's own pipe ends) is never treated as an orphan to kill —
    /// only an actual timeout is.
    ///
    /// Safety invariants (non-negotiable): `pid` is exactly the value
    /// `posix_spawn` returned for THIS run. Because `POSIX_SPAWN_SETPGROUP`
    /// made this child's pgid equal its own pid, `killpg(pid, _)` can only
    /// ever reach that child's own group — never Vee's. Every signal below is
    /// guarded by `pid > 0`: we never call `killpg` with 0 (which means "my
    /// own group", i.e. Vee itself) or a negative value (which `kill` — not
    /// used here — would treat as "every process the caller may signal").
    /// `killpg` returning -1/ESRCH just means the group is already gone,
    /// which is fine.
    private func enforceTimeout() {
        let target: pid_t? = lock.withLock {
            guard !exited else { return nil }
            timedOut = true
            return pid
        }
        guard let target, target > 0 else { return }
        killpg(target, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let stillTarget: pid_t? = self.lock.withLock { self.exited ? nil : self.pid }
            guard let stillTarget, stillTarget > 0 else { return }
            killpg(stillTarget, SIGKILL)
        }
    }

    /// Once the child has exited, give its drains a short grace to reach EOF; if
    /// they haven't (a grandchild is still holding the pipe open), force-complete
    /// with whatever was captured and close the read ends so the parked drain
    /// threads unblock — turning a permanent hang/leak into a bounded one.
    private func armDrainGrace() {
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.drainGracePeriod) { [weak self] in
            self?.forceResumeIfStalled()
        }
    }

    private func forceResumeIfStalled() {
        var outcome: ProcessOutcome?
        lock.lock()
        if !resumed {
            resumed = true
            outcome = ProcessOutcome(
                standardOutput: String(decoding: outData, as: UTF8.self),
                standardError: String(decoding: errData, as: UTF8.self),
                exitCode: exitCode,
                timedOut: timedOut)
        }
        let item = timeoutItem
        lock.unlock()

        guard let outcome else { return } // already resumed normally — no-op
        item?.cancel()
        // Closing the read ends makes the parked raw `read()` return, so the drain
        // threads exit instead of leaking for the life of the grandchild.
        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()
        continuation.resume(returning: outcome)
        selfRetain = nil
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
