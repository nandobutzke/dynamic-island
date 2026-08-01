import AppKit
import SwiftUI

@main
struct DynamicIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store: IslandStore
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    init() {
        _store = ObservedObject(wrappedValue: IslandBootstrap.shared.store)
    }

    var body: some Scene {
        MenuBarExtra("Dynamic Island", systemImage: "pill.fill") {
            if store.isSignedIn {
                Button("Refresh usage") {
                    Task { await store.refreshUsage() }
                }
                Button("Sign out of Cursor") {
                    store.signOut()
                }
            } else {
                Button("Sign in to Cursor…") {
                    store.signIn()
                }
            }

            if store.needsAccessibilityHint {
                Button("Enable Accessibility for Screenshots…") {
                    store.requestAccessibilityPermission()
                }
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { newValue in
                    if LaunchAtLogin.setEnabled(newValue) {
                        launchAtLoginEnabled = newValue
                    } else {
                        launchAtLoginEnabled = LaunchAtLogin.isEnabled
                    }
                }
            ))

            Divider()

            Button("Quit Dynamic Island") {
                store.stop()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

@MainActor
enum IslandBootstrap {
    static let shared = IslandRuntime()
}

@MainActor
final class IslandRuntime {
    let store = IslandStore()
    private var panel: IslandPanelController?
    private var started = false

    func startIfNeeded() {
        guard !started else { return }
        started = true
        store.start()
        let controller = IslandPanelController(store: store)
        panel = controller
        controller.show()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        IslandBootstrap.shared.startIfNeeded()
    }
}
