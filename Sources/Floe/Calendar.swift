//
//  Calendar.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import EventKit

/// One event from today or tomorrow, copied out of EventKit so it can be held and compared.
struct CalendarEvent: Equatable, Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let meetingURL: URL?

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)

    var subtitle: String {
        isAllDay
            ? "All day · \(calendarTitle)"
            : "\(startDate.formatted(Self.timeFormat)) to \(endDate.formatted(Self.timeFormat)) · \(calendarTitle)"
    }

    /// Opens the event in Calendar.
    var calendarURL: URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: allowed) ?? identifier
        return URL(string: "ical://ekevent/\(encoded)?method=show&options=more")
    }
}

/// Today's remaining and tomorrow's events, shown when the search asks for them. Access is asked for
/// the first time such a search is typed, never at launch.
final class CalendarAgenda {
    static let shared = CalendarAgenda()

    /// Called on the main queue when newly loaded events could change the results.
    var onChange: () -> Void = {}

    private static let triggers = ["calendar", "today", "meetings", "events", "agenda", "next meeting"]
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
    private static let cacheLifetime: TimeInterval = 60

    private let store = EKEventStore()
    private var events: [CalendarEvent] = []
    private var loadedAt: Date?
    private var isLoading = false
    private var askedForAccess = false
    private var observer: NSObjectProtocol?

    /// Whether a query is asking for the agenda: a close match for one of the trigger words.
    static func isTrigger(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        return triggers.contains { (Fuzzy.score(trimmed, $0) ?? 0) >= 70 }
    }

    /// The first video call link in the event's URL, location or notes.
    static func meetingURL(url: URL?, location: String?, notes: String?) -> URL? {
        var candidates = url.map { [$0] } ?? []
        let text = [location, notes].compactMap(\.self).joined(separator: "\n")
        if !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            candidates += detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
        }
        return candidates.first { candidate in
            guard let host = candidate.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// Up to eight upcoming events for a trigger query; empty otherwise, or until access is granted.
    func events(matching query: String) -> [CalendarEvent] {
        guard Self.isTrigger(query) else { return [] }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            requestAccess()
            return []
        case .fullAccess:
            break
        default:
            return []
        }
        observeChanges()
        loadIfStale()
        let now = Date()
        return Array(events.filter { $0.endDate > now }.prefix(8))
    }

    private func requestAccess() {
        guard !askedForAccess else { return }
        askedForAccess = true
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self?.loadIfStale() }
        }
    }

    private func observeChanges() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.loadedAt = nil
            self?.loadIfStale()
        }
    }

    private func loadIfStale() {
        guard !isLoading else { return }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < Self.cacheLifetime { return }
        isLoading = true
        let store = store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: Date())
            let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(2 * 86400)
            let loaded = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
                .map { event in
                    CalendarEvent(
                        identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                        title: event.title ?? "Untitled",
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay,
                        calendarTitle: event.calendar?.title ?? "Calendar",
                        meetingURL: Self.meetingURL(url: event.url, location: event.location, notes: event.notes)
                    )
                }
                .sorted { $0.startDate < $1.startDate }
            DispatchQueue.main.async {
                guard let self else { return }
                self.events = loaded
                self.loadedAt = Date()
                self.isLoading = false
                self.onChange()
            }
        }
    }
}
