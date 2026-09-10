import EventKit
import Foundation

@MainActor
final class CalendarNudgeProvider: NudgeProvider {
    let source: NudgeSource = .calendar

    func currentNudges() async -> [Nudge] {
        CalendarEventKitHelper.shared.refreshIfNeeded()
        let now = Date()
        return CalendarEventKitHelper.shared.upcomingEvents().compactMap { event in
            guard let start = event.startDate, start > now else { return nil }
            let seconds = start.timeIntervalSince(now)
            guard let priority = Self.priority(forSecondsUntil: seconds) else { return nil }
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = (title?.isEmpty == false) ? title! : "Evento"
            return Nudge(
                id: "calendar.\(event.eventIdentifier ?? displayTitle).\(Int(start.timeIntervalSince1970))",
                source: .calendar,
                emoji: "📅",
                title: displayTitle,
                description: Self.startsInDescription(until: start, now: now),
                priority: priority,
                createdAt: now
            )
        }
    }

    /// Urgent: now → ~42 min. High: ~1 h ± 15 min. Medium: ~5 h ± 30 min.
    static func priority(forSecondsUntil seconds: TimeInterval) -> NudgePriority? {
        let minutes = seconds / 60
        if minutes <= 42 { return .urgent }
        if minutes >= 45 && minutes <= 75 { return .high }
        if minutes >= (5 * 60 - 30) && minutes <= (5 * 60 + 30) { return .medium }
        return nil
    }

    static func startsInDescription(until start: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: start, relativeTo: now)
        return "Começa \(relative)"
    }
}
