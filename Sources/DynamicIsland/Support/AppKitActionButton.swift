import AppKit
import SwiftUI

/// Reliable AppKit button for use inside a nonactivating NSPanel (SwiftUI Button often drops clicks).
struct AppKitActionButton: NSViewRepresentable {
    let title: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.clicked))
        button.bezelStyle = .flexiblePush
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        button.layer?.cornerRadius = 10
        button.layer?.masksToBounds = true
        button.focusRingType = .none
        button.setButtonType(.momentaryLight)
        applyTitle(to: button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        applyTitle(to: button)
        context.coordinator.action = action
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked)
    }

    private func applyTitle(to button: NSButton) {
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ]
        )
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked() {
            action()
        }
    }
}
