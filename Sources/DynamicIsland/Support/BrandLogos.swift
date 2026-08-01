import AppKit
import SwiftUI

enum BrandLogo {
    case cursor
    case spotify
    case screenshot

    private var resourceName: String? {
        switch self {
        case .cursor: "cursor-logo"
        case .spotify: "spotify-logo"
        case .screenshot: nil
        }
    }

    var nsImage: NSImage? {
        guard let resourceName else { return nil }
        if let url = Bundle.module.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // Packaged .app: SPM resource bundle beside the binary.
        if let exeURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("DynamicIsland_DynamicIsland.bundle"),
           let bundle = Bundle(url: exeURL),
           let url = bundle.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // Packaged .app: files copied into Contents/Resources.
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: resourceName)
    }
}

struct BrandLogoImage: View {
    let logo: BrandLogo
    var size: CGFloat = 18
    var selected: Bool = true

    var body: some View {
        Group {
            if let image = logo.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .opacity(selected ? 1 : 0.38)
            } else {
                // Vector fallbacks if assets fail to load.
                switch logo {
                case .spotify:
                    SpotifyMark()
                        .foregroundStyle(selected ? Color(red: 0.11, green: 0.73, blue: 0.33) : .white.opacity(0.38))
                case .cursor:
                    CursorMark()
                        .foregroundStyle(selected ? .white : .white.opacity(0.38))
                case .screenshot:
                    Image(systemName: "camera.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(selected ? .white : .white.opacity(0.38))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Classic Spotify glyph (three arcs) used if the PNG is missing.
private struct SpotifyMark: View {
    var body: some View {
        Canvas { context, size in
            let inset = size.width * 0.06
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            context.fill(Path(ellipseIn: rect), with: .foreground)

            let cx = size.width / 2
            let cy = size.height / 2
            let w = size.width
            let stroke = max(w * 0.08, 1.2)
            for (i, scale) in [0.62, 0.46, 0.30].enumerated() {
                var arc = Path()
                let y = cy - w * (0.02 - CGFloat(i) * 0.015)
                arc.addArc(
                    center: CGPoint(x: cx, y: y + w * 0.18),
                    radius: w * scale,
                    startAngle: .degrees(210),
                    endAngle: .degrees(330),
                    clockwise: false
                )
                context.stroke(
                    arc,
                    with: .color(.black.opacity(0.85)),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
            }
        }
    }
}

/// Simple Cursor-style mark fallback.
private struct CursorMark: View {
    var body: some View {
        Image(systemName: "cursorarrow")
            .resizable()
            .scaledToFit()
    }
}

struct ModuleSwitchButton: View {
    let module: IslandModule
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .matchedGeometryEffect(id: "moduleSelection", in: namespace)
                }

                BrandLogoImage(
                    logo: {
                        switch module {
                        case .cursor: return .cursor
                        case .spotify: return .spotify
                        case .screenshot: return .screenshot
                        }
                    }(),
                    size: 20,
                    selected: isSelected
                )
            }
            .frame(width: 42, height: 36)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(IslandMotion.selection, value: isSelected)
        .help(module.displayName)
    }
}
