import Foundation
import VeeCore

/// Watches the plugins directory for changes and invokes a handler (debounced)
/// so the runtime can re-enumerate. Uses a `DispatchSource` vnode source on the
/// directory rather than the full FSEvents C API — sufficient for a single
/// flat plugins folder and simpler to reason about.
///
/// `@unchecked Sendable`: state is confined to `queue`.
public final class PluginDirectoryWatcher: @unchecked Sendable {
    private let directory: String
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "com.vee.plugin-watcher")
    private let onChange: @Sendable () -> Void

    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pendingWork: DispatchWorkItem?

    public init(directory: String, debounce: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in self?.openSource() }
    }

    public func stop() {
        queue.async { [weak self] in self?.closeSource() }
    }

    private func openSource() {
        closeSource()
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else {
            VeeLog.make("plugin-watcher").error("cannot watch \(self.directory, privacy: .public)")
            return
        }
        fileDescriptor = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.scheduleNotify() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    private func scheduleNotify() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func closeSource() {
        pendingWork?.cancel()
        pendingWork = nil
        source?.cancel()
        source = nil
    }

    deinit { closeSource() }
}
