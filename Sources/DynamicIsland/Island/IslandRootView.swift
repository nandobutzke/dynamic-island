import SwiftUI

struct IslandRootView: View {
    @ObservedObject var store: IslandStore
    @Namespace private var moduleNamespace

    private var compactSize: CGSize { CGSize(width: 172, height: 36) }
    private var expandedSize: CGSize {
        switch store.displayedModule {
        case .cursor: return CGSize(width: 380, height: store.usage == nil ? 176 : 288)
        case .spotify: return CGSize(width: 340, height: store.spotifyError == nil ? 196 : 224)
        case .screenshot:
            let extra: CGFloat = store.needsAccessibilityHint ? 28 : 0
            return CGSize(
                width: ScreenshotClipboardLayout.expandedWidth(itemCount: store.screenshots.count),
                height: ScreenshotClipboardLayout.expandedBaseHeight + extra
            )
        case .system: return CGSize(width: 380, height: 196)
        }
    }

    private var expandedContentTopPadding: CGFloat {
        NotchGeometry.expandedContentTopPadding()
    }

    private var expandedShellHeight: CGFloat {
        switch store.displayedModule {
        case .cursor: return (store.usage == nil ? 176 : 288) + expandedContentTopPadding - 12
        case .spotify: return (store.spotifyError == nil ? 196 : 224) + expandedContentTopPadding - 12
        case .screenshot:
            let extra: CGFloat = store.needsAccessibilityHint ? 28 : 0
            return ScreenshotClipboardLayout.expandedBaseHeight + extra + expandedContentTopPadding - 12
        case .system: return 196 + expandedContentTopPadding - 12
        }
    }

    private var size: CGSize {
        store.presentation == .expanded
            ? CGSize(width: expandedSize.width, height: expandedShellHeight)
            : compactSize
    }

    /// Clamp to half-height so the top stays pill-round while height is still growing.
    private func cornerRadius(for height: CGFloat) -> CGFloat {
        let target: CGFloat = store.presentation == .expanded ? 34 : 18
        return min(target, height / 2)
    }

    var body: some View {
        let radius = cornerRadius(for: size.height)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)

            if store.presentation == .expanded {
                ExpandedIslandView(store: store, namespace: moduleNamespace)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .padding(.top, expandedContentTopPadding)
                    .opacity(store.contentRevealed ? 1 : 0)
                    .offset(y: store.contentRevealed ? 0 : 8)
                    .scaleEffect(store.contentRevealed ? 1 : 0.985, anchor: .top)
                    .transition(IslandMotion.expandTransition)
            } else {
                CompactIslandView(store: store)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
                    .contentShape(shape)
                    .onTapGesture {
                        store.expand()
                    }
                    .transition(IslandMotion.compactTransition)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .scaleEffect(store.isPulsing ? 1.03 : 1, anchor: .top)
        .animation(IslandMotion.expand, value: store.presentation == .expanded)
        .animation(IslandMotion.moduleSwitch, value: store.displayedModule)
        .animation(IslandMotion.contentReveal, value: store.contentRevealed)
        .animation(IslandMotion.pulse, value: store.isPulsing)
        .animation(store.presentation == .expanded ? IslandMotion.expand : IslandMotion.collapse, value: size.width)
        .animation(store.presentation == .expanded ? IslandMotion.expand : IslandMotion.collapse, value: size.height)
        .animation(IslandMotion.expand, value: radius)
    }
}

struct CompactIslandView: View {
    @ObservedObject var store: IslandStore

    var body: some View {
        Group {
            switch store.activeModule {
            case .spotify:
                SpotifyCompactBadge(nowPlaying: store.spotify)
                    .transition(IslandMotion.moduleTransition(forward: true))
            case .cursor:
                CursorCompactBadge(percent: store.usage.map(\.worstPercent))
                    .transition(IslandMotion.moduleTransition(forward: false))
            case .screenshot:
                ScreenshotCompactBadge(count: store.screenshots.count)
                    .transition(IslandMotion.moduleTransition(forward: true))
            case .system:
                MacSystemCompactBadge(snapshot: store.systemStats)
                    .transition(IslandMotion.moduleTransition(forward: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(IslandMotion.moduleSwitch, value: store.activeModule)
    }
}

struct ExpandedIslandView: View {
    @ObservedObject var store: IslandStore
    var namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(IslandModule.allCases) { module in
                    ModuleSwitchButton(
                        module: module,
                        isSelected: store.displayedModule == module,
                        namespace: namespace
                    ) {
                        store.selectModule(module)
                    }
                }
                Spacer(minLength: 0)
            }

            ZStack(alignment: .topLeading) {
                switch store.displayedModule {
                case .cursor:
                    CursorUsageView(
                        usage: store.usage,
                        error: store.usageError,
                        isSignedIn: store.isSignedIn,
                        onSignIn: { store.signIn() }
                    )
                    .transition(IslandMotion.moduleTransition(forward: store.moduleSwitchForward))
                case .spotify:
                    SpotifyPlayerView(
                        nowPlaying: store.spotify,
                        error: store.spotifyError,
                        onPrevious: store.spotifyPrevious,
                        onPlayPause: store.spotifyPlayPause,
                        onNext: store.spotifyNext
                    )
                    .transition(IslandMotion.moduleTransition(forward: store.moduleSwitchForward))
                case .screenshot:
                    ScreenshotClipboardView(
                        screenshots: store.screenshots,
                        needsAccessibilityHint: store.needsAccessibilityHint,
                        copiedID: store.copiedScreenshotID,
                        onCopy: store.copyScreenshot,
                        onDelete: store.deleteScreenshot,
                        onPlus: store.captureNewScreenshot,
                        onInteract: store.noteScreenshotInteraction,
                        onRequestAccessibility: store.requestAccessibilityPermission
                    )
                    .transition(IslandMotion.moduleTransition(forward: store.moduleSwitchForward))
                case .system:
                    MacSystemView(snapshot: store.systemStats)
                    .transition(IslandMotion.moduleTransition(forward: store.moduleSwitchForward))
                }
            }
            .clipped()
            .animation(IslandMotion.moduleSwitch, value: store.displayedModule)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
