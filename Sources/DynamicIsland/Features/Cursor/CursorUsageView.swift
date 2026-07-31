import SwiftUI

struct CursorUsageView: View {
    let usage: CursorUsageSnapshot?
    let error: String?
    let isSignedIn: Bool
    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let usage {
                Text(usage.includedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                UsageBarRow(
                    title: "Cursor Models",
                    subtitle: "Includes Cursor Grok 4.5 and Composer 2.5",
                    percent: usage.cursorModelsPercent,
                    footer: "Additional usage beyond limits consumes Other Models quota or on-demand spend."
                )

                UsageBarRow(
                    title: "Other Models",
                    subtitle: nil,
                    percent: usage.otherModelsPercent,
                    footer: usage.onDemandEnabled
                        ? "Additional usage beyond limits consumes on-demand spend. Your plan includes at least $20 of API usage."
                        : "Additional usage beyond limits consumes on-demand spend."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isSignedIn ? "Loading usage…" : "Sign in to Cursor")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !isSignedIn {
                        AppKitActionButton(title: "Sign in", action: onSignIn)
                            .frame(width: 96, height: 34)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageBarRow: View {
    let title: String
    let subtitle: String?
    let percent: Double
    let footer: String

    private var severity: UsageSeverity { UsageSeverity(percent: percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
                Text("\(Int(percent.rounded()))% used")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(severity.color)
                        .frame(width: max(4, geo.size.width * CGFloat(min(percent, 100) / 100)))
                }
            }
            .frame(height: 6)

            Text(footer)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CursorCompactBadge: View {
    let percent: Double?

    var body: some View {
        let value = percent ?? 0
        let severity = UsageSeverity(percent: value)
        HStack(spacing: 7) {
            BrandLogoImage(logo: .cursor, size: 14, selected: true)
            Text(percent == nil ? "—" : "\(Int(value.rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(severity.color)
                .monospacedDigit()
        }
    }
}
