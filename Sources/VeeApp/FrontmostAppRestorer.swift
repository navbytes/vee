import AppKit

/// Tracks whatever app was frontmost before Vee stole activation (to make a
/// panel/window key), and hands it back on demand.
///
/// Extracted out of `MenuSearchPanel` so the capture/restore/one-shot ordering
/// is independently testable without a live NSPanel or window server — see
/// `FrontmostAppRestorerTests`.
struct FrontmostAppRestorer {
    private(set) var captured: NSRunningApplication?

    mutating func capture(_ app: NSRunningApplication?) {
        captured = app
    }

    /// Restores the captured app via `activator`, then clears it — a second
    /// call with nothing captured is a no-op, so repeated dismissals (e.g. a
    /// stray Esc after a row already activated) don't re-fire activation.
    mutating func restore(activator: (NSRunningApplication) -> Void = { $0.activate(options: []) }) {
        guard let captured else { return }
        activator(captured)
        self.captured = nil
    }
}
