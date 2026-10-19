import EventKit
import Foundation

/// A calendar event, reduced to what a meeting recording uses.
struct CalendarEvent: Equatable {
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
}

/// The meeting happening now, from the Mac's calendars (EventKit) and/or an iCal address (phase 4).
@MainActor
final class MeetingCalendar: ObservableObject {
    private let store = EKEventStore()
    private var icsEvents: [CalendarEvent] = []
    private var refresh: Timer?

    init() {
        Task { await reloadICS() }
        refresh = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { await self?.reloadICS() }
        }
    }

    /// Asks for calendar access when the person turns the option on; false if they decline.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func reloadICS() async {
        guard let address = URL(string: Settings.calendarICS.trimmingCharacters(in: .whitespaces)),
              address.scheme?.hasPrefix("http") == true || address.scheme == "webcal" else {
            icsEvents = []
            return
        }
        var components = URLComponents(url: address, resolvingAgainstBaseURL: false)
        if components?.scheme == "webcal" { components?.scheme = "https" }
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
        icsEvents = ICS.events(in: String(decoding: data, as: UTF8.self), around: Date())
    }

    /// The event going on now: started and not over, or starting within 10 minutes; the closest start wins.
    func currentEvent(at now: Date = Date()) -> CalendarEvent? {
        var candidates = icsEvents
        if Settings.useSystemCalendars, EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600),
                                                     end: now.addingTimeInterval(12 * 3600), calendars: nil)
            candidates += store.events(matching: predicate).filter { !$0.isAllDay && $0.status != .canceled }.map { event in
                CalendarEvent(
                    title: event.title ?? "Reunião",
                    start: event.startDate,
                    end: event.endDate,
                    attendees: (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap { participant in
                        participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                            .components(separatedBy: "@").first
                    }
                )
            }
        }
        return candidates
            .filter { $0.start <= now.addingTimeInterval(10 * 60) && $0.end > now }
            .min { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
    }
}

/// A small iCalendar reader: VEVENTs with start, end, title, attendees, cancellation, and daily/weekly repetition
/// expanded around a day (see docs/reunioes.md, phase 4).
enum ICS {
    static func events(in text: String, around day: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: day).addingTimeInterval(-86_400)
        let windowEnd = windowStart.addingTimeInterval(3 * 86_400)

