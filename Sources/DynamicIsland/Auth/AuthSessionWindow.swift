import AppKit
import SwiftUI
import WebKit

@MainActor
final class AuthSessionController: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    static let shared = AuthSessionController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    var onAuthenticated: ((String) -> Void)?

    func presentLogin() {
        // Accessory (LSUIElement) apps often fail to surface windows unless briefly regular.
        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 700), configuration: config)
        webView.navigationDelegate = self
        config.websiteDataStore.httpCookieStore.add(self)
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Cursor"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        let url = URL(string: "https://cursor.com/dashboard")!
        webView.load(URLRequest(url: url))
        Task { await inspectCookies() }
    }

    func close() {
        window?.delegate = nil
        window?.close()
        cleanupWebView()
        window = nil
        restoreActivationPolicy()
    }

    private func cleanupWebView() {
        if let webView {
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        }
        webView = nil
    }

    private func restoreActivationPolicy() {
        if let previousActivationPolicy {
            NSApp.setActivationPolicy(previousActivationPolicy)
            self.previousActivationPolicy = nil
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { await inspectCookies() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await inspectCookies() }
    }

    private func inspectCookies() async {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        let cookies = await store.allCookies()
        guard let token = cookies.first(where: {
            $0.name == "WorkosCursorSessionToken" && !$0.value.isEmpty
        })?.value else { return }
        onAuthenticated?(token)
        close()
    }
}

extension AuthSessionController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        cleanupWebView()
        window = nil
        restoreActivationPolicy()
    }
}
