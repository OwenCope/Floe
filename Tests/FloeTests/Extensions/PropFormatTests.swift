//
//  PropFormatTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct PropFormatTests {
    @Test func textReadsStringsNumbersAndValueObjects() {
        #expect(PropFormat.text("plain") == "plain")
        #expect(PropFormat.text(42) == "42")
        #expect(PropFormat.text(1.5) == "1.5")
        #expect(PropFormat.text(["value": "wrapped", "color": "color:Red"]) == "wrapped")
        #expect(PropFormat.text(["value": 7]) == "7")
    }

    @Test(arguments: [nil, ["color": "color:Red"], ["a", "b"]] as [Any?])
    func textIsNilForAnythingElse(value: Any?) {
        #expect(PropFormat.text(value) == nil)
    }

    @Test func colorComesFromAValueObject() {
        #expect(PropFormat.color(["value": "x", "color": "color:Red"]) as? String == "color:Red")
        #expect(PropFormat.color(["value": "x"]) == nil)
        #expect(PropFormat.color("plain") == nil)
    }

    @Test func datesParseWithAndWithoutFractionalSeconds() throws {
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-10-09T12:30:00Z"))
        #expect(PropFormat.date("2026-10-09T12:30:00Z") == expected)
        #expect(PropFormat.date("2026-10-09T12:30:00.000Z") == expected, "the host serializes Date as ISO with milliseconds")
        #expect(PropFormat.date(["value": "2026-10-09T12:30:00.000Z"]) == expected)
    }

    @Test(arguments: [nil, "yesterday", 1_700_000_000, ["value": 3]] as [Any?])
    func invalidDatesAreNil(value: Any?) {
        #expect(PropFormat.date(value) == nil)
    }
}
