//
//  HostRequestTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct HostRequestTests {
    private let claude = URL(fileURLWithPath: "/tools/claude")
    private let codex = URL(fileURLWithPath: "/tools/codex")

    private func installed(_ names: String...) -> (String) -> URL? {
        { name in names.contains(name) ? URL(fileURLWithPath: "/tools/\(name)") : nil }
    }

    @Test func anAskCarriesItsPromptAndModel() {
        #expect(HostRequest(method: "ai.ask", params: ["prompt": "why?", "model": "Anthropic_Claude_Sonnet"]) == .askAI(prompt: "why?", model: "Anthropic_Claude_Sonnet"))
        #expect(HostRequest(method: "ai.ask", params: ["prompt": "why?"]) == .askAI(prompt: "why?", model: nil))
    }

    @Test func anUnknownMethodOrAMissingPromptIsNoRequest() {
        #expect(HostRequest(method: "ai.ask", params: [:]) == nil)
        #expect(HostRequest(method: "oauth.authorize", params: ["prompt": "why?"]) == nil)
    }

    @Test func claudeAnswersWhenItIsInstalled() {
        #expect(AIEngine.resolve(model: nil, which: installed("claude", "codex")) == .claude(executable: claude, model: nil))
        #expect(AIEngine.resolve(model: "Anthropic_Claude_Opus", which: installed("claude")) == .claude(executable: claude, model: "opus"))
    }

    @Test func codexAnswersWhenItIsAllThereIsOrAnOpenAIModelIsAsked() {
        #expect(AIEngine.resolve(model: nil, which: installed("codex")) == .codex(executable: codex, model: nil))
        #expect(AIEngine.resolve(model: "OpenAI_GPT4o", which: installed("claude", "codex")) == .codex(executable: codex, model: nil))
        #expect(AIEngine.resolve(model: "openai-gpt-4o", which: installed("claude")) == .claude(executable: claude, model: nil))
    }

    @Test func nothingAnswersWithoutATool() {
        #expect(AIEngine.resolve(model: nil, which: installed()) == nil)
        #expect(AIEngine.missingMessage.contains("claude"))
    }

    @Test(arguments: [
        ("Anthropic_Claude_Sonnet", "sonnet"),
        ("anthropic-claude-haiku", "haiku"),
        ("Anthropic_Claude_Opus", "opus"),
    ])
    func raycastsModelNamesMapToClaudesAliases(requested: String, alias: String) {
        #expect(AIEngine.claudeModel(for: requested) == alias)
    }

    @Test func otherModelNamesLeaveTheChoiceToTheEngine() {
        #expect(AIEngine.claudeModel(for: nil) == nil)
        #expect(AIEngine.claudeModel(for: "Perplexity_Sonar") == nil)
    }

    // MARK: The API

    @Test func theChatAddressSitsUnderTheBaseAddress() {
        #expect(AIEndpoint.chatURL(baseURL: "https://api.openai.com/v1")?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: " http://localhost:11434/v1// ")?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: "https://api.z.ai/api/paas/v4/chat/completions")?.absoluteString == "https://api.z.ai/api/paas/v4/chat/completions")
        #expect(AIEndpoint.chatURL(baseURL: "")?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test(arguments: ["api.openai.com/v1", "ftp://example.com", "https://", "not a url"])
    func anAddressThatIsNotAWebAddressIsRefused(address: String) {
        #expect(AIEndpoint.chatURL(baseURL: address) == nil)
    }

    @Test func anEndpointNeedsItsAddressModelAndKey() {
        let endpoint = AIEndpoint(baseURL: "https://api.test/v1", model: " small ", apiKey: " key-123\n")
        #expect(endpoint?.chatURL.absoluteString == "https://api.test/v1/chat/completions")
        #expect(endpoint?.model == "small")
        #expect(endpoint?.apiKey == "key-123")
        #expect(AIEndpoint(baseURL: "https://api.test/v1", model: "", apiKey: "key") == nil)
        #expect(AIEndpoint(baseURL: "https://api.test/v1", model: "small", apiKey: nil) == nil)
        #expect(AIEndpoint(baseURL: "nonsense", model: "small", apiKey: "key") == nil)
    }

    @Test func aCompleteSetupHasNoProblem() {
        #expect(AIEndpoint.problem(baseURL: "https://api.test/v1", model: "small", apiKey: "key") == nil)
        #expect(AIEndpoint.problem(baseURL: "", model: "small", apiKey: "key") == nil)
    }

    @Test func anIncompleteSetupSaysWhatItStillNeeds() {
        #expect(AIEndpoint.problem(baseURL: "https://api.test/v1", model: " ", apiKey: "key") == "AI can't answer yet. It needs a model.")
        #expect(AIEndpoint.problem(baseURL: "https://api.test/v1", model: "", apiKey: nil) == "AI can't answer yet. It needs a model and an API key.")
        #expect(AIEndpoint.problem(baseURL: "nonsense", model: "", apiKey: "") == "AI can't answer yet. It needs an address that starts with http:// or https://, a model and an API key.")
    }

    @Test func aServerOnThisMacNeedsNoKey() {
        let local = AIEndpoint(baseURL: "http://localhost:11434/v1", model: "llama3.2", apiKey: nil)
        #expect(local?.chatURL.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(local?.apiKey.isEmpty == true)
        #expect(AIEndpoint.problem(baseURL: "http://127.0.0.1:1234/v1", model: "qwen", apiKey: "") == nil)
        #expect(AIEndpoint.problem(baseURL: "http://localhost:11434/v1", model: "", apiKey: nil) == "AI can't answer yet. It needs a model.")
        #expect(AIEndpoint.needsKey(URL(string: "https://openrouter.ai/api/v1/chat/completions")))
        #expect(AIEndpoint.needsKey(nil), "an address that is not one still asks for everything")
    }

    @Test func aRequestWithoutAKeyCarriesNoAuthorizationHeader() throws {
        let url = try #require(URL(string: "http://localhost:11434/v1/chat/completions"))
        let keyless = ChatCompletionStream.request(chatURL: url, apiKey: "", model: "llama3.2", prompt: "hi")
        #expect(keyless.value(forHTTPHeaderField: "Authorization") == nil)
        let keyed = ChatCompletionStream.request(chatURL: url, apiKey: "key-123", model: "llama3.2", prompt: "hi")
        #expect(keyed.value(forHTTPHeaderField: "Authorization") == "Bearer key-123")
    }

    @Test func theServicePickerFollowsTheAddressThatIsStored() {
        #expect(AIService.matching("") == .openAI, "an empty address is OpenAI's")
        #expect(AIService.matching("https://api.openai.com/v1/") == .openAI)
        #expect(AIService.matching("http://localhost:11434/v1") == .ollama)
        #expect(AIService.matching("http://localhost:1234/v1/chat/completions") == .lmStudio)
        #expect(AIService.matching("https://openrouter.ai/api/v1") == .openRouter)
        #expect(AIService.matching("https://api.z.ai/api/paas/v4") == .other)
        #expect(AIService.matching("nonsense") == .other)
        #expect(AIService.allCases.filter { $0.baseURL == nil } == [.other])
    }

    @Test func appleIntelligenceIsAChoiceThatNeverReadsTheKey() {
        let choice = AIAnswer.choice(source: .appleIntelligence, baseURL: "", model: "") {
            Issue.record("the Keychain was read for the on-device model")
            return "key"
        }
        #expect(choice == .appleIntelligence)
    }

    @Test func onlyWhatIsNewInAnAnswerIsPassedOn() {
        #expect(AppleIntelligence.addition(from: "", to: "po") == "po")
        #expect(AppleIntelligence.addition(from: "po", to: "pong") == "ng")
        #expect(AppleIntelligence.addition(from: "pong", to: "pong").isEmpty)
        #expect(AppleIntelligence.addition(from: "ping", to: "pong") == "pong", "a rewritten answer is sent whole")
    }

    @Test func theToolsChoiceNeverReadsTheKey() {
        let choice = AIAnswer.choice(source: .tools, baseURL: "https://api.test/v1", model: "small") {
            Issue.record("the Keychain was read for the tools")
            return "key"
        }
        #expect(choice == .tools)
    }

    @Test func theAPIChoiceCarriesItsEndpointOrNothingWhenIncomplete() {
        let complete = AIAnswer.choice(source: .api, baseURL: "https://api.test/v1", model: "small") { "key" }
        #expect(complete == .api(AIEndpoint(baseURL: "https://api.test/v1", model: "small", apiKey: "key")))
        #expect(AIAnswer.choice(source: .api, baseURL: "https://api.test/v1", model: "small") { nil } == .api(nil))
        #expect(AIAnswer.incompleteMessage.contains("Settings"))
    }
}
