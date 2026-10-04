//
//  CalendarTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct CalendarTests {
    @Test(arguments: ["today", "calendar", "agenda", "meetings", "next meeting", "Today"])
    func agendaWordsShowTheAgenda(query: String) {
        #expect(CalendarAgenda.isTrigger(query))
    }

    @Test(arguments: ["", "to", "safari", "terminal"])
    func otherSearchesDoNot(query: String) {
        #expect(!CalendarAgenda.isTrigger(query))
    }

    @Test func aCallLinkInTheNotesIsFound() {
        let url = CalendarAgenda.meetingURL(url: nil, location: "Room 4", notes: "Agenda\nJoin: https://us02web.zoom.us/j/123 thanks")
        #expect(url?.host == "us02web.zoom.us")
    }

    @Test func theEventURLWinsAndOtherLinksAreIgnored() {
        let meet = URL(string: "https://meet.google.com/abc-defg-hij")
        #expect(CalendarAgenda.meetingURL(url: meet, location: nil, notes: "https://example.com") == meet)
        #expect(CalendarAgenda.meetingURL(url: URL(string: "https://example.com"), location: nil, notes: nil) == nil)
        #expect(CalendarAgenda.meetingURL(url: URL(string: "https://notzoom.us.example.com"), location: nil, notes: nil) == nil)
    }
}
