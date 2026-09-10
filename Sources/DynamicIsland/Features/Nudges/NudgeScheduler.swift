import Foundation

@MainActor
final class NudgeScheduler {
    static let shared = NudgeScheduler()

    var onPresent: ((Nudge) -> Void)?

    private var providers: [NudgeProvider] = []
    private var timer: Timer?
    private var lastPresentedID: String?
    private var lastPresentedAt: [String: Date] = [:]
    private var rotateIndex = 0

    func register(_ provider: NudgeProvider) {
        if providers.contains(where: { $0.source == provider.source }) { return }
        providers.append(provider)
    }

    func start() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: NudgeSchedule.popInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        var candidates: [Nudge] = []
        for provider in providers {
            let nudges = await provider.currentNudges()
            candidates.append(contentsOf: nudges)
        }

        let now = Date()
        candidates = candidates.filter { nudge in
            if let last = lastPresentedAt[nudge.id],
               now.timeIntervalSince(last) < NudgeSchedule.sameNudgeCooldown {
                return false
            }
            return true
        }

        guard let picked = pickHighestRotating(from: candidates) else { return }
        lastPresentedID = picked.id
        lastPresentedAt[picked.id] = now
        providers.first(where: { $0.source == picked.source })?.didPresent(picked)
        onPresent?(picked)
    }

    private func pickHighestRotating(from nudges: [Nudge]) -> Nudge? {
        guard !nudges.isEmpty else { return nil }
        let maxPriority = nudges.map(\.priority).max() ?? .low
        var band = nudges.filter { $0.priority == maxPriority }
        band.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id < rhs.id
        }
        if band.count > 1, let last = lastPresentedID,
           let idx = band.firstIndex(where: { $0.id == last }) {
            let next = band[(idx + 1) % band.count]
            return next
        }
        if rotateIndex >= band.count { rotateIndex = 0 }
        let picked = band[rotateIndex]
        rotateIndex = (rotateIndex + 1) % max(band.count, 1)
        return picked
    }
}
