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
