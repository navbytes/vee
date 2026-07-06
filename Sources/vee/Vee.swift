import AppKit
import VeeApp
import VeeCLI
import VeeRuntime

/// Thin executable entry point for development (`swift run vee`). The
/// distributable app bundle uses the same `AppController` via the Xcode target.
///
/// `main()` inspects the arguments: a `render`/`lint`/`new` subcommand (or
/// `--help`/`--version`) dispatches to `VeeCLI` and exits. Everything else —
/// no args, a double-click, or a LaunchServices `-psn_…` argument — falls
/// through to the EXISTING NSApplication launch path unchanged, so the menu-bar
/// app still boots.
@main
struct Vee {
    @MainActor
    static func main() {
        switch ArgumentClassifier.classify(CommandLine.arguments) {
        case .none:
            launchApp()
        case .subcommand, .topLevelFlag:
            runCLIAndExit()
        }
    }

    // MARK: - App launch (unchanged)

    @MainActor
    private static func launchApp() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        // `.accessory`: menu-bar-only, no Dock icon or app-switcher entry.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // MARK: - CLI dispatch

    private static func runCLIAndExit() -> Never {
        let args = Array(CommandLine.arguments.dropFirst())
        // Run the async CLI entry synchronously via a semaphore.
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outBuf = ""
        nonisolated(unsafe) var errBuf = ""
        nonisolated(unsafe) var code: Int32 = 0
        Task.detached {
            code = await VeeCLI.run(args, runner: SystemProcessRunner(), out: &outBuf, err: &errBuf)
            semaphore.signal()
        }
        semaphore.wait()

        if !outBuf.isEmpty { FileHandle.standardOutput.write(Data(outBuf.utf8)) }
        if !errBuf.isEmpty { FileHandle.standardError.write(Data(errBuf.utf8)) }
        exit(code)
    }
}
