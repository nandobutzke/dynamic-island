import Foundation
import SwiftUI

struct CursorUsageSnapshot: Equatable {
    var membershipType: String
    var cursorModelsPercent: Double
    var otherModelsPercent: Double
    var billingCycleEnd: Date?
    var onDemandEnabled: Bool
    var isUnlimited: Bool
    var fetchedAt: Date

    var worstPercent: Double {
        max(cursorModelsPercent, otherModelsPercent)
    }

    var includedTitle: String {
        let plan = membershipType.trimmingCharacters(in: .whitespacesAndNewlines)
        if plan.isEmpty { return "Included in Pro" }
        let pretty = plan.prefix(1).uppercased() + plan.dropFirst().lowercased()
        return "Included in \(pretty)"
    }

    /// Calendar days from today to the next usage reset (`billingCycleEnd`).
    /// If the API date is already past, rolls forward one month at a time.
    func daysUntilReset(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let reset = nextResetDate(now: now, calendar: calendar) else { return nil }
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: reset)
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    func nextResetDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard var end = billingCycleEnd else { return nil }
        var guardCount = 0
        while end < now, guardCount < 24 {
            guard let next = calendar.date(byAdding: .month, value: 1, to: end), next > end else { break }
            end = next
            guardCount += 1
        }
        return end
    }

    var resetCaption: String? {
        guard let days = daysUntilReset(), days >= 0 else { return nil }
        switch days {
        case 0: return "Resets today"
        case 1: return "1 day until reset"
        default: return "\(days) days until reset"
        }
    }

    static let placeholder = CursorUsageSnapshot(
        membershipType: "pro",
        cursorModelsPercent: 0,
        otherModelsPercent: 0,
        billingCycleEnd: nil,
        onDemandEnabled: true,
        isUnlimited: false,
        fetchedAt: .distantPast
    )
}

enum UsageSeverity {
    case normal
    case warning
    case critical

    init(percent: Double) {
        if percent >= 100 { self = .critical }
        else if percent >= 90 { self = .warning }
        else { self = .normal }
    }

    var color: Color {
        switch self {
        case .normal: Color(red: 0.45, green: 0.63, blue: 0.76) // soft blue like dashboard
        case .warning: Color(red: 0.95, green: 0.72, blue: 0.28)
        case .critical: Color(red: 0.92, green: 0.35, blue: 0.35)
        }
    }
}
