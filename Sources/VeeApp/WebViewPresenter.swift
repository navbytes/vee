import AppKit
import VeePluginFormat
import WebKit

/// Shows a plugin's `webview=` URL in a standalone floating window (a WKWebView
/// hosted in a normal window, never inside the menu — so the menu stays native
/// and leak-free). Retains each window until the user closes it.
@MainActor
final class WebViewPresenter {
    static let shared = WebViewPresenter()

    private var windows: [NSWindow] = []
    /// Close-observer tokens, keyed by window identity. Owned here (presenter
    /// state) rather than captured by the observer closure: a token local
    /// captured by the `@Sendable` notification closure is a non-Sendable
    /// value crossing isolation regions, which strict concurrency rejects as
    /// a data race.
    private var observerTokens: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// The window size for a `webview=` row, bounded by the screen it will open
    /// on.
    ///
    /// `webvieww=`/`webviewh=` come straight from plugin stdout and used to
    /// reach `NSWindow(contentRect:)` unbounded, so `webvieww=99999` opened a
    /// window far larger than the display — with its title bar and close button
    /// off-screen, which is a window the user cannot dismiss. Clamping to the
    /// visible frame keeps the chrome reachable. Nothing here is a matter of
    /// taste: a window bigger than the screen is never what the author meant.
    ///
    /// `static` and internal so the bounds are unit-testable without opening a
    /// real window.
    static func windowSize(width: Double?, height: Double?, screen: NSSize? = nil) -> NSSize {
        let visible = screen ?? NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let minimumSide: Double = 120
        func bound(_ requested: Double?, default fallback: Double, limit: Double) -> Double {
            let value = requested ?? fallback
            guard value.isFinite else { return fallback }
            return Swift.min(Swift.max(value, minimumSide), Swift.max(limit, minimumSide))
        }
        return NSSize(
            width: bound(width, default: 640, limit: Double(visible.width)),
            height: bound(height, default: 480, limit: Double(visible.height))
        )
    }

    func show(url: URL, width: Double?, height: Double?) {
        // Defense in depth: the parser already restricts `webview=` to http/https,
        // but never load a non-web URL (e.g. file://) into an in-app WKWebView.
        guard URLScheme.isWebURL(url) else { return }
        let size = Self.windowSize(width: width, height: height)
        let webView = WKWebView(frame: NSRect(origin: .zero, size: size))
        webView.load(URLRequest(url: url))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.host ?? "Vee"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows.append(window)

        // Evict on close *any* way — a discarded observer token would leave
        // the block registration alive forever, accumulating one dead
        // observer per window ever opened.
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                self?.windowDidClose(window)
            }
        }
        // Stored in presenter state (not captured by the closure) so the
        // handler can unregister it. Ordering is safe: willClose can only fire
        // on a later main-runloop turn, so the token is always stored before
        // the handler could ever consume it.
        observerTokens[ObjectIdentifier(window)] = token
    }

    /// Releases the closed window and unregisters its close observer.
    private func windowDidClose(_ window: NSWindow) {
        windows.removeAll { $0 === window }
        if let token = observerTokens.removeValue(forKey: ObjectIdentifier(window)) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
