import Combine
import Foundation

/// A calendar event, reduced to what a meeting recording uses.
struct CalendarEvent: Equatable {
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
    /// The call's link (Meet, Zoom…), when the event has one.
    var link: String?
}

/// The meetings' view of the calendar: today's events and the one going on now, from Google Calendar.
@MainActor
final class MeetingCalendar: ObservableObject {
    let google = GoogleCalendar()
    private var forward: AnyCancellable?

    init() {
        // Screens observing the calendar redraw when Google's events or connection change.
        forward = google.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isConfigured: Bool { google.isConnected }

    /// Today's events, in order.
    func todayEvents(at now: Date = Date()) -> [CalendarEvent] {
        let day = Calendar.current.startOfDay(for: now)
        let next = day.addingTimeInterval(86_400)
        return google.events.filter { $0.start < next && $0.end > day }.sorted { $0.start < $1.start }
    }

    /// The event going on now: started and not over, or starting within 10 minutes; the closest start wins.
    func currentEvent(at now: Date = Date()) -> CalendarEvent? {
        google.events
            .filter { $0.start <= now.addingTimeInterval(10 * 60) && $0.end > now }
            .min { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
    }
}
