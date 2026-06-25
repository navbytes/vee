import Foundation

// MARK: - Thin real AppKit adapters (NOT unit-tested; need a desktop session)
//
// These are the logic-free OS adapters behind the VeeServices seams that touch
// AppKit / Launch Services / NSPasteboard. They contain NO business logic:
//   - de-dup + fuzzy + frecency live in `AppSearchProvider` (above `AppEnumerating`)
//   - the privacy filter + capture pipeline live in `ClipboardMonitor` (above
//     `PasteboardReading`)
// so these types only translate OS values into the value types each protocol
// already defines. They cannot be unit-tested (real `NSWorkspace`/`NSPasteboard`
// have no fakes), so the bar is compile-clean + faithful-to-the-API; each is
// verified manually on a desktop.

#if canImport(AppKit)
import AppKit

// MARK: App enumeration (Launch Services / /Applications scan)

/// Thin `NSWorkspace`-backed `AppEnumerating`. Scans `/Applications`,
/// `/System/Applications`, and `~/Applications` for `.app` bundles and reads each
/// bundle's identifier + display name. Logic-free: de-dup (across roots) and
/// ranking live ABOVE this seam in `AppSearchProvider`, so this just enumerates.
///
/// NOT unit-tested — it reads the real filesystem / Launch Services. Verify on a
/// desktop (see the manual-verification note in the build report).
public final class NSWorkspaceAppEnumerator: AppEnumerating {
    /// The roots to scan (build plan Plugin 5: `/Applications`,
    /// `/System/Applications`, `~/Applications`). Overridable for flexibility;
    /// the default mirrors the spec.
    private let roots: [URL]
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    /// - Parameters:
    ///   - roots: directories to scan. Defaults to the three standard app roots.
    ///   - fileManager: injected so the path expansion uses one instance.
    ///   - workspace: the `NSWorkspace` used for launching.
    public init(roots: [URL]? = nil,
                fileManager: FileManager = .default,
                workspace: NSWorkspace = .shared) {
        self.fileManager = fileManager
        self.workspace = workspace
        if let roots {
            self.roots = roots
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            self.roots = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                URL(fileURLWithPath: "/System/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true),
            ]
        }
    }

    /// Every `.app` bundle found under the roots, as `AppRecord` values. Recurses
    /// into sub-directories (e.g. `/Applications/Utilities`) but treats each
    /// `.app` as a leaf (`skipsPackageDescendants`), so apps nested inside another
    /// app's bundle aren't surfaced. May contain duplicates across roots — de-dup
    /// is done above the seam.
    public func enumerateApps() -> [AppRecord] {
        var out: [AppRecord] = []
        for root in roots {
            out.append(contentsOf: enumerateApps(in: root))
        }
        return out
    }

    private func enumerateApps(in root: URL) -> [AppRecord] {
        // Skip roots that don't exist (e.g. a user without ~/Applications).
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let keys: [URLResourceKey] = [.isApplicationKey, .isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            // Descend into folders but never walk INTO a `.app` package, and skip
            // hidden files. This makes a `.app` a leaf node we record directly.
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var out: [AppRecord] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            if let record = appRecord(at: url) {
                out.append(record)
            }
        }
        return out
    }

    /// Read bundle id + display name from a `.app` URL. Returns nil if the bundle
    /// has no identifier (we key on bundleId above the seam). Display name prefers
    /// `CFBundleDisplayName`, then `CFBundleName`, then the file name.
    private func appRecord(at url: URL) -> AppRecord? {
        guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else {
            return nil
        }
        let info = bundle.infoDictionary
        let displayName = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppRecord(name: displayName, bundleId: bundleId, path: url.path)
    }

    // MARK: Launch

    /// Launch (or activate) the app at `url` via the modern
    /// `openApplication(at:configuration:)`. Logic-free fire-and-forget; the
    /// optional completion forwards any OS error. Deprecated `launchApplication`
    /// is intentionally avoided.
    public func launch(at url: URL,
                       configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration(),
                       completion: ((Error?) -> Void)? = nil) {
        workspace.openApplication(at: url, configuration: configuration) { _, error in
            completion?(error)
        }
    }

    /// Resolve a `bundleId` to its on-disk URL via Launch Services, then launch
    /// it (the sandbox-friendly path). Calls `completion` with a resolution error
    /// if the bundle id is unknown.
    public func launch(bundleId: String,
                       configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration(),
                       completion: ((Error?) -> Void)? = nil) {
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleId) else {
            completion?(CocoaError(.fileNoSuchFile))
            return
        }
        launch(at: url, configuration: configuration, completion: completion)
    }
}

// MARK: Pasteboard reading

/// Thin `NSPasteboard`-backed `PasteboardReading`. Exposes the live
/// `changeCount` and snapshots the current item's declared types + plain-text
/// representation into a `PasteboardItemSnapshot`. NO filtering — the pure
/// `ClipboardPrivacyFilter` (above the seam, in `ClipboardMonitor`) consumes the
/// snapshot and decides what to drop.
///
/// NOT unit-tested — it reads the real `NSPasteboard.general`. Verify on a
/// desktop.
public final class NSPasteboardReader: PasteboardReading {
    private let pasteboard: NSPasteboard

    /// - Parameter pasteboard: defaults to `.general`; injectable for a named
    ///   pasteboard if ever needed.
    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Mirrors `NSPasteboard.changeCount` (monotonic; bumped on every write).
    public var changeCount: Int { pasteboard.changeCount }

    /// Snapshot the current pasteboard: all declared type identifiers and the
    /// plain-text (`.string`) representation if present. `text` is nil for
    /// non-text items (which the monitor ignores). No filtering happens here.
    public func currentSnapshot() -> PasteboardItemSnapshot {
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let text = pasteboard.string(forType: .string)
        return PasteboardItemSnapshot(types: types, text: text)
    }
}

// MARK: Poll driver

/// Drives a `ClipboardMonitor` by ticking its `poll()` on a `DispatchSourceTimer`
/// at a fixed interval (default 500 ms, matching
/// `ClipboardMonitor.defaultPollInterval` / Maccy). Logic-free: it only schedules
/// the tick; ALL capture/privacy logic lives in the monitor above the seam.
///
/// `NSPasteboard` access is main-thread-friendly, so the timer fires on the main
/// queue by default. NOT unit-tested — it exists to wire the real monitor to a
/// running app; verify on a desktop.
public final class ClipboardPollDriver {
    private let monitor: ClipboardMonitor
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?

    /// - Parameters:
    ///   - monitor: the tested monitor whose `poll()` we tick.
    ///   - interval: poll cadence (default `ClipboardMonitor.defaultPollInterval`).
    ///   - queue: queue the tick runs on (default `.main`, since the snapshot
    ///     reads `NSPasteboard`).
    public init(monitor: ClipboardMonitor,
                interval: TimeInterval = ClipboardMonitor.defaultPollInterval,
                queue: DispatchQueue = .main) {
        self.monitor = monitor
        self.interval = interval
        self.queue = queue
    }

    /// Start ticking. Idempotent — a second call while running is a no-op.
    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval,
                       repeating: interval,
                       leeway: .milliseconds(50))
        let monitor = self.monitor
        timer.setEventHandler {
            monitor.poll()
        }
        self.timer = timer
        timer.resume()
    }

    /// Stop ticking. Idempotent.
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        timer?.cancel()
    }
}

#endif
