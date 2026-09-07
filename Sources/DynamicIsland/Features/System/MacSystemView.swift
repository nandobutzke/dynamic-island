import SwiftUI

struct MacSystemView: View {
    let snapshot: MacSystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This Mac")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            HStack(alignment: .top, spacing: 10) {
                SystemStatColumn(
                    title: "CPU",
                    value: "\(Int(snapshot.cpuPercent.rounded()))%",
                    unitLabel: "Percent used",
                    fill: snapshot.cpuPercent / 100,
                    color: UsageSeverity(percent: snapshot.cpuPercent).color
                )
                SystemStatColumn(
                    title: "RAM",
                    value: memoryValue,
                    unitLabel: "Gigabytes used",
                    fill: snapshot.memoryPercent / 100,
                    color: UsageSeverity(percent: snapshot.memoryPercent).color
                )
                SystemStatColumn(
                    title: "Energy",
                    value: snapshot.energy.displayValue,
                    unitLabel: snapshot.energy.unitLabel,
                    fill: energyFill,
                    color: energyColor
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memoryValue: String {
        let used = formatGigabytes(snapshot.memoryUsedGigabytes)
        let total = formatGigabytes(snapshot.memoryTotalGigabytes)
        return "\(used)/\(total) GB"
    }

    private var energyFill: Double {
        switch snapshot.energy {
        case .watts(let watts):
            return min(1, watts / 20)
        case .unavailable:
            return 0
        }
    }

    private var energyColor: Color {
        switch snapshot.energy {
        case .watts(let watts):
            return UsageSeverity(percent: min(100, watts / 20 * 100)).color
        case .unavailable:
            return Color.white.opacity(0.35)
        }
    }

    private func formatGigabytes(_ value: Double) -> String {
        if value >= 10 {
            return String(format: "%.0f", value.rounded())
        }
        return String(format: "%.1f", value)
    }
}

private struct SystemStatColumn: View {
    let title: String
    let value: String
    let unitLabel: String
    let fill: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(unitLabel)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(min(max(fill, 0), 1))))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacSystemCompactBadge: View {
    let snapshot: MacSystemSnapshot

    var body: some View {
        let severity = UsageSeverity(percent: snapshot.cpuPercent)
        HStack(spacing: 7) {
            BrandLogoImage(logo: .system, size: 14, selected: true)
            Text("\(Int(snapshot.cpuPercent.rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(severity.color)
                .monospacedDigit()
        }
    }
}