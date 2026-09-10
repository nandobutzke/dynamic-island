import Foundation

enum NudgeSource: String, Sendable {
    case teams
    case calendar
    case lifestyle
}

enum NudgePriority: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case urgent = 3

    static func < (lhs: NudgePriority, rhs: NudgePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Nudge: Identifiable, Equatable, Sendable {
    let id: String
    let source: NudgeSource
    /// Calendar / lifestyle use emoji. Teams leaves this empty and uses `BrandLogo.teams`.
    let emoji: String
    let title: String
    let description: String
    let priority: NudgePriority
    let createdAt: Date
}

@MainActor
protocol NudgeProvider: AnyObject {
    var source: NudgeSource { get }
    func currentNudges() async -> [Nudge]
    func didPresent(_ nudge: Nudge)
}

extension NudgeProvider {
    func didPresent(_ nudge: Nudge) {}
}

enum NudgeSchedule {
    /// Island collect/pop interval. Tests: `5`. Production: `15 * 60`.
    static let popInterval: TimeInterval = 15 * 60
    static let displayDuration: TimeInterval = 8
    static let sameNudgeCooldown: TimeInterval = 90
}
