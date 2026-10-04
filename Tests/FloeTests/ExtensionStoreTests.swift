//
//  ExtensionStoreTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ExtensionStoreTests {
    @Test func aManifestBecomesTheStoreDetails() {
        let details = ExtensionStore.parseDetails(name: "weather-test", manifest: [
            "title": "Weather",
            "description": "Forecasts",
            "author": ["name": "someone"],
            "icon": "assets/weather icon.png",
            "commands": [["name": "forecast", "title": "Forecast"], ["name": "refresh", "mode": "no-view"], ["title": "Nameless"]],
        ])
        #expect(details.title == "Weather")
        #expect(details.author == "someone")
        #expect(details.commands.map(\.name) == ["forecast", "refresh"])
        #expect(details.commands.map(\.mode) == ["view", "no-view"])
    }

    @Test func remoteIconNamesAreEncoded() {
        let url = ExtensionStore.iconURL(for: "weather-test-not-installed", icon: "assets/weather icon.png")
        #expect(url?.absoluteString.hasSuffix("/weather-test-not-installed/assets/weather%20icon.png") == true)
    }

    @Test(arguments: ["icon:Star", "https://example.com/i.png", "data:image/png;base64,AA", ""])
    func iconsThatAreNotFilesInTheRepositoryHaveNoURL(icon: String) {
        #expect(ExtensionStore.iconURL(for: "weather-test", icon: icon) == nil)
    }

    @Test func aToolThatSucceedsHandsBackWhatItPrinted() async throws {
        let output = try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", "pwd; echo note >&2"], workingDirectory: URL(fileURLWithPath: "/usr"), context: "Listing failed")
        #expect(output.stdout == "/usr\n")
        #expect(output.stderr == "note\n")
    }

    @Test func aToolThatFailsReportsItsLastErrorLine() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", "echo out; echo first >&2; echo last >&2; echo >&2; exit 3"], context: "Clone failed")
        }
        #expect(failure?.message == "Clone failed: last")
    }

    @Test func aToolThatFailsQuietlyOnStderrReportsItsOutput() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/bin/sh", arguments: ["-c", "echo said; exit 1"], context: "Clone failed")
        }
        #expect(failure?.message == "Clone failed: said")
    }

    @Test func aToolThatCannotStartFailsWithItsContext() async {
        let failure = await #expect(throws: ExtensionStore.StoreFailure.self) {
            try await ExtensionStore.runTool(executable: "/nonexistent/floe-tool", arguments: [], context: "Bun install failed")
        }
        #expect(failure?.message.hasPrefix("Bun install failed: ") == true)
    }
}
