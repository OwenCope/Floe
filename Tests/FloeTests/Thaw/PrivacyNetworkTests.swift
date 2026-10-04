//
//  PrivacyNetworkTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

struct PrivacyNetworkTests {
    @Test func theAILineNamesWhereAQuestionGoes() {
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "https://openrouter.ai/api/v1") == "Questions go to openrouter.ai, with your key, and nowhere else.")
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "").contains("api.openai.com"), "an empty address is OpenAI's")
        #expect(PrivacyNetwork.aiLine(source: .tools, baseURL: "").contains("claude or codex"))
    }

    @Test func whatStaysOnTheMacIsSaidToStayThere() {
        #expect(PrivacyNetwork.aiLine(source: .appleIntelligence, baseURL: "https://api.openai.com/v1").contains("Nothing is sent anywhere"))
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "http://localhost:11434/v1") == "Questions go to the server on this Mac at localhost. Nothing leaves the machine.")
    }

    @Test func anAddressThatIsNotOneClaimsNoDestination() {
        #expect(PrivacyNetwork.aiLine(source: .api, baseURL: "nonsense") == "Questions go to the address set in General, once it is filled in.")
    }

    @Test func aBuildWithoutUpdatesSaysNothingAboutThem() {
        // Under `swift test` the bundle has no feed, so the Updates rows are left out.
        #expect(PrivacyNetwork.updateHost == nil)
    }

    @Test func thePermissionsAreFoundOnThePrivacyPane() {
        #expect(SearchIndex.privacyEntries.allSatisfy { $0.pane == .privacy })
        #expect(SearchIndex.staticEntries.contains { $0.id == "privacy.permissions" })
        #expect(!SearchIndex.generalEntries.contains { $0.section == "Permissions" })
    }
}
