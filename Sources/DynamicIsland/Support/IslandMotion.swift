import SwiftUI

enum IslandMotion {
    // MARK: - Springs (shell)

    /// Open — slightly bouncy, grows from the notch.
    static let expand = Animation.spring(response: 0.52, dampingFraction: 0.78, blendDuration: 0.05)

    /// Close — snappier settle back into the notch.
    static let collapse = Animation.spring(response: 0.38, dampingFraction: 0.9, blendDuration: 0.04)

    /// Cursor ↔ Spotify size morph.
    static let moduleSwitch = Animation.spring(response: 0.36, dampingFraction: 0.86, blendDuration: 0.05)

    /// Selected module pill / micro UI.
    static let selection = Animation.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.03)

    /// Pulse alert.
    static let pulse = Animation.spring(response: 0.32, dampingFraction: 0.68, blendDuration: 0.04)

    /// Content fade / artwork.
    static let content = Animation.easeInOut(duration: 0.18)

    /// Content reveal after shell starts opening.
    static let contentReveal = Animation.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.04)

    /// Content hide before shell closes.
    static let contentHide = Animation.easeIn(duration: 0.12)

    // MARK: - AppKit panel springs (match SwiftUI)

    static let expandResponse: CGFloat = 0.52
    static let expandDamping: CGFloat = 0.78
    static let collapseResponse: CGFloat = 0.38
    static let collapseDamping: CGFloat = 0.9
    static let moduleResponse: CGFloat = 0.36
    static let moduleDamping: CGFloat = 0.86

    // Back-compat aliases used in a few places.
    static let morph = expand
    static let panelResponse: CGFloat = expandResponse
    static let panelDamping: CGFloat = expandDamping

    // MARK: - Transitions

    /// Expanded body appears under the top curve after the shell starts growing.
    static var expandTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.97, anchor: .top))
                .combined(with: .offset(y: 6)),
            removal: .opacity
                .combined(with: .scale(scale: 0.98, anchor: .top))
                .combined(with: .offset(y: 4))
        )
    }

    /// Compact badge dissolves as the shell takes over.
    static var compactTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .center))
        )
    }

    /// Directional swap between Cursor and Spotify.
    static func moduleTransition(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: forward ? .trailing : .leading))
                .combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity
                .combined(with: .move(edge: forward ? .leading : .trailing))
                .combined(with: .scale(scale: 0.97, anchor: .top))
        )
    }
}
