import AppKit
import Foundation

struct SpotifyNowPlaying: Equatable {
    var isRunning: Bool
    var isPlaying: Bool
    var title: String
    var artist: String
    var artworkURL: URL?
    var artwork: NSImage?

    static let inactive = SpotifyNowPlaying(
        isRunning: false,
        isPlaying: false,
        title: "",
        artist: "",
        artworkURL: nil,
        artwork: nil
    )

    static func == (lhs: SpotifyNowPlaying, rhs: SpotifyNowPlaying) -> Bool {
        lhs.isRunning == rhs.isRunning
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.artworkURL == rhs.artworkURL
            && (lhs.artwork != nil) == (rhs.artwork != nil)
    }
}

@MainActor
final class SpotifyService {
    private var lastTrackKey: String?
    private var cachedArtwork: NSImage?
    private var cachedArtworkURL: URL?
    private var artworkTask: Task<Void, Never>?

    var lastError: String?
    /// Called when artwork finishes downloading for the current track.
    var onArtworkUpdated: ((NSImage?) -> Void)?

    func refresh() -> SpotifyNowPlaying {
        guard isSpotifyRunning() else {
            resetArtworkCache()
            lastError = nil
            return .inactive
        }

        do {
            let state = try runAppleScript("""
            tell application "Spotify"
              if player state is playing then
                return "playing"
              else if player state is paused then
                return "paused"
              else
                return "stopped"
              end if
            end tell
            """)
            let isPlaying = state == "playing"
            let isActive = state == "playing" || state == "paused"

            guard isActive else {
                resetArtworkCache()
                return SpotifyNowPlaying(
                    isRunning: true,
                    isPlaying: false,
                    title: "",
                    artist: "",
                    artworkURL: nil,
                    artwork: nil
                )
            }

            let title = (try? runAppleScript("""
            tell application "Spotify" to return name of current track
            """)) ?? ""
            let artist = (try? runAppleScript("""
            tell application "Spotify" to return artist of current track
            """)) ?? ""
            let trackKey = "\(title)|\(artist)"

            var artworkURL = cachedArtworkURL
            var artwork = cachedArtwork

            if trackKey != lastTrackKey {
                lastTrackKey = trackKey
                cachedArtwork = nil
                cachedArtworkURL = nil
                artwork = nil
                artworkURL = fetchArtworkURL()
                cachedArtworkURL = artworkURL

                if let artworkURL {
                    loadArtwork(from: artworkURL, trackKey: trackKey)
                } else if let raw = fetchArtworkData() {
                    artwork = NSImage(data: raw)
                    cachedArtwork = artwork
                }
            }

            lastError = nil
            return SpotifyNowPlaying(
                isRunning: true,
                isPlaying: isPlaying,
                title: title,
                artist: artist,
                artworkURL: artworkURL,
                artwork: artwork
            )
        } catch {
            lastError = automationHint(for: error)
            return SpotifyNowPlaying(
                isRunning: true,
                isPlaying: false,
                title: "",
                artist: "",
                artworkURL: nil,
                artwork: nil
            )
        }
    }

    func playPause() {
        _ = try? runAppleScript("tell application \"Spotify\" to playpause")
    }

    func nextTrack() {
        _ = try? runAppleScript("tell application \"Spotify\" to next track")
    }

    func previousTrack() {
        _ = try? runAppleScript("tell application \"Spotify\" to previous track")
    }

    private func resetArtworkCache() {
        artworkTask?.cancel()
        lastTrackKey = nil
        cachedArtwork = nil
        cachedArtworkURL = nil
    }

    private func isSpotifyRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
    }

    /// Preferred: Spotify exposes a CDN URL for cover art.
    private func fetchArtworkURL() -> URL? {
        let raw = try? runAppleScript("""
        tell application "Spotify"
          try
            return artwork url of current track as text
          on error
            return ""
          end try
        end tell
        """)
        guard let raw, !raw.isEmpty, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return url
    }

    /// Fallback: raw image bytes from AppleEvent descriptor.
    private func fetchArtworkData() -> Data? {
        let source = """
        tell application "Spotify" to return artwork of current track
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }

        let data = result.data
        if !data.isEmpty {
            return data
        }

        // Some Spotify builds return a list of byte integers.
        if result.numberOfItems > 0 {
            var bytes = [UInt8]()
            bytes.reserveCapacity(result.numberOfItems)
            for index in 1...result.numberOfItems {
                if let item = result.atIndex(index) {
                    bytes.append(UInt8(clamping: item.int32Value))
                }
            }
            if !bytes.isEmpty {
                return Data(bytes)
            }
        }
        return nil
    }

    private func loadArtwork(from url: URL, trackKey: String) {
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let image = NSImage(data: data) else { return }
                await MainActor.run {
                    guard let self, self.lastTrackKey == trackKey else { return }
                    self.cachedArtwork = image
                    self.onArtworkUpdated?(image)
                }
            } catch {
                // Keep placeholder; no hard error for artwork.
            }
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SpotifyError.scriptFailed("Could not create AppleScript.")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String
                ?? "AppleScript error"
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            throw SpotifyError.scriptFailed("\(message) (\(number))")
        }
        return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func automationHint(for error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not allowed") {
            return "Allow Automation for Spotify in System Settings → Privacy & Security → Automation."
        }
        return text
    }
}

enum SpotifyError: LocalizedError {
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): return message
        }
    }
}
