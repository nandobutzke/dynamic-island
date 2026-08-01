import AppKit
import SwiftUI

struct ScreenshotClipboardView: View {
    let screenshots: [ScreenshotItem]
    let needsAccessibilityHint: Bool
    let copiedID: UUID?
    let onCopy: (ScreenshotItem) -> Void
    let onDelete: (ScreenshotItem) -> Void
    let onPlus: () -> Void
    let onInteract: () -> Void
    let onRequestAccessibility: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: ScreenshotClipboardLayout.previewSpacing) {
                ForEach(screenshots) { item in
                    ScreenshotPreviewTile(
                        item: item,
                        showCopied: copiedID == item.id,
                        onCopy: {
                            onInteract()
                            onCopy(item)
                        },
                        onDelete: {
                            onInteract()
                            onDelete(item)
                        },
                        onDragStarted: onInteract
                    )
                }

                ScreenshotPlusTile(action: {
                    onInteract()
                    onPlus()
                })
            }

            if needsAccessibilityHint {
                HStack(spacing: 8) {
                    Text("Enable Accessibility for clipboard capture and + shortcut.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open") {
                        onRequestAccessibility()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering in
            if hovering { onInteract() }
        }
    }
}

private struct ScreenshotPreviewTile: View {
    let item: ScreenshotItem
    let showCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onDragStarted: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScreenshotDragSource(
                fileURL: item.fileURL,
                onClick: onCopy,
                onDragStarted: onDragStarted
            ) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black)

                    if let image = item.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    if showCopied {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(
                    width: ScreenshotClipboardLayout.previewWidth,
                    height: ScreenshotClipboardLayout.previewHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { isHovering = $0 }
    }
}

private struct ScreenshotPlusTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
                    .foregroundStyle(Color.white.opacity(0.22))
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(
                width: ScreenshotClipboardLayout.previewWidth,
                height: ScreenshotClipboardLayout.previewHeight
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("New screenshot (⇧⌘5)")
    }
}

/// AppKit drag source that also handles click-to-copy inside a nonactivating panel.
private struct ScreenshotDragSource<Content: View>: NSViewRepresentable {
    let fileURL: URL
    let onClick: () -> Void
    let onDragStarted: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> ScreenshotDragNSView {
        let view = ScreenshotDragNSView(frame: .zero)
        view.onClick = onClick
        view.onDragStarted = onDragStarted
        view.fileURL = fileURL

        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        context.coordinator.hostingView = hosting
        return view
    }

    func updateNSView(_ nsView: ScreenshotDragNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onDragStarted = onDragStarted
        nsView.fileURL = fileURL
        context.coordinator.hostingView?.rootView = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}

private final class ScreenshotDragNSView: NSView, NSDraggingSource {
    var fileURL: URL?
    var onClick: (() -> Void)?
    var onDragStarted: (() -> Void)?

    private var mouseDownPoint: NSPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let fileURL else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        guard distance > 4, !didDrag else { return }
        didDrag = true
        onDragStarted?()

        let writer = ScreenshotPasteboardWriter(fileURL: fileURL)
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage())

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            didDrag = false
        }
        guard !didDrag else { return }
        onClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    private func snapshotImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let context = NSGraphicsContext.current {
            layer?.render(in: context.cgContext)
        }
        image.unlockFocus()
        return image
    }
}

private final class ScreenshotPasteboardWriter: NSObject, NSPasteboardWriting {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .png, .tiff]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            return fileURL.absoluteString
        case .png:
            guard
                let image = NSImage(contentsOf: fileURL),
                let tiff = image.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return nil }
            return png
        case .tiff:
            return NSImage(contentsOf: fileURL)?.tiffRepresentation
        default:
            return nil
        }
    }
}

struct ScreenshotCompactBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(count == 0 ? "Screenshots" : "\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
