//
//  SettingsProcessTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct SettingsProcessTests {
    @Test func openingSettingsStartsAProcessWhenNoneRuns() {
        #expect(SettingsProcess.step(isRunning: false, page: nil, lastPage: nil) == .start(arguments: ["--settings"]))
        #expect(SettingsProcess.step(isRunning: false, page: "about", lastPage: nil) == .start(arguments: ["--settings", "--page", "about"]))
    }

    @Test func aNewProcessOpensWhereTheLastOneWasLeft() {
        #expect(SettingsProcess.step(isRunning: false, page: nil, lastPage: "privacy") == .start(arguments: ["--settings", "--page", "privacy"]))
        #expect(
            SettingsProcess.step(isRunning: false, page: "extension:planets", lastPage: "privacy")
                == .start(arguments: ["--settings", "--page", "extension:planets"]),
            "a page that is asked for wins over the remembered one"
        )
    }

    @Test func openingSettingsAgainBringsTheRunningProcessForward() {
        #expect(SettingsProcess.step(isRunning: true, page: nil, lastPage: "privacy") == .bringForward(page: ""))
        #expect(SettingsProcess.step(isRunning: true, page: "about", lastPage: "privacy") == .bringForward(page: "about"))
    }

    @Test func aHandleWithNoProcessHasNoPid() {
        #expect(SettingsProcess().pid == nil)
    }
}

struct RemoteRecordingTests {
    @Test func theHotkeysStandDownWhileTheSettingsProcessRecords() {
        var recording = RemoteRecording()
        #expect(!recording.isRecording)
        recording.received(true)
        #expect(recording.isRecording)
        recording.received(false)
        #expect(!recording.isRecording)
    }

    @Test func aSettingsProcessThatDiesMidRecordingDoesNotLeaveThemSuspended() {
        var recording = RemoteRecording()
        recording.received(true)
        recording.settingsProcessExited()
        #expect(!recording.isRecording)
    }
}

struct SettingsModeTests {
    @Test func theSettingsModeIsParsedWithItsPage() throws {
        #expect(try DebugOptions.parse(["--settings"]).settings)
        #expect(try DebugOptions.parse(["--settings"]).settingsPage == nil)
        #expect(try DebugOptions.parse(["--settings", "--page", "about"]).settingsPage == .about)
        #expect(try DebugOptions.parse(["--settings", "--page", "extension:planets"]).settingsPage == .extensionPage("planets"))
        #expect(try DebugOptions.parse(["--settings", "--extension", "planets"]).settingsPage == .extensionPage("planets"))
        #expect(try !DebugOptions.parse([]).settings)
    }

    @Test func aPageNeedsTheSettingsModeAndARealName() {
        #expect(throws: (any Error).self) { try DebugOptions.parse(["--page", "about"]) }
        #expect(throws: (any Error).self) { try DebugOptions.parse(["--extension", "planets"]) }
        #expect(throws: (any Error).self) { try DebugOptions.parse(["--settings", "--page", "nowhere"]) }
        #expect(throws: (any Error).self) { try DebugOptions.parse(["--settings", "--page", "about", "--extension", "planets"]) }
    }

    @Test func everyPageHasANameThatReadsBack() {
        let pages: [SettingsPage] = [.general, .applications, .quicklinks, .snippets, .extensionStore, .appearance, .privacy, .about, .extensionPage("kill-process")]
        for page in pages {
            #expect(SettingsPage(id: page.id) == page)
        }
        #expect(Set(pages.map(\.id)).count == pages.count)
        #expect(SettingsPage(id: "") == nil)
        #expect(SettingsPage(id: "extension:") == nil)
    }

    @Test func theProcessEndsWhenItsWindowIsClosedAndNothingIsStillGoing() {
        #expect(SettingsExit.isDue(windowOpen: false, otherWindowOpen: false, installing: false))
        #expect(!SettingsExit.isDue(windowOpen: true, otherWindowOpen: false, installing: false))
        #expect(!SettingsExit.isDue(windowOpen: false, otherWindowOpen: true, installing: false), "the welcome or the release notes it opened are still up")
        #expect(!SettingsExit.isDue(windowOpen: false, otherWindowOpen: false, installing: true), "an extension is still being installed")
    }
}

struct UpdatesLinkTests {
    @Test func everyRequestReadsBackFromItsText() {
        let requests: [UpdateRequest] = [
            .check, .setChecks(true), .setChecks(false), .setDownloads(true), .setDownloads(false),
            .setChannel(.stable), .setChannel(.beta), .consent(.off), .consent(.check), .consent(.download),
        ]
        for request in requests {
            #expect(UpdateRequest(text: request.text) == request)
        }
    }

    @Test func textThatIsNoRequestIsRefused() {
        for text in ["", "check:1", "checks", "checks:2", "downloads:yes", "channel:nightly", "consent:3", "install:https://example.com"] {
            #expect(UpdateRequest(text: text) == nil, "\(text)")
        }
    }

    @MainActor @Test func inTheSettingsProcessTheUpdateControlsAskTheLauncher() throws {
        let scratch = try ScratchDefaults()
        let configuration = UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: Data(count: 32).base64EncodedString())
        let manager = UpdatesManager(configuration: configuration, defaults: scratch.defaults)
        var sent: [UpdateRequest] = []
        manager.sendToLauncher = { sent.append($0) }

        manager.automaticallyChecksForUpdates = true
        manager.automaticallyDownloadsUpdates = true
        manager.updateChannel = .beta
        manager.checkForUpdates()
        manager.answerConsent(.check)
        #expect(sent == [.setChecks(true), .setDownloads(true), .setChannel(.beta), .check, .consent(.check)])
        #expect(!manager.hasStartedUpdater, "no updater runs in the settings process")
        #expect(UpdateChannel.stored(in: scratch.defaults) == .stable, "the launcher is the one that stores the channel")
        #expect(manager.updateChannel == .beta, "the control shows the choice at once")
        #expect(manager.automaticallyChecksForUpdates)
        #expect(!manager.automaticallyDownloadsUpdates, "the consent answer was to check only")

        var state = UpdatesState()
        state.canCheckNow = true
        state.lastCheck = Date(timeIntervalSinceReferenceDate: 800_000_000)
        manager.show(state)
        #expect(manager.canCheckNow)
        #expect(manager.lastUpdateCheckDate == state.lastCheck)
        #expect(!manager.automaticallyChecksForUpdates, "what the launcher reports replaces what was shown")
    }

    @Test func theUpdatersStateReadsBackFromItsText() {
        var state = UpdatesState()
        state.canCheckNow = true
        state.checks = true
        state.lastCheck = Date(timeIntervalSinceReferenceDate: 800_000_000)
        state.channel = UpdateChannel.beta.rawValue
        #expect(UpdatesState(text: state.text) == state)
        #expect(UpdatesState(text: UpdatesState().text) == UpdatesState())
        #expect(UpdatesState(text: "not json") == nil)
    }
}
