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

    func show(url: URL, width: Double?, height: Double?) {
        // Defense in depth: the parser already restricts `webview=` to http/https,
        // but never load a non-web URL (e.g. file://) into an in-app WKWebView.
        guard URLScheme.isWebURL(url) else { return }
        let size = NSSize(width: width ?? 640, height: height ?? 480)
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
