import Foundation

/// Watches a **single file** and invokes a debounced handler whenever its
/// contents change.
///
/// A vnode source on a *directory* does not fire for a write to an entry inside
/// it — that gap is why `PluginDirectoryWatcher` carries a periodic tick. A
/// vnode source on the *file itself* does fire for a write, which is what this
/// type exists to provide.
///
/// The hard part is that a vnode source is bound to an **inode**, not a path,
/// and most editors do not save by writing in place: they write a temporary
/// file alongside the target and `rename()` it over. After that the watched fd
/// refers to the old, now-unlinked inode, and every subsequent save is
/// invisible. So the debounced handler always re-verifies that the open fd
/// still refers to whatever currently lives at `path`, and reopens when it does
/// not. A save that deletes before recreating can leave nothing to reopen for a
/// moment, so a failed reopen retries on a short backoff rather than leaving the
/// watcher permanently inert.
///
/// `@unchecked Sendable`: all mutable state is confined to `queue`.
public final class FileWatcher: @unchecked Sendable {
    private let path: String
    private let debounce: TimeInterval
    private let reopenRetry: TimeInterval
    private let queue = DispatchQueue(label: "com.vee.file-watcher")
    private let onChange: @Sendable () -> Void

    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pendingWork: DispatchWorkItem?
    private var retryTimer: DispatchSourceTimer?
    private var stopped = false

    public init(
        path: String,
        debounce: TimeInterval = 0.05,
        reopenRetry: TimeInterval = 0.2,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.path = path
        self.debounce = debounce
        self.reopenRetry = reopenRetry
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.openSource()
        }
    }

    /// Idempotent — safe to call repeatedly, and after it returns (on `queue`)
    /// no further handler invocations are scheduled.
    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.closeSource()
            self.cancelRetry()
        }
    }

    // MARK: - Source lifecycle

    private func openSource() {
        closeSource()
        guard !stopped else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // Nothing at the path right now (a delete-then-recreate save
            // mid-flight, or a file that doesn't exist yet). Keep trying.
            scheduleRetry()
            return
        }
        cancelRetry()
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            // `.attrib` catches `chmod +x`, which changes whether the file can
            // be run at all — a change worth re-running for.
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.scheduleNotify() }
        // Close the fd this specific source owns rather than
        // `self.fileDescriptor`: by the time this async cancel handler runs, a
        // reopen may already have replaced it, and closing that would close the
        // wrong descriptor. Same reasoning as `PluginDirectoryWatcher`.
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func closeSource() {
        pendingWork?.cancel()
        pendingWork = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    // MARK: - Notification

    private func scheduleNotify() {
        guard !stopped else { return }
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fire() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// Runs once per debounce window: re-bind to the current inode if the file
    /// was replaced, then notify. Re-binding happens *before* notifying so the
    /// handler never runs while the watcher is pointed at a dead inode.
    private func fire() {
        guard !stopped else { return }
        if !sourceMatchesCurrentPath() { openSource() }
        onChange()
    }

    /// Whether the open fd still refers to whatever currently lives at `path` —
    /// false if the path is no longer stat-able, or resolves to a different
    /// inode (the atomic-replace case).
    private func sourceMatchesCurrentPath() -> Bool {
        guard fileDescriptor >= 0 else { return false }
        var openStat = stat()
        guard fstat(fileDescriptor, &openStat) == 0 else { return false }
        var pathStat = stat()
        guard stat(path, &pathStat) == 0 else { return false }
        return openStat.st_dev == pathStat.st_dev && openStat.st_ino == pathStat.st_ino
    }

    // MARK: - Reopen retry

    /// Retries `openSource()` until the path exists again. Without this, a save
    /// that unlinks before recreating would leave the watcher inert for the rest
    /// of the session.
    private func scheduleRetry() {
        guard !stopped, retryTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + reopenRetry, repeating: reopenRetry, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in
            guard let self, !self.stopped else { return }
            // `openSource()` cancels this timer once `open()` succeeds. Notify
            // too: whatever replaced the file is itself a change worth seeing.
            self.openSource()
            if self.fileDescriptor >= 0 { self.onChange() }
        }
        retryTimer = t
        t.resume()
    }

    private func cancelRetry() {
        retryTimer?.cancel()
        retryTimer = nil
    }

    deinit {
        closeSource()
        cancelRetry()
    }
}
