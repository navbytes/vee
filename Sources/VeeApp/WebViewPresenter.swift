import AppKit
import WebKit

/// Shows a plugin's `webview=` URL in a standalone floating window (a WKWebView
/// hosted in a normal window, never inside the menu — so the menu stays native
/// and leak-free). Retains each window until the user closes it.
@MainActor
final class WebViewPresenter {
    static let shared = WebViewPresenter()

    private var windows: [NSWindow] = []

    func show(url: URL, width: Double?, height: Double?) {
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

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                self?.windows.removeAll { $0 === window }
            }
        }
    }
}
