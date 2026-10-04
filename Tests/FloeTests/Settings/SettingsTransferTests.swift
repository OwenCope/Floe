//
//  SettingsTransferTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SettingsTransferTests {
    private func archive() -> SettingsTransfer.Archive {
        SettingsTransfer.Archive(
            settings: Data(#"{"aliases":{"a":"x","b":"y"},"favorites":["one"],"commandHotkeys":{"c":{}}}"#.utf8),
            preferences: ["weather": ["unit": "metric", "days": 3]],
            secretKeys: ["github": ["token"], "weather": ["apiKey"]]
        )
    }

    @Test func anExportReadsBackTheSame() throws {
        let decoded = try SettingsTransfer.decode(SettingsTransfer.encode(archive()))
        #expect(decoded.preferences["weather"]?["unit"] as? String == "metric")
        #expect(decoded.preferences["weather"]?["days"] as? Int == 3)
        #expect(decoded.secretKeys == ["github": ["token"], "weather": ["apiKey"]])
    }

    @Test func aFileWithoutSecretKeysStillLoads() throws {
        let decoded = try SettingsTransfer.decode(Data(#"{"version":1,"settings":{}}"#.utf8))
        #expect(decoded.secretKeys.isEmpty)
        #expect(decoded.preferences.isEmpty)
    }

    @Test func aNewerFileAndAnyOtherJSONAreRefused() {
        #expect(throws: SettingsTransfer.TransferError.newerVersion(2)) {
            try SettingsTransfer.decode(Data(#"{"version":2,"settings":{}}"#.utf8))
        }
        #expect(throws: SettingsTransfer.TransferError.notAnExport) {
            try SettingsTransfer.decode(Data(#"{"name":"package"}"#.utf8))
        }
    }

    @Test func theSummaryCountsWhatCameAndListsPasswordsToEnterAgain() {
        let summary = SettingsTransfer.summary(of: archive()) { name, _ in name == "weather" }
        #expect(summary == SettingsTransfer.Summary(aliases: 2, hotkeys: 1, favorites: 1, extensions: 1, missingSecrets: ["github: token"]))
    }
}
