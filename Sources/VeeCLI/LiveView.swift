import Darwin
import Foundation
import VeeCore
import VeeRuntime

// Set by the signal handlers below; polled by the live loop. `sig_atomic_t` is
// the only type safe to mutate from a C signal handler.
private nonisolated(unsafe) var liveStopRequested: sig_atomic_t = 0
private func liveStopHandler(_ sig: Int32) { liveStopRequested = 1 }
private func liveWinchHandler(_ sig: Int32) { /* no-op: just interrupts poll() so we repaint at the new width */ }

/// The interactive `vee show <plugin>` loop: paints the plugin's rendered
/// dropdown to an alternate screen and re-runs it on the plugin's own filename
/// cadence, with `r` to refresh now and `q` to quit. This is the only part of
/// `vee show` that touches the real terminal (raw-mode stdin, alt screen); all
/// rendering is delegated to the pure `TerminalRenderer` / `VeeCLI.showBody`, so
/// the loop stays thin. Never entered from tests — `VeeCLI.runShow` only calls
/// it on a genuine interactive TTY.
enum LiveView {
    private enum Wait { case quit, refresh, timeout }

    static func run(resolved: PluginResolver.Resolved, runner: ProcessRunning, color: Bool) async -> Int32 {
        let fd = STDIN_FILENO

        var original = termios()
        let hasTerminal = tcgetattr(fd, &original) == 0
        if hasTerminal {
            var raw = original
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
            raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
            _ = tcsetattr(fd, TCSANOW, &raw)
        }

        liveStopRequested = 0
        installSignals()
        write("\u{1B}[?1049h\u{1B}[?25l")  // enter alt screen, hide cursor
        defer {
            write("\u{1B}[?25h\u{1B}[?1049l")  // show cursor, leave alt screen
            if hasTerminal {
                var restore = original
                _ = tcsetattr(fd, TCSANOW, &restore)
            }
        }

        var lastCode: Int32 = 0
        while liveStopRequested == 0 {
            let width = terminalWidth()
            let result = await VeeCLI.showBody(resolved: resolved, runner: runner, color: color, width: width)
            lastCode = result.code
            write("\u{1B}[2J\u{1B}[H" + frame(result: result, color: color))

            switch waitForKeyOrTimeout(interval: resolved.interval) {
            case .quit: return lastCode
            case .refresh, .timeout: continue
            }
        }
        return lastCode
    }

    // MARK: - Frame

    private static func frame(
        result: (status: String, body: String, code: Int32, timedOut: Bool),
        color: Bool
    ) -> String {
        let header = result.status + TerminalRenderer.dimmed("  ·  updated " + clock(), color: color)
        let footer = TerminalRenderer.dimmed("[r] refresh   [q] quit", color: color)
        return header + "\n\n" + result.body + "\n\n" + footer + "\n"
    }

    private static func clock() -> String {
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        func pad(_ n: Int?) -> String {
            let v = n ?? 0
            return v < 10 ? "0\(v)" : "\(v)"
        }
        return pad(now.hour) + ":" + pad(now.minute) + ":" + pad(now.second)
    }

    // MARK: - Input

    /// Blocks until the plugin's interval elapses (`.timeout`) or a key is
    /// pressed. `q`/`Ctrl-C` quit; `r` refreshes now; any other key repaints. A
    /// `.manual`/`.cron` plugin has no fixed interval, so it waits on a key.
    private static func waitForKeyOrTimeout(interval: RefreshInterval) -> Wait {
        var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)

        let timeout: Int32
        if let seconds = interval.timeInterval {
            let ms = Int((max(0, seconds) * 1000).rounded())
            timeout = Int32(clamping: max(1, ms))
        } else {
            timeout = -1  // manual / cron: wait for a keypress
        }

        let ready = poll(&pfd, 1, timeout)
        if liveStopRequested != 0 { return .quit }
        if ready <= 0 { return .timeout }  // 0 = interval elapsed; <0 = EINTR (e.g. SIGWINCH) → repaint

        var byte: UInt8 = 0
        let n = read(STDIN_FILENO, &byte, 1)
        if n <= 0 { return .timeout }
        switch byte {
        case 0x71, 0x51, 0x03: return .quit      // q, Q, Ctrl-C
        case 0x72, 0x52: return .refresh          // r, R
        default: return .timeout
        }
    }

    // MARK: - Terminal helpers

    private static func installSignals() {
        _ = signal(SIGINT, liveStopHandler)
        _ = signal(SIGTERM, liveStopHandler)
        _ = signal(SIGHUP, liveStopHandler)
        _ = signal(SIGWINCH, liveWinchHandler)
    }

    static func terminalWidth() -> Int {
        var ws = winsize()
        let ok = withUnsafeMutablePointer(to: &ws) { ptr in
            ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), ptr) == 0
        }
        if ok, ws.ws_col > 0 { return Int(ws.ws_col) }
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"], let n = Int(columns), n > 0 {
            return n
        }
        return 80
    }

    private static func write(_ s: String) {
        FileHandle.standardOutput.write(Data(s.utf8))
    }
}
