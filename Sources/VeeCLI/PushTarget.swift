import Foundation
import VeePluginFormat
import VeeRuntime

/// `vee dev --push`: render each save as a **real** status item in the running
/// Vee app, so the author sees Vee's native render rather than only a textual
/// tree.
///
/// `VeeCLI` does not link AppKit, so this cannot reach for `NSWorkspace`.
/// It shells out to `/usr/bin/open` through the same injected `ProcessRunning`
/// seam the rest of the CLI uses — which keeps the whole thing testable with a
/// fake runner.
///
/// The transport is the existing `vee://setephemeralplugin` deep link, which
/// already renders arbitrary protocol text as a status item with **no file on
/// disk**. That also means it inherits the link's defenses: because any web page
/// can open a `vee://` URL, Vee strips `shell=`/`bash=` actions from ephemeral
/// content. A previewed row carrying one is therefore visible but inert, and the
/// loop says so rather than letting it silently do nothing.
struct PushTarget {
    /// Stable across saves so each save *updates* one status item instead of
    /// accumulating one per save.
    let key: String

    /// Encoded-content ceiling. A URL argument is bounded by `ARG_MAX` and by
    /// LaunchServices, while plugin stdout is capped at 8 MB — so an oversized
    /// menu must be refused with an explanation rather than failing opaquely.
    static let maxEncodedBytes = 32 * 1024

    /// Every push carries a long expiry as a crash-safety net: a `SIGKILL`ed
    /// loop never runs its teardown, and a stranded preview that lives until Vee
    /// quits is worse than one that expires on its own.
    static let safetyNetExpiry = 3600

    init(path: String) {
        self.key = "dev:" + (path as NSString).lastPathComponent
    }

    // MARK: - URL construction (pure)

    /// Percent-encodes `content` for a query value.
    ///
    /// Explicit rather than via `URLComponents.queryItems`, whose escaping of
    /// `&` and `+` in values has historically been inconsistent — and a menu
    /// body is exactly the kind of text that contains both. Everything reserved
    /// in a query is escaped here, so the receiving `URLComponents` decode is
    /// unambiguous.
    static func encode(_ content: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
        return content.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// The deep link for one push, or `nil` when the encoded content exceeds
    /// `maxEncodedBytes`.
    static func url(key: String, content: String, exitAfter: Int?) -> String? {
        let encodedContent = encode(content)
        guard encodedContent.utf8.count <= maxEncodedBytes else { return nil }
        var url = "vee://setephemeralplugin?name=\(encode(key))&content=\(encodedContent)"
        if let exitAfter { url += "&exitafter=\(exitAfter)" }
        return url
    }

    /// Whether a parsed menu contains any `shell=`/`bash=` action — the rows an
    /// ephemeral preview will show but refuse to fire.
    static func containsShellAction(_ output: ParsedOutput) -> Bool {
        if output.titleLines.contains(where: { $0.params.shell != nil }) { return true }
        func walk(_ nodes: [MenuNode]) -> Bool {
            for node in nodes {
                guard case .item(let item) = node else { continue }
                if item.params.shell != nil { return true }
                if item.alternate?.params.shell != nil { return true }
                if walk(item.submenu) { return true }
            }
            return false
        }
        return walk(output.body)
    }

    // MARK: - Sending

    /// Pushes one save. Returns notes for the frame — never throws, and never
    /// stops the textual loop, because the preview is the secondary view.
    func send(snapshot: DevLoop.Snapshot, runner: ProcessRunning, isFirstPush: Bool) async -> [String] {
        var notes: [String] = []

        // Nothing to preview if the file could not be loaded at all.
        if snapshot.loadError != nil { return notes }

        guard let url = Self.url(key: key, content: snapshot.raw, exitAfter: Self.safetyNetExpiry) else {
            notes.append("  preview skipped: menu is larger than \(Self.maxEncodedBytes / 1024) KB")
            return notes
        }

        // Whether Vee is already up decides only whether we *announce* a launch;
        // `open` starts it either way. Checked once, on the first push.
        var announceLaunch = false
        if isFirstPush {
            announceLaunch = !(await Self.veeIsRunning(runner: runner))
        }

        let opened = await Self.open(url: url, runner: runner)
        if !opened {
            notes.append("  preview could not be shown: no installed Vee handled vee://")
            return notes
        }

        if announceLaunch {
            notes.append("  Vee was not running — started it in the background to show the preview")
        }
        if isFirstPush, Self.containsShellAction(OutputParser.parseAuto(snapshot.raw)) {
            notes.append("  note: shell=/bash= rows appear in the preview but do not fire (ephemeral content is defanged)")
        }
        return notes
    }

    /// Removes the preview on a clean exit. Empty content with a 1-second expiry
    /// rather than a dedicated URL action, because none exists — and inventing
    /// one is a change to the app's deep-link surface, not to this loop.
    func teardown(runner: ProcessRunning) async {
        guard let url = Self.url(key: key, content: "", exitAfter: 1) else { return }
        _ = await Self.open(url: url, runner: runner)
    }

    // MARK: - Process helpers

    /// `-g` keeps the launch in the background so a dev command never steals
    /// focus from the author's editor.
    private static func open(url: String, runner: ProcessRunning) async -> Bool {
        let invocation = ProcessInvocation(
            launchPath: "/usr/bin/open",
            arguments: ["-g", url],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: FileManager.default.currentDirectoryPath,
            timeout: 10)
        guard let outcome = try? await runner.run(invocation) else { return false }
        return outcome.exitCode == 0
    }

    /// Matches the app bundle's executable path specifically. A bare `pgrep -x
    /// vee` would match the `vee` CLI running this very loop.
    private static func veeIsRunning(runner: ProcessRunning) async -> Bool {
        let invocation = ProcessInvocation(
            launchPath: "/usr/bin/pgrep",
            arguments: ["-f", "Vee.app/Contents/MacOS/"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: FileManager.default.currentDirectoryPath,
            timeout: 5)
        guard let outcome = try? await runner.run(invocation) else { return false }
        return outcome.exitCode == 0 && !outcome.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
