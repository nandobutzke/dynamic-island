import AppKit

enum NotchGeometry {
    /// Built-in Liquid Retina display with a hardware notch.
    static var builtInNotchedScreen: NSScreen? {
        let screens = NSScreen.screens
        if let named = screens.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains("built-in")
                && $0.hasNotch
        }) {
            return named
        }
        return screens.first(where: \.hasNotch)
    }

    static func notchDepth(on screen: NSScreen) -> CGFloat {
        max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 32)
    }

    /// How far the shell tucks into the notch band (same for compact + expanded).
    static func notchOverlap(on screen: NSScreen) -> CGFloat {
        // Sit deep in the notch so the closed pill reads as behind the camera housing.
        max(notchDepth(on: screen) - 2, 28)
    }

    /// Content top padding so module icons sit just below the camera housing.
    static func expandedContentTopPadding(on screen: NSScreen? = builtInNotchedScreen) -> CGFloat {
        let overlap = screen.map(notchOverlap(on:)) ?? 28
        // Keep icons closer to the top curve without sitting under the notch glass.
        return max(overlap - 6, 16)
    }

    /// Shared top edge in screen coords — keeps the island glued to the notch while morphing.
    static func anchoredTopY(on screen: NSScreen, expanded: Bool = false) -> CGFloat {
        let frame = screen.frame
        let notch = notchDepth(on: screen)
        let overlap = notchOverlap(on: screen)
        // Tiny drop when open so module icons clear the camera housing.
        let openNudge: CGFloat = expanded ? 5 : 0
        return frame.maxY - notch + overlap - openNudge
    }

    /// Frame for a given size, top-anchored to the notch.
    static func islandFrame(for screen: NSScreen, size: CGSize, expanded: Bool = false) -> NSRect {
        let frame = screen.frame
        let topY = anchoredTopY(on: screen, expanded: expanded)
        let x = frame.midX - size.width / 2
        let y = topY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

extension NSScreen {
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }
}