        var events: [CalendarEvent] = []
        var fields: [(name: String, params: [String: String], value: String)] = []
        var inEvent = false
        for line in unfold(text) {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                fields = []
            } else if line == "END:VEVENT" {
                inEvent = false
                events += expand(fields, from: windowStart, to: windowEnd)
            } else if inEvent, let field = parse(line) {
                fields.append(field)
            }
        }
        return events
    }

    /// Joins folded lines (a continuation starts with a space or a tab).
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        return lines
    }

    private static func parse(_ line: String) -> (name: String, params: [String: String], value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        var head = line[..<colon].components(separatedBy: ";")
        let name = head.removeFirst().uppercased()
        var params: [String: String] = [:]
        for param in head {
            let pair = param.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return (name, params, String(line[line.index(after: colon)...]))
    }

    private static func expand(_ fields: [(name: String, params: [String: String], value: String)],
                               from windowStart: Date, to windowEnd: Date) -> [CalendarEvent] {
        func field(_ name: String) -> (params: [String: String], value: String)? {
            fields.first { $0.name == name }.map { ($0.params, $0.value) }
        }
        guard field("STATUS")?.value.uppercased() != "CANCELLED",
              let startField = field("DTSTART"), let start = date(startField.value, timeZone: startField.params["TZID"]) else { return [] }
        let duration: TimeInterval
        if let endField = field("DTEND"), let end = date(endField.value, timeZone: endField.params["TZID"]) {
            duration = end.timeIntervalSince(start)
        } else if let value = field("DURATION")?.value {
            duration = parseDuration(value)
        } else {
            duration = 3600
        }
        let title = unescape(field("SUMMARY")?.value ?? "Reunião")
        let attendees = fields.filter { $0.name == "ATTENDEE" || $0.name == "ORGANIZER" }.compactMap { item -> String? in
            if let name = item.params["CN"], !name.isEmpty, !name.contains("@") { return unescape(name) }
            let address = item.value.replacingOccurrences(of: "mailto:", with: "", options: .caseInsensitive)
            return address.components(separatedBy: "@").first.flatMap { $0.isEmpty ? nil : $0 }
        }
        var seen = Set<String>()
        let people = attendees.filter { seen.insert($0.lowercased()).inserted }
        let excluded = Set(fields.filter { $0.name == "EXDATE" }.flatMap { item in
            item.value.split(separator: ",").compactMap { date(String($0), timeZone: item.params["TZID"]) }
        })

        var starts: [Date] = []
        if let rule = field("RRULE")?.value {
            starts = occurrences(of: rule, from: start, until: windowEnd)
        } else {
            starts = [start]
        }
        return starts
            .filter { !excluded.contains($0) && $0 < windowEnd && $0.addingTimeInterval(duration) > windowStart }
            .map { CalendarEvent(title: title, start: $0, end: $0.addingTimeInterval(duration), attendees: people) }
    }

    /// Daily and weekly repetition: INTERVAL, BYDAY, UNTIL and COUNT.
    private static func occurrences(of rule: String, from start: Date, until limit: Date) -> [Date] {
        var parts: [String: String] = [:]
        for item in rule.split(separator: ";") {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { parts[pair[0].uppercased()] = pair[1] }
        }
        guard let frequency = parts["FREQ"], frequency == "DAILY" || frequency == "WEEKLY" else { return [start] }
        let interval = max(1, Int(parts["INTERVAL"] ?? "") ?? 1)
        let until = parts["UNTIL"].flatMap { date($0, timeZone: nil) }
        let count = parts["COUNT"].flatMap(Int.init)
        let weekdays: Set<Int> = Set((parts["BYDAY"] ?? "").split(separator: ",").compactMap { code in
            ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][String(code.suffix(2))]
        })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start

        var result: [Date] = []
        var produced = 0
        var day = start
        while day < limit {
            if let until, day > until { break }
            if let count, produced >= count { break }
            let matches: Bool
            if frequency == "DAILY" {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: day)).day ?? 0
                matches = days % interval == 0
            } else {
                let week = calendar.dateComponents([.weekOfYear], from: startWeek, to: day).weekOfYear ?? 0
                let weekday = calendar.component(.weekday, from: day)
                matches = week % interval == 0 && (weekdays.isEmpty ? weekday == calendar.component(.weekday, from: start) : weekdays.contains(weekday))
            }
            if matches {
                result.append(day)
                produced += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// `20261018T140000Z`, `20261018T140000` (with a TZID, or local) and `20261018` (all day, local midnight).
    static func date(_ value: String, timeZone identifier: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let text = value.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("Z") {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else if text.contains("T") {
            formatter.timeZone = identifier.flatMap(TimeZone.init(identifier:)) ?? .current
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        } else {
            formatter.timeZone = .current
            formatter.dateFormat = "yyyyMMdd"
        }
        return formatter.date(from: text)
    }

    /// `PT1H30M`, `PT45M`, `P1D`.
    private static func parseDuration(_ value: String) -> TimeInterval {
        var total: TimeInterval = 0, number = ""
        for character in value {
            if character.isNumber {
                number.append(character)
            } else {
                let amount = TimeInterval(number) ?? 0
                switch character {
                case "W": total += amount * 604_800
                case "D": total += amount * 86_400
                case "H": total += amount * 3600
                case "M": total += amount * 60
                case "S": total += amount
                default: break
                }
                number = ""
            }
        }
        return total > 0 ? total : 3600
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\\\", with: "\\")
    }
}
