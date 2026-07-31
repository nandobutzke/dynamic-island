import SwiftUI

struct SpotifyPlayerView: View {
    let nowPlaying: SpotifyNowPlaying
    let error: String?
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                artworkView(size: 64, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(nowPlaying.title.isEmpty ? "Not playing" : nowPlaying.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .animation(IslandMotion.content, value: nowPlaying.title)
                    Text(nowPlaying.artist.isEmpty ? (nowPlaying.isRunning ? "Spotify" : "Spotify isn’t running") : nowPlaying.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .animation(IslandMotion.content, value: nowPlaying.artist)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 28) {
                Spacer()
                controlButton(systemName: "backward.fill", action: onPrevious)
                controlButton(
                    systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                    size: 18,
                    action: onPlayPause
                )
                controlButton(systemName: "forward.fill", action: onNext)
                Spacer()
            }
            .padding(.top, 4)
            .padding(.bottom, 6)

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func artworkView(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let image = nowPlaying.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(IslandMotion.content, value: nowPlaying.artwork != nil)
        .animation(IslandMotion.content, value: nowPlaying.title)
    }

    private func controlButton(systemName: String, size: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

struct SpotifyCompactBadge: View {
    let nowPlaying: SpotifyNowPlaying

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                if let image = nowPlaying.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .animation(IslandMotion.content, value: nowPlaying.artwork != nil)

            Text(nowPlaying.title.isEmpty ? "Spotify" : nowPlaying.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .animation(IslandMotion.content, value: nowPlaying.title)
        }
    }
}
