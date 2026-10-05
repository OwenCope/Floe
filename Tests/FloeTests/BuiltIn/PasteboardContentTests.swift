//
//  PasteboardContentTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor struct PasteboardContentTests {
    /// A pasteboard of the test's own, so the user's clipboard is never read or written.
    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    @Test func textIsWrittenAndReadBack() {
        withPasteboard { pasteboard in
            #expect(PasteboardContent.write(text: "hello", html: nil, file: nil, to: pasteboard))
            #expect(PasteboardContent.read(from: pasteboard) == ["text": "hello"])
        }
    }

    @Test func htmlTravelsBesideItsText() {
        withPasteboard { pasteboard in
            #expect(PasteboardContent.write(text: "bold", html: "<b>bold</b>", file: nil, to: pasteboard))
            #expect(PasteboardContent.read(from: pasteboard) == ["text": "bold", "html": "<b>bold</b>"])
        }
    }

    @Test func htmlAloneLeavesTheTextEmpty() {
        withPasteboard { pasteboard in
            #expect(PasteboardContent.write(text: "", html: "<i>x</i>", file: nil, to: pasteboard))
            #expect(pasteboard.string(forType: .string) == nil)
            #expect(PasteboardContent.read(from: pasteboard) == ["text": "", "html": "<i>x</i>"])
        }
    }

    @Test func aFileIsReadBackAsItsPath() {
        withPasteboard { pasteboard in
            #expect(PasteboardContent.write(text: "", html: nil, file: "/tmp/floe-report.pdf", to: pasteboard))
            #expect(PasteboardContent.read(from: pasteboard)["file"] == "/tmp/floe-report.pdf")
        }
    }

    @Test func aTildeInAFilePathIsTheHomeFolder() {
        withPasteboard { pasteboard in
            PasteboardContent.write(text: "", html: nil, file: "~/floe-notes.txt", to: pasteboard)
            #expect(PasteboardContent.read(from: pasteboard)["file"] == NSHomeDirectory() + "/floe-notes.txt")
        }
    }

    @Test func emptyContentStillWritesAnEmptyText() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.setString("old", forType: .string)
            #expect(PasteboardContent.write(text: "", html: "", file: "", to: pasteboard))
            #expect(pasteboard.string(forType: .string)?.isEmpty == true)
            #expect(PasteboardContent.read(from: pasteboard) == ["text": ""])
        }
    }

    @Test func anEmptyPasteboardReadsAsEmptyText() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            #expect(PasteboardContent.read(from: pasteboard) == ["text": ""])
        }
    }

    @Test func aSnapshotPutsBackEveryTypeOfEveryItem() throws {
        try withPasteboard { pasteboard in
            let custom = NSPasteboard.PasteboardType("app.floe.tests.custom")
            let first = NSPasteboardItem()
            first.setString("one", forType: .string)
            first.setData(Data([1, 2, 3]), forType: custom)
            let second = NSPasteboardItem()
            second.setString("two", forType: .string)
            pasteboard.clearContents()
            pasteboard.writeObjects([first, second])

            let snapshot = SavedPasteboard.capture(pasteboard)
            PasteboardContent.write(text: "borrowed", html: nil, file: nil, to: pasteboard)
            snapshot.restore(to: pasteboard)

            let items = try #require(pasteboard.pasteboardItems)
            #expect(items.map { $0.string(forType: .string) } == ["one", "two"])
            #expect(items[0].data(forType: custom) == Data([1, 2, 3]))
            #expect(items[1].data(forType: custom) == nil)
        }
    }

    @Test func aSnapshotOfNothingClearsWhatWasBorrowed() {
        withPasteboard { pasteboard in
            pasteboard.clearContents()
            let snapshot = SavedPasteboard.capture(pasteboard)
            #expect(snapshot.items.isEmpty)

            PasteboardContent.write(text: "borrowed", html: nil, file: nil, to: pasteboard)
            snapshot.restore(to: pasteboard)
            #expect(pasteboard.pasteboardItems?.isEmpty != false)
            #expect(pasteboard.string(forType: .string) == nil)
        }
    }

    @Test func theFinderErrorsSayWhatToDo() {
        #expect(SelectionError.finderNotFrontmost.errorDescription == "The Finder isn't frontmost, so there is no Finder selection to read.")
        #expect(SelectionError.finderEmpty.errorDescription == "No files are selected in the Finder.")
        #expect(SelectionError.automationRefused.errorDescription?.hasSuffix("(-1743)") == true)
    }
}
