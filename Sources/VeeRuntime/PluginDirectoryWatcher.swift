import Foundation
import VeeCore

/// Watches the plugins directory for changes and invokes a handler (debounced)
/// so the runtime can re-enumerate. Uses a `DispatchSource` vnode source on the
/// directory rather than the full FSEvents C API — sufficient for a single
/// flat plugins folder and simpler to reason about.
///
/// The vnode source only fires on directory-entry add/remove/rename — an
/// in-place edit (`nano`, append, `chmod` on an existing plugin file) produces
/// no event there, so a periodic tick also calls the same debounced `onChange`.
/// `AppController.reload()` already no-ops cheaply when its mtime-keyed
/// signature is unchanged, so the poll just reuses that existing dedupe rather
/// than needing its own. The tick additionally recovers from the watched
/// directory itself being deleted and recreated (switching plugins folders, or
/// an editor's atomic-replace of a directory), which otherwise leaves the fd
/// pointed at a dead inode and the watcher silently inert until relaunch.
///
/// `@unchecked Sendable`: state is confined to `queue`.
public final class PluginDirectoryWatcher: @unchecked Sendable {
    private let directory: String
    private let debounce: TimeInterval
    private let tickInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.vee.plugin-watcher")
    private let onChange: @Sendable () -> Void

    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pendingWork: DispatchWorkItem?
    private var tickTimer: DispatchSourceTimer?
    /// Set when the watched fd itself is deleted/renamed (the directory, not
    /// just an entry inside it) — the vnode source is now watching a dead
    /// inode. Checked (and cleared on a successful reopen) on the next tick.
    private var sourceInvalidated = false

    public init(directory: String, debounce: TimeInterval = 0.3, tickInterval: TimeInterval = 15, onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.debounce = debounce
        self.tickInterval = tickInterval
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in
            self?.openSource()
            self?.scheduleTick()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.closeSource()
            self?.cancelTick()
        }
    }

    private func openSource() {
        closeSource()
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else {
            VeeLog.make("plugin-watcher").error("cannot watch \(self.directory, privacy: .public)")
            return
        }
        fileDescriptor = fd
        sourceInvalidated = false
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.handleDirectoryEvent() }
        // Close the fd this specific source owns — not `self.fileDescriptor` —
        // since by the time this (async) cancel handler runs, a later reopen
        // may already have replaced it with a newer fd, and closing that would
        // close the wrong one.
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    /// Fires for a write inside the directory (an entry was added, removed, or
    /// renamed — the common case) as well as a delete/rename of the watched
    /// directory itself, which is flagged so the next tick reopens.
    private func handleDirectoryEvent() {
        if let mask = source?.data, mask.contains(.delete) || mask.contains(.rename) {
            sourceInvalidated = true
        }
        scheduleNotify()
    }

    private func scheduleNotify() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// A periodic backstop, wall-clock scheduled (so a tick due mid-sleep fires
    /// promptly on wake, same reasoning as `CronScheduler`): catches in-place
    /// file edits the vnode source can't see, and reopens the source if the
    /// watched directory itself went away. Deliberately independent of
    /// `closeSource()`/`openSource()` — a reopen triggered from inside `tick()`
    /// must not cancel the very timer that's driving it.
    private func scheduleTick() {
        cancelTick()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(wallDeadline: .now() + tickInterval, repeating: tickInterval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.tick() }
        tickTimer = t
        t.resume()
    }

    private func cancelTick() {
        tickTimer?.cancel()
        tickTimer = nil
    }

    private func tick() {
        if sourceInvalidated || !sourceMatchesCurrentDirectory() {
            // Retries every tick until open() succeeds (e.g. the directory
            // hasn't been recreated yet).
            openSource()
        }
        scheduleNotify()
    }

    /// Whether the open fd still refers to the directory currently at
    /// `directory` — false if the path is no longer stat-able, or resolves to
    /// a different inode (deleted and recreated at the same path). Guards
    /// against the vnode source's delete/rename event being missed or
    /// coalesced away.
    private func sourceMatchesCurrentDirectory() -> Bool {
        guard fileDescriptor >= 0 else { return false }
        var openStat = stat()
        guard fstat(fileDescriptor, &openStat) == 0 else { return false }
        var pathStat = stat()
        guard stat(directory, &pathStat) == 0 else { return false }
        return openStat.st_dev == pathStat.st_dev && openStat.st_ino == pathStat.st_ino
    }

    /// Tears down the vnode source, its fd, and any pending debounced notify.
    /// Safe to call repeatedly — `openSource()` calls this at its top before
    /// reopening. Deliberately leaves the tick timer alone; see `cancelTick()`.
    private func closeSource() {
        pendingWork?.cancel()
        pendingWork = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    deinit {
        closeSource()
        cancelTick()
    }
}
