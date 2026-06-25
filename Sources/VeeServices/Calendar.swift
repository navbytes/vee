import Foundation
import VeeProtocol

// MARK: - Raw event value type (crosses the seam)

/// An untrimmed calendar event as read from the OS, carrying the fields the
/// meeting-link detector needs (`location` + `notes`). The seam yields these
/// values; `CalendarService` maps them to the wire `CalendarEvent` (which only
/// carries the resolved `meetingURL`). No EventKit type ever crosses up.
public struct RawCalendarEvent: Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String
    public var notes: String
    public init(id: String, title: String, start: Date, end: Date,
                location: String, notes: String) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.location = location; self.notes = notes
    }
}

/// The OS seam over `EKEventStore`. Fake (tests) + thin real adapter conform;
/// sorting and link detection live ABOVE this seam.
public protocol CalendarProvider: AnyObject {
    /// Raw events whose start falls in `[start, end]`. Order is unspecified —
    /// the service sorts.
    func fetchRawEvents(from start: Date, to end: Date) -> [RawCalendarEvent]
}

// MARK: - Meeting-link detection (PURE regex)

/// Pure regex meeting-link detector. Scans a meeting's location AND notes (a
/// real-world bug: links live in notes when the location is a physical room) and
/// returns the first matching URL, preferring `location` then `notes`. Patterns
/// mirror MeetingBar's `MeetingServices` for the common providers.
public enum MeetingLinkDetector {

    /// Ordered URL patterns (most specific schemes first). Each captures a full URL.
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            // Zoom native scheme.
            #"zoommtg://[^\s>"']+"#,
            // Zoom web (any zoom subdomain).
            #"https://[a-zA-Z0-9.-]*zoom\.us/[^\s>"']+"#,
            // Microsoft Teams meetup-join (.com or .us).
            #"https://teams\.microsoft\.(com|us)/l/meetup-join/[^\s>"']+"#,
            // Google Meet.
            #"https://meet\.google\.com/[^\s>"']+"#,
            // Webex.
            #"https://[a-zA-Z0-9.-]*\.webex\.com/[^\s>"']+"#,
            // Slack huddle.
            #"https://app\.slack\.com/huddle/[^\s>"']+"#,
            // Jitsi (meet.jit.si or self-hosted jitsi subdomain).
            #"https://[a-zA-Z0-9.-]*jit\.si/[^\s>"']+"#,
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    /// First meeting URL found in `location` then `notes`, or nil.
    public static func detect(location: String, notes: String) -> String? {
        if let hit = firstMatch(in: location) { return hit }
        if let hit = firstMatch(in: notes) { return hit }
        return nil
    }

    private static func firstMatch(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in patterns {
            if let m = pattern.firstMatch(in: text, options: [], range: range),
               let r = Range(m.range, in: text) {
                return String(text[r])
            }
        }
        return nil
    }
}

// MARK: - Calendar service (above the seam)

/// Reads raw events over the `CalendarProvider` seam, filters to the upcoming
/// window, sorts by start, runs the pure link detector, and emits wire
/// `CalendarEvent`s. Fully tested with a fake provider.
public final class CalendarService {
    private let provider: CalendarProvider
    private let clock: Clock

    public init(provider: CalendarProvider, clock: Clock) {
        self.provider = provider
        self.clock = clock
    }

    /// Upcoming events within `window` seconds of now, sorted ascending by start,
    /// each with `meetingURL` resolved from location/notes. Events that already
    /// started (start < now) are excluded.
    public func upcoming(within window: TimeInterval) -> [CalendarEvent] {
        let now = clock.now
        let end = now.addingTimeInterval(window)
        let raw = provider.fetchRawEvents(from: now, to: end)
        return raw
            .filter { $0.start >= now }
            .sorted { $0.start < $1.start }
            .map { ev in
                CalendarEvent(
                    id: ev.id,
                    title: ev.title,
                    start: ev.start,
                    end: ev.end,
                    meetingURL: MeetingLinkDetector.detect(location: ev.location, notes: ev.notes)
                )
            }
    }
}

// MARK: - Thin real adapter (NOT unit-tested; needs full-access TCC)

#if canImport(EventKit)
import EventKit

/// Thin `EKEventStore`-backed `CalendarProvider`. Logic-free: it only translates
/// `EKEvent`s into `RawCalendarEvent` values. Reading events requires full-access
/// TCC (`requestFullAccessToEvents` + `NSCalendarsFullAccessUsageDescription`),
/// which belongs to the app, so this is intentionally NOT unit-tested here.
public final class EventKitCalendarProvider: CalendarProvider {
    private let store: EKEventStore
    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func fetchRawEvents(from start: Date, to end: Date) -> [RawCalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { ev in
            RawCalendarEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "",
                start: ev.startDate ?? start,
                end: ev.endDate ?? start,
                location: ev.location ?? "",
                notes: ev.notes ?? ""
            )
        }
    }
}
#endif
