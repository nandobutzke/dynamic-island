import AppKit
import Foundation
import SwiftUI

enum IslandModule: String, CaseIterable, Identifiable {
    case cursor
    case spotify

    var id: String { rawValue }

}

enum IslandPresentation: Equatable {
    case compact
    case expanded
}

@MainActor
final class IslandStore: ObservableObject {
    @Published var presentation: IslandPresentation = .compact
    @Published var overrideModule: IslandModule?
    /// Drives staggered content fade on open/close (shell morphs first / last).
    @Published var contentRevealed = false
    /// Used for directional Cursor ↔ Spotify transitions.
    @Published var moduleSwitchForward = true
    @Published var usage: CursorUsageSnapshot?
    @Published var isSignedIn = false
    @Published var usageError: String?
    @Published var spotify = SpotifyNowPlaying.inactive
    @Published var spotifyError: String?
    @Published var isPulsing = false
    @Published var isRefreshingUsage = false

    private let cursorService = CursorUsageService()
    private let spotifyService = SpotifyService()
    private var usageTimer: Timer?
    private var spotifyTimer: Timer?
    private var alertedThresholds: Set<String> = []
    private var pulseResetTask: Task<Void, Never>?
    private var phaseTask: Task<Void, Never>?

    /// Automatic context: Spotify while playing, otherwise Cursor.
    var activeModule: IslandModule {
        if spotify.isRunning && spotify.isPlaying {
            return .spotify
        }
        return .cursor
    }

    /// Module shown in the current presentation (honors manual switch when expanded).
    var displayedModule: IslandModule {
        if presentation == .expanded {
            return overrideModule ?? activeModule
        }
        return activeModule
    }

    func start() {
        isSignedIn = KeychainStore.loadSessionToken() != nil
        AuthSessionController.shared.onAuthenticated = { [weak self] token in
            Task { @MainActor in
                self?.handleAuthenticated(token: token)
            }
        }
        spotifyService.onArtworkUpdated = { [weak self] image in
            guard let self else { return }
            withAnimation(IslandMotion.content) {
                var updated = self.spotify
                updated.artwork = image
                self.spotify = updated
            }
        }
        Task { await refreshUsage() }
        refreshSpotify()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshUsage()
            }
        }
        spotifyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSpotify()
            }
        }
        if let usageTimer { RunLoop.main.add(usageTimer, forMode: .common) }
        if let spotifyTimer { RunLoop.main.add(spotifyTimer, forMode: .common) }
    }

    func stop() {
        usageTimer?.invalidate()
        spotifyTimer?.invalidate()
        usageTimer = nil
        spotifyTimer = nil
    }

    func toggleExpanded() {
        if presentation == .expanded {
            collapse()
        } else {
            expand()
        }
    }

    func collapse() {
        guard presentation == .expanded else { return }
        phaseTask?.cancel()
        // 1) Hide content quickly so the shell can shrink cleanly.
        withAnimation(IslandMotion.contentHide) {
            contentRevealed = false
        }
        phaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(IslandMotion.collapse) {
                presentation = .compact
                overrideModule = nil
            }
        }
    }

    func expand() {
        guard presentation == .compact else { return }
        phaseTask?.cancel()
        // 1) Grow the shell from the notch…
        withAnimation(IslandMotion.expand) {
            presentation = .expanded
            overrideModule = activeModule
            contentRevealed = false
        }
        // 2) …then reveal content once the morph has started.
        phaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(IslandMotion.contentReveal) {
                contentRevealed = true
            }
        }
    }

    func selectModule(_ module: IslandModule) {
        let current = displayedModule
        guard module != current || presentation == .compact else { return }
        let forward = moduleIndex(module) > moduleIndex(current)
        moduleSwitchForward = forward
        withAnimation(IslandMotion.moduleSwitch) {
            overrideModule = module
            presentation = .expanded
            contentRevealed = true
        }
    }

    private func moduleIndex(_ module: IslandModule) -> Int {
        switch module {
        case .cursor: return 0
        case .spotify: return 1
        }
    }

    func signIn() {
        NSApp.activate(ignoringOtherApps: true)
        AuthSessionController.shared.presentLogin()
    }

    func signOut() {
        KeychainStore.clearSessionToken()
        isSignedIn = false
        usage = nil
        usageError = "Sign in to see Cursor usage."
    }

    func handleAuthenticated(token: String) {
        do {
            try KeychainStore.saveSessionToken(token)
            isSignedIn = true
            usageError = nil
            Task { await refreshUsage() }
        } catch {
            usageError = "Could not save session."
        }
    }

    func refreshUsage() async {
        guard let token = KeychainStore.loadSessionToken() else {
            isSignedIn = false
            usageError = "Sign in to see Cursor usage."
            return
        }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }
        do {
            let previous = usage
            let snapshot = try await cursorService.fetchUsage(sessionToken: token)
            usage = snapshot
            isSignedIn = true
            usageError = nil
            evaluateAlerts(previous: previous, current: snapshot)
        } catch CursorUsageError.unauthorized {
            KeychainStore.clearSessionToken()
            isSignedIn = false
            usage = nil
            usageError = CursorUsageError.unauthorized.localizedDescription
        } catch {
            usageError = error.localizedDescription
        }
    }

    func refreshSpotify() {
        let previousPlaying = spotify.isPlaying
        let previousTitle = spotify.title
        let snapshot = spotifyService.refresh()
        // Preserve in-flight artwork if track didn't change and new snapshot has none yet.
        var next = snapshot
        if next.title == previousTitle, next.artwork == nil, let existing = spotify.artwork {
            next.artwork = existing
        }
        withAnimation(IslandMotion.content) {
            spotify = next
            spotifyError = spotifyService.lastError
        }
        // Clear manual override when music starts so compact auto-switches.
        if !previousPlaying && spotify.isPlaying && presentation == .compact {
            withAnimation(IslandMotion.moduleSwitch) {
                overrideModule = nil
            }
        }
    }

    func spotifyPlayPause() { spotifyService.playPause(); refreshSpotify() }
    func spotifyNext() { spotifyService.nextTrack(); refreshSpotify() }
    func spotifyPrevious() { spotifyService.previousTrack(); refreshSpotify() }

    private func evaluateAlerts(previous: CursorUsageSnapshot?, current: CursorUsageSnapshot) {
        let cycleKey = current.billingCycleEnd.map { String(Int($0.timeIntervalSince1970)) } ?? "cycle"
        checkThreshold(pool: "cursor", percent: current.cursorModelsPercent, previous: previous?.cursorModelsPercent, cycleKey: cycleKey)
        checkThreshold(pool: "other", percent: current.otherModelsPercent, previous: previous?.otherModelsPercent, cycleKey: cycleKey)
    }

    private func checkThreshold(pool: String, percent: Double, previous: Double?, cycleKey: String) {
        for threshold in [90.0, 100.0] {
            let key = "\(cycleKey)-\(pool)-\(Int(threshold))"
            let crossed = percent >= threshold && (previous == nil || (previous ?? 0) < threshold)
            if crossed && !alertedThresholds.contains(key) {
                alertedThresholds.insert(key)
                triggerPulse()
            }
        }
    }

    private func triggerPulse() {
        phaseTask?.cancel()
        withAnimation(IslandMotion.pulse) {
            isPulsing = true
            presentation = .expanded
            overrideModule = .cursor
            contentRevealed = true
        }
        pulseResetTask?.cancel()
        pulseResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.collapse()
                withAnimation(IslandMotion.pulse) {
                    self.isPulsing = false
                }
            }
        }
    }
}
