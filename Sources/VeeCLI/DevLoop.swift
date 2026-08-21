import Darwin
import Foundation
import VeePluginFormat
import VeeRuntime

// Set by the signal handlers below; polled by the loop. `sig_atomic_t` is the
// only type safe to mutate from a C signal handler. Separate from `LiveView`'s
// equivalents because `signal()` is process-global and the two loops are never
// live at once (different subcommands).
private nonisolated(unsafe) var devStopRequested: sig_atomic_t = 0
private func devStopHandler(_ sig: Int32) { devStopRequested = 1 }
private func devWinchHandler(_ sig: Int32) { /* no-op: just interrupts poll() so we repaint at the new width */ }

/// The `vee dev <path>` loop: watch one file and repaint on every save.
///
/// It differs from `LiveView` in exactly one way that matters — its wake
/// condition. `LiveView` waits out a plugin's refresh interval; `dev` has no
/// interval, it waits for the file to change. A `FileWatcher` running on its own
/// queue signals that by writing a byte to a **self-pipe**, so the loop can
/// `poll()` stdin and the pipe together and block indefinitely on both rather
/// than waking on a timer to discover nothing happened.
///
/// All rendering is delegated to the pure `frame(_:)` below, so every output
/// shape is unit-tested without a TTY, a process, or a running app.
enum DevLoop {
    // MARK: - Pure rendering

    /// Everything one save produced, in a form `frame` can render without
    /// touching a process, a file, or a terminal.
    struct Snapshot {
        let path: String
        let mode: InputMode
        let raw: String
        /// The process result, or `nil` under `--text` where nothing ran.
        let outcome: ProcessOutcome?
        /// Set when the file could not be read or run at all. The loop stays
        /// alive and shows this instead of a tree.
        let loadError: String?

        init(path: String, mode: InputMode, raw: String = "", outcome: ProcessOutcome? = nil, loadError: String? = nil) {
            self.path = path
            self.mode = mode
            self.raw = raw
            self.outcome = outcome
            self.loadError = loadError
        }
    }

