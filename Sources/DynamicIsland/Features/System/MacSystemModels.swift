import Foundation
import SwiftUI

struct MacSystemSnapshot: Equatable {
    var cpuPercent: Double
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var energy: MacEnergyReading
    var sampledAt: Date

    var memoryUsedGigabytes: Double {
        Double(memoryUsedBytes) / 1_073_741_824
    }

    var memoryTotalGigabytes: Double {
        Double(memoryTotalBytes) / 1_073_741_824
    }

    var memoryPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(100, Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100)
    }

    static let placeholder = MacSystemSnapshot(
        cpuPercent: 0,
        memoryUsedBytes: 0,
        memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
        energy: .unavailable,
        sampledAt: .distantPast
    )
}

enum MacEnergyReading: Equatable {
    /// Rolling average of process-attributed power from running apps (watts).
    case watts(Double)
    case unavailable

    var displayValue: String {
        switch self {
        case .watts(let watts):
            return String(format: watts >= 10 ? "%.0f W" : "%.1f W", watts)
        case .unavailable:
            return "—"
        }
    }

    /// Brief unit / meaning under the value.
    var unitLabel: String {
        switch self {
        case .watts:
            return "Avg app watts"
        case .unavailable:
            return "Energy unavailable"
        }
    }
}
