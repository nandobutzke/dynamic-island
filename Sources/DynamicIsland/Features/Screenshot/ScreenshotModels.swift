import AppKit
import Foundation

struct ScreenshotItem: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let fileURL: URL
    let contentHash: String

    var image: NSImage? {
        NSImage(contentsOf: fileURL)
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.id == rhs.id
            && lhs.createdAt == rhs.createdAt
            && lhs.fileURL == rhs.fileURL
            && lhs.contentHash == rhs.contentHash
    }
}

enum ScreenshotClipboardLayout {
    static let previewHeight: CGFloat = 54
    static let previewWidth: CGFloat = 96
    static let previewSpacing: CGFloat = 8
    static let maxItems = 3
    static let autoCollapseNanoseconds: UInt64 = 4_000_000_000
    /// Window after ⇧⌘3 (full-screen). Pasteboard/file can lag the key event.
    static let pasteboardArmNanoseconds: UInt64 = 12_000_000_000
    /// Longer window after ⇧⌘4/5 / + (user still picking region/window).
    static let screenshotUIPasteboardArmNanoseconds: UInt64 = 60_000_000_000

    static func expandedWidth(itemCount: Int) -> CGFloat {
        let slots = max(itemCount, 0) + 1
        let row = CGFloat(slots) * previewWidth + CGFloat(max(slots - 1, 0)) * previewSpacing
        return max(280, row + 48)
    }

    static let expandedBaseHeight: CGFloat = 148
}
