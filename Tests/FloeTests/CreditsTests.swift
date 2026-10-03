//
//  CreditsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

/// Credits.swift is written by scripts/generate-credits.py; these catch a script change that breaks the list.
struct CreditsTests {
    @Test func theListNamesWhatFloeIsBuiltFrom() {
        let names = Credits.all.map(\.name)
        for expected in ["Thaw", "CompactSlider", "Bun", "React", "react-reconciler", "Raycast extensions"] {
            #expect(names.contains(expected), "\(expected)")
        }
    }

    @Test func namesAreUniqueBecauseTheSheetUsesThemAsIdentifiers() {
        #expect(Set(Credits.all.map(\.id)).count == Credits.all.count)
    }

    @Test func everyEntryHasALinkNameAndADetailSentence() {
        for credit in Credits.all {
            #expect(!credit.link.isEmpty, "\(credit.name)")
            #expect(credit.detail.hasSuffix("."), "\(credit.name)")
        }
    }

    @Test func theTrademarkNoteNamesRaycast() {
        #expect(Credits.trademark.contains("Raycast"))
    }
}