    /// One full screen: status line, the parsed menu tree, any notes
    /// (diagnostics, timeout, stderr, push messages), and the key footer.
    ///
    /// `updatedAt` is passed in rather than read from the clock so this stays a
    /// pure function.
    static func frame(
        _ snapshot: Snapshot,
        width: Int,
        color: Bool,
        updatedAt: String,
        extraNotes: [String] = []
    ) -> String {
        let name = (snapshot.path as NSString).lastPathComponent
        var notes = extraNotes

        let body: String
        let healthy: Bool

        if let loadError = snapshot.loadError {
            body = TerminalRenderer.dimmed(loadError, color: color)
            healthy = false
        } else {
            let parsed = OutputParser.parseAuto(snapshot.raw)
            body = TerminalRenderer.render(parsed, options: TerminalRenderer.Options(color: color, width: width))

            for d in DiagnosticFormatter.sorted(parsed.diagnostics) {
                notes.append(DiagnosticFormatter.line(d, format: .human, path: ""))
            }
            if let outcome = snapshot.outcome {
                if outcome.timedOut { notes.append("  plugin timed out") }
                if !outcome.standardError.isEmpty {
                    notes.append("  stderr: " + outcome.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            let exitBad = (snapshot.outcome?.exitCode ?? 0) != 0 || (snapshot.outcome?.timedOut ?? false)
            healthy = !exitBad && !parsed.diagnostics.contains { $0.severity == .error }
        }

        let dot = TerminalRenderer.colored("●", healthy ? .named("green") : .named("red"), color: color)
        var statusParts = [dot + " " + name, describeMode(snapshot)]
        statusParts.append("updated " + updatedAt)
        let status = statusParts.joined(separator: TerminalRenderer.dimmed("  ·  ", color: color))

        var frame = status + "\n\n" + body
        if !notes.isEmpty {
            let block = notes.map { TerminalRenderer.dimmed($0, color: color) }.joined(separator: "\n")
            frame += (body.isEmpty ? "" : "\n\n") + block
        }
        frame += "\n\n" + TerminalRenderer.dimmed("[r] re-run   [q] quit", color: color)
        return frame + "\n"
    }

    /// What produced this frame: `--text` never ran anything, so reporting an
    /// exit code for it would be a fiction.
    private static func describeMode(_ snapshot: Snapshot) -> String {
        switch snapshot.mode {
        case .text:
            return "text (not executed)"
        case .execute:
            guard let outcome = snapshot.outcome else { return "did not run" }
            if outcome.timedOut { return "timed out" }
            return "exit \(outcome.exitCode)"
        }
    }

    /// The exit code the loop reports for a given snapshot: non-zero when the
    /// last save produced something wrong.
    static func exitCode(for snapshot: Snapshot) -> Int32 {
        if snapshot.loadError != nil { return 1 }
        if let outcome = snapshot.outcome, outcome.exitCode != 0 || outcome.timedOut { return 1 }
        let parsed = OutputParser.parseAuto(snapshot.raw)
        return parsed.diagnostics.contains { $0.severity == .error } ? 1 : 0
    }

    // MARK: - The loop

    /// Loads the file once. Never throws — a failed load becomes a snapshot the
    /// frame can display, because a broken save must repaint, not exit.
    static func snapshot(path: String, mode: InputMode, runner: ProcessRunning) async -> Snapshot {
        do {
            let loaded = try await PluginInput.load(path: path, mode: mode, runner: runner)
            return Snapshot(path: path, mode: mode, raw: loaded.raw, outcome: loaded.outcome)
        } catch {
            let verb = mode == .text ? "read" : "run"
            return Snapshot(path: path, mode: mode, loadError: "could not \(verb) '\(path)': \(error)")
        }
    }

    static func run(
        path: String,
        mode: InputMode,
        runner: ProcessRunning,
        color: Bool,
        push: PushTarget?
    ) async -> Int32 {
        let fd = STDIN_FILENO

        var original = termios()
        let hasTerminal = tcgetattr(fd, &original) == 0
        if hasTerminal {
            var raw = original
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
            raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
            _ = tcsetattr(fd, TCSANOW, &raw)
        }

        devStopRequested = 0
        installSignals()
        write("\u{1B}[?1049h\u{1B}[?25l")  // enter alt screen, hide cursor
        defer {
            write("\u{1B}[?25h\u{1B}[?1049l")  // show cursor, leave alt screen
            if hasTerminal {
                var restore = original
                _ = tcsetattr(fd, TCSANOW, &restore)
            }
        }

        // Self-pipe: the watcher runs on its own queue and cannot be polled, so
        // it signals through a descriptor that can be.
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return 1 }
        let wakeRead = fds[0]
        let wakeWrite = fds[1]
        defer { close(wakeRead); close(wakeWrite) }
        // Non-blocking, so a full pipe (many saves before a repaint) drops the
        // extra bytes instead of blocking the watcher's queue. One byte is all
        // the loop needs — the signal is "something changed", not "how many".
        _ = fcntl(wakeRead, F_SETFL, fcntl(wakeRead, F_GETFL, 0) | O_NONBLOCK)
        _ = fcntl(wakeWrite, F_SETFL, fcntl(wakeWrite, F_GETFL, 0) | O_NONBLOCK)

        let watcher = FileWatcher(path: path, debounce: 0.08) {
            var byte: UInt8 = 1
            _ = Darwin.write(wakeWrite, &byte, 1)
        }
        watcher.start()
        defer { watcher.stop() }

        var lastCode: Int32 = 0
        var pushedOnce = false

        while devStopRequested == 0 {
            let snap = await snapshot(path: path, mode: mode, runner: runner)
            lastCode = exitCode(for: snap)

            var notes: [String] = []
            if let push {
                let result = await push.send(snapshot: snap, runner: runner, isFirstPush: !pushedOnce)
                pushedOnce = true
                notes.append(contentsOf: result)
            }

            write("\u{1B}[2J\u{1B}[H" + frame(
                snap,
                width: LiveView.terminalWidth(),
                color: color,
                updatedAt: clock(),
                extraNotes: notes))

            if waitForChangeOrKey(wakeRead: wakeRead) == .quit { break }
        }

        if let push { await push.teardown(runner: runner) }
        return lastCode
    }

    // MARK: - Input

    private enum Wake { case quit, rerun }

    /// Blocks until the file changes, a key is pressed, or a signal arrives.
    /// No timeout: there is nothing to wait out, so the loop consumes nothing
    /// while idle.
    private static func waitForChangeOrKey(wakeRead: Int32) -> Wake {
        var pfds = [
            pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
            pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0),
        ]

        let ready = poll(&pfds, 2, -1)
        if devStopRequested != 0 { return .quit }
        if ready <= 0 { return .rerun }  // EINTR (e.g. SIGWINCH) → repaint at the new width

        // Drain the wake pipe so a burst of saves collapses into one re-run.
        if pfds[1].revents & Int16(POLLIN) != 0 {
            var scratch = [UInt8](repeating: 0, count: 64)
            while read(wakeRead, &scratch, scratch.count) > 0 {}
            return .rerun
        }

        if pfds[0].revents & Int16(POLLIN) != 0 {
            var byte: UInt8 = 0
            let n = read(STDIN_FILENO, &byte, 1)
            // EOF on stdin must quit, not repaint. `poll()` reports a closed
            // descriptor as readable *every* time, so returning `.rerun` here
            // would spin the loop at full speed — re-running the author's script
            // continuously — with no key left that could ever stop it.
            if n == 0 { return .quit }
            if n < 0 { return .rerun }   // EINTR and friends
            switch byte {
            case 0x71, 0x51, 0x03: return .quit    // q, Q, Ctrl-C
            default: return .rerun                 // r re-runs; anything else repaints
            }
        }
        return .rerun
    }

    // MARK: - Terminal helpers

    private static func installSignals() {
        _ = signal(SIGINT, devStopHandler)
        _ = signal(SIGTERM, devStopHandler)
        _ = signal(SIGHUP, devStopHandler)
        _ = signal(SIGWINCH, devWinchHandler)
    }

    private static func clock() -> String {
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        func pad(_ n: Int?) -> String {
            let v = n ?? 0
            return v < 10 ? "0\(v)" : "\(v)"
        }
        return pad(now.hour) + ":" + pad(now.minute) + ":" + pad(now.second)
    }

    private static func write(_ s: String) {
        FileHandle.standardOutput.write(Data(s.utf8))
    }
}
