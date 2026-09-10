import EventKit
import Foundation

@MainActor
final class CalendarEventKitHelper {
    static let shared = CalendarEventKitHelper()

    private let store = EKEventStore()
    private var cache: [EKEvent] = []
    private var lastFetch = Date.distantPast
    private let cacheTTL: TimeInterval = 45
    private let horizon: TimeInterval = 8 * 60 * 60
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastFetch = .distantPast
                self?.refreshIfNeeded()
            }
        }
    }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func upcomingEvents() -> [EKEvent] {
        refreshIfNeeded()
        return cache
    }

    func refreshIfNeeded() {
        guard isAuthorized else {
            cache = []
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastFetch) >= cacheTTL else { return }
        lastFetch = now
        let end = now.addingTimeInterval(horizon)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        cache = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
}
