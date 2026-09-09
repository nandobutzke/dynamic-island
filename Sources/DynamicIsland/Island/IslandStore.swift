import AppKit
import Foundation
import SwiftUI

enum IslandModule: String, CaseIterable, Identifiable {
    case cursor
    case spotify
    case screenshot
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .spotify: return "Spotify"
        case .screenshot: return "Screenshots"
        case .system: return "System"
        }
    }
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
    @Published var screenshots: [ScreenshotItem] = []
    @Published var needsAccessibilityHint = false
    @Published var copiedScreenshotID: UUID?
    @Published var systemStats = MacSystemSnapshot.placeholder
    @Published var presentedNudge: Nudge?

    private let cursorService = CursorUsageService()
    private let spotifyService = SpotifyService()
    private let screenshotService = ScreenshotClipboardService()
    private let systemService = MacSystemService()
    private var usageTimer: Timer?
    private var spotifyTimer: Timer?
    private var systemTimer: Timer?
    private var alertedThresholds: Set<String> = []
    private var pulseResetTask: Task<Void, Never>?
    private var phaseTask: Task<Void, Never>?
    private var screenshotAutoCollapseTask: Task<Void, Never>?
    private var copiedFeedbackTask: Task<Void, Never>?
    private var nudgeCollapseTask: Task<Void, Never>?
    private let calendarProvider = CalendarNudgeProvider()
    private let teamsProvider = TeamsNudgeProvider()
    private let lifestyleProvider = LifestyleNudgeProvider()
    private var screenshotPresentationIsTemporary = false
    /// True only after explicit module-switcher selection (survives collapse → compact badge).
    private var screenshotPinnedByUser = false
    private var moduleBeforeScreenshot: IslandModule?

    /// Automatic context: Spotify while playing, otherwise Cursor.
    /// Screenshot is never automatic — only via capture overlay or manual pin.
    var activeModule: IslandModule {
        if let overrideModule, overrideModule == .screenshot {
            return .screenshot
        }
        if spotify.isRunning && spotify.isPlaying {
            return .spotify
        }
        return .cursor
    }

    /// Module shown in the current presentation (honors manual/pinned override).
    var displayedModule: IslandModule {
        overrideModule ?? activeModule
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

        screenshotService.onScreenshotsChanged = { [weak self] items in
            guard let self else { return }
            withAnimation(IslandMotion.content) {
                self.screenshots = items
            }
        }
        screenshotService.onNewScreenshot = { [weak self] in
            self?.presentScreenshotCapture()
        }
        screenshotService.onAccessibilityStatusChanged = { [weak self] trusted in
            self?.needsAccessibilityHint = !trusted
        }
        screenshotService.start()
        screenshots = screenshotService.items
        needsAccessibilityHint = !screenshotService.isAccessibilityTrusted

        Task { await refreshUsage() }
        refreshSpotify()
        refreshSystemStats()
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
        systemTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSystemStats()
            }
        }
        if let usageTimer { RunLoop.main.add(usageTimer, forMode: .common) }
        if let spotifyTimer { RunLoop.main.add(spotifyTimer, forMode: .common) }
        if let systemTimer { RunLoop.main.add(systemTimer, forMode: .common) }

        NudgeScheduler.shared.register(calendarProvider)
        NudgeScheduler.shared.register(teamsProvider)
        NudgeScheduler.shared.register(lifestyleProvider)
        NudgeScheduler.shared.onPresent = { [weak self] nudge in
            self?.presentNudge(nudge)
        }
        NudgeScheduler.shared.start()
        Task { _ = await CalendarEventKitHelper.shared.requestAccess() }
    }

    func stop() {
        usageTimer?.invalidate()
        spotifyTimer?.invalidate()
        systemTimer?.invalidate()
        usageTimer = nil
        spotifyTimer = nil
        systemTimer = nil
        screenshotService.stop()
        NudgeScheduler.shared.stop()
        screenshotAutoCollapseTask?.cancel()
        copiedFeedbackTask?.cancel()
        nudgeCollapseTask?.cancel()
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
        screenshotAutoCollapseTask?.cancel()
        screenshotAutoCollapseTask = nil
        presentedNudge = nil
        if isPulsing {
            withAnimation(IslandMotion.pulse) { isPulsing = false }
        }

        let keepScreenshotPin = screenshotPinnedByUser && overrideModule == .screenshot
        screenshotPresentationIsTemporary = false
        moduleBeforeScreenshot = nil

        // 1) Hide content quickly so the shell can shrink cleanly.
        withAnimation(IslandMotion.contentHide) {
            contentRevealed = false
        }
        phaseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(IslandMotion.collapse) {
                presentation = .compact
                if keepScreenshotPin {
                    overrideModule = .screenshot
                } else {
                    overrideModule = nil
                    screenshotPinnedByUser = false
                }
            }
        }
    }

    func expand() {
        guard presentation == .compact else { return }
        phaseTask?.cancel()
        // 1) Grow the shell from the notch…
        withAnimation(IslandMotion.expand) {
            presentation = .expanded
            overrideModule = overrideModule ?? activeModule
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

    func presentNudge(_ nudge: Nudge) {
        if overrideModule == .screenshot { return }
        if presentation == .expanded && presentedNudge == nil && nudge.priority < .high {
            return
        }

        nudgeCollapseTask?.cancel()
        withAnimation(IslandMotion.pulse) {
            presentedNudge = nudge
            isPulsing = true
        }
        if presentation == .compact {
            expand()
        } else {
            withAnimation(IslandMotion.contentReveal) {
                contentRevealed = true
            }
        }

        nudgeCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(NudgeSchedule.displayDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard presentedNudge?.id == nudge.id else { return }
            collapse()
        }
    }

    func requestCalendarAccess() {
        Task { _ = await CalendarEventKitHelper.shared.requestAccess() }
    }

    func selectModule(_ module: IslandModule) {
        presentedNudge = nil
        nudgeCollapseTask?.cancel()
        let current = displayedModule
        guard module != current || presentation == .compact else { return }
        let forward = moduleIndex(module) > moduleIndex(current)
        moduleSwitchForward = forward

        if module == .screenshot {
            screenshotPresentationIsTemporary = false
            screenshotPinnedByUser = true
            screenshotAutoCollapseTask?.cancel()
            screenshotAutoCollapseTask = nil
            moduleBeforeScreenshot = nil
        } else {
            screenshotPresentationIsTemporary = false
            screenshotPinnedByUser = false
            screenshotAutoCollapseTask?.cancel()
            screenshotAutoCollapseTask = nil
        }

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
        case .screenshot: return 2
        case .system: return 3
        }
    }

    // MARK: - Screenshot clipboard

    func presentScreenshotCapture() {
        // Already manually viewing screenshots — refresh only, no auto-collapse.
        if overrideModule == .screenshot && presentation == .expanded && !screenshotPresentationIsTemporary {
            return
        }

        if !screenshotPresentationIsTemporary {
            if presentation == .expanded,
               let current = overrideModule,
               current != .screenshot {
                moduleBeforeScreenshot = current
            } else if spotify.isRunning && spotify.isPlaying {
                moduleBeforeScreenshot = .spotify
            } else {
                moduleBeforeScreenshot = .cursor
            }
        }

        screenshotPresentationIsTemporary = true
        let forward = moduleIndex(.screenshot) > moduleIndex(displayedModule)
        moduleSwitchForward = forward

        phaseTask?.cancel()
        withAnimation(IslandMotion.moduleSwitch) {
            overrideModule = .screenshot
            presentation = .expanded
            contentRevealed = true
        }
        startScreenshotAutoCollapse()
    }

    func noteScreenshotInteraction() {
        // Cancel auto-collapse; stay expanded until outside click / + / module switch.
        // Do not pin to compact unless the user chose Screenshots in the switcher.
        screenshotAutoCollapseTask?.cancel()
        screenshotAutoCollapseTask = nil
        screenshotPresentationIsTemporary = false
        moduleBeforeScreenshot = nil
    }

    func copyScreenshot(_ item: ScreenshotItem) {
        guard screenshotService.copyToPasteboard(item) else { return }
        copiedScreenshotID = item.id
        copiedFeedbackTask?.cancel()
        copiedFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            if copiedScreenshotID == item.id {
                copiedScreenshotID = nil
            }
        }
    }

    func deleteScreenshot(_ item: ScreenshotItem) {
        screenshotService.remove(item)
    }

    func captureNewScreenshot() {
        screenshotAutoCollapseTask?.cancel()
        screenshotAutoCollapseTask = nil
        screenshotPresentationIsTemporary = false
        screenshotPinnedByUser = false
        moduleBeforeScreenshot = nil

        // Collapse first so the system UI isn't covered.
        if presentation == .expanded {
            phaseTask?.cancel()
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
                try? await Task.sleep(nanoseconds: 120_000_000)
                let ok = screenshotService.postScreenshotUIShortcut()
                needsAccessibilityHint = !ok || !screenshotService.isAccessibilityTrusted
                if !ok {
                    screenshotService.armPasteboardWindow(
                        durationNanoseconds: ScreenshotClipboardLayout.screenshotUIPasteboardArmNanoseconds
                    )
                    screenshotService.promptAccessibilityPermission()
                }
            }
        } else {
            let ok = screenshotService.postScreenshotUIShortcut()
            needsAccessibilityHint = !ok || !screenshotService.isAccessibilityTrusted
            if !ok {
                screenshotService.armPasteboardWindow(
                    durationNanoseconds: ScreenshotClipboardLayout.screenshotUIPasteboardArmNanoseconds
                )
                screenshotService.promptAccessibilityPermission()
            }
        }
    }

    func requestAccessibilityPermission() {
        screenshotService.promptAccessibilityPermission()
        needsAccessibilityHint = !screenshotService.isAccessibilityTrusted
    }

    private func startScreenshotAutoCollapse() {
        screenshotAutoCollapseTask?.cancel()
        screenshotAutoCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ScreenshotClipboardLayout.autoCollapseNanoseconds)
            guard !Task.isCancelled else { return }
            guard screenshotPresentationIsTemporary else { return }
            screenshotPresentationIsTemporary = false
            moduleBeforeScreenshot = nil
            collapse()
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

    func refreshSystemStats() {
        let snapshot = systemService.snapshot()
        withAnimation(IslandMotion.content) {
            systemStats = snapshot
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
        // Clear manual override when music starts so compact auto-switches —
        // but keep a pinned screenshot module.
        if !previousPlaying && spotify.isPlaying && presentation == .compact,
           overrideModule != .screenshot {
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
        // Don't interrupt an active screenshot session or a nudge overlay.
        if overrideModule == .screenshot { return }
        if presentedNudge != nil { return }

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
