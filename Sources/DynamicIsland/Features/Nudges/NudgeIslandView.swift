import AppKit
import SwiftUI

/// Leading mark for a nudge: Teams uses `BrandLogo.teams`; calendar/lifestyle use emoji.
struct NudgeLeadingGlyph: View {
    let nudge: Nudge
    var image: NSImage? = nil
    var pointSize: CGFloat = 28
    var columnWidth: CGFloat? = 36

    var body: some View {
        Group {
            if nudge.source == .teams {
                BrandLogoImage(logo: .teams, size: pointSize, selected: true)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Text(nudge.emoji)
                    .font(.system(size: pointSize))
            }
        }
        .frame(width: columnWidth ?? pointSize, height: pointSize)
    }
}

struct NudgeIslandView: View {
    let nudge: Nudge
    var leadingImage: NSImage? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NudgeLeadingGlyph(nudge: nudge, image: leadingImage, pointSize: 28, columnWidth: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(nudge.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                Text(nudge.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct NudgeCompactBadge: View {
    let nudge: Nudge
    var leadingImage: NSImage? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            NudgeLeadingGlyph(nudge: nudge, image: leadingImage, pointSize: 14, columnWidth: 18)
            Text(nudge.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

enum NudgeIslandLayout {
    static let expandedSize = CGSize(width: 348, height: 124)
    /// Match module-expanded island corners (`34`).
    static let expandedCornerRadius: CGFloat = 34
}
