//
//  HostRequest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Something an extension asks the app for and waits on: the host sends `request` with an id, a
/// method and its parameters, and the app sends back `reply` with the same id and a result or an error.
enum HostRequest: Sendable, Equatable {
    /// `AI.ask`: one prompt, one answer.
    case askAI(prompt: String, model: String?)
    /// `OAuth.PKCEClient.authorize`: the provider's page, opened in the browser.
    case oauthAuthorize(url: String, state: String, providerName: String)
    /// `OAuth.PKCEClient.getTokens`: the stored tokens, if the extension signed in before.
    case oauthGetTokens(providerId: String)
    /// `OAuth.PKCEClient.setTokens`: what the provider answered the authorization code with.
    case oauthSetTokens(providerId: String, tokens: [String: Any])
    /// `OAuth.PKCEClient.removeTokens`.
    case oauthRemoveTokens(providerId: String)

    /// Whether the OAuth broker answers this rather than `answer`.
    var isOAuth: Bool {
        switch self {
        case .oauthAuthorize, .oauthGetTokens, .oauthSetTokens, .oauthRemoveTokens:
            true
        case .askAI, .selectedText, .selectedFinderItems, .clipboardRead:
            false
        }
    }

    /// `getSelectedText`: the frontmost app's selected text.
    case selectedText
    /// `getSelectedFinderItems`: the Finder's selection, when Finder is frontmost.
    case selectedFinderItems
    /// `Clipboard.read`: the pasteboard as text, HTML and file.
    case clipboardRead

    /// Nil for a method the app doesn't know, or one whose parameters are missing.
    init?(method: String, params: [String: Any]) {
        switch method {
        case "ai.ask":
            guard let prompt = params["prompt"] as? String else { return nil }
            self = .askAI(prompt: prompt, model: params["model"] as? String)
        case "oauth.authorize":
            guard let url = params["url"] as? String,
                  let state = params["state"] as? String,
                  let providerName = params["providerName"] as? String
            else { return nil }
            self = .oauthAuthorize(url: url, state: state, providerName: providerName)
        case "oauth.getTokens":
            guard let providerId = params["providerId"] as? String else { return nil }
            self = .oauthGetTokens(providerId: providerId)
        case "oauth.setTokens":
            guard let providerId = params["providerId"] as? String,
                  let tokens = params["tokens"] as? [String: Any]
            else { return nil }
            self = .oauthSetTokens(providerId: providerId, tokens: tokens)
        case "oauth.removeTokens":
            guard let providerId = params["providerId"] as? String else { return nil }
            self = .oauthRemoveTokens(providerId: providerId)
        case "selectedText":
            self = .selectedText
        case "selectedFinderItems":
            self = .selectedFinderItems
        case "clipboard.read":
            self = .clipboardRead
        default:
            return nil
        }
    }

    static func == (lhs: HostRequest, rhs: HostRequest) -> Bool {
        switch (lhs, rhs) {
        case let (.askAI(prompt1, model1), .askAI(prompt2, model2)):
            prompt1 == prompt2 && model1 == model2
        case let (.oauthAuthorize(url1, state1, provider1), .oauthAuthorize(url2, state2, provider2)):
            url1 == url2 && state1 == state2 && provider1 == provider2
        case let (.oauthGetTokens(first), .oauthGetTokens(second)):
            first == second
        case let (.oauthSetTokens(firstId, firstTokens), .oauthSetTokens(secondId, secondTokens)):
            firstId == secondId && NSDictionary(dictionary: firstTokens).isEqual(to: secondTokens)
        case let (.oauthRemoveTokens(first), .oauthRemoveTokens(second)):
            first == second
        default:
            false
        }
    }

    /// Answers a request with the real system: the user's settings, the login shell's environment
    /// and the installed tools. Text that arrives before the whole answer goes to `emit`.
    @Sendable
    static func answer(_ request: HostRequest, emit: @Sendable (String) async -> Void) async throws -> Any {
        switch request {
        case let .askAI(prompt, model):
            // The one place a prompt is answered, for an extension and for Ask AI (see AISources.swift).
            let asking = AIAnswer.askingExtension
            let (choice, localOnly) = await MainActor.run { (AIAnswer.configured(for: asking), AppSettings.shared.aiOnThisMacOnly) }
            return try await AIAnswer.answer(prompt, model: model, choice: choice, localOnly: localOnly, emit: emit)
        case .oauthAuthorize, .oauthGetTokens, .oauthSetTokens, .oauthRemoveTokens:
            // Answered by the OAuth broker, through the same reply channel (see Session+Requests.swift).
            throw OAuthError.unknownRequest
        case .selectedText:
            return try await SelectedText.current()
        case .selectedFinderItems:
            return try await MainActor.run { try FinderSelection.current() }
        case .clipboardRead:
            return await MainActor.run { PasteboardContent.read() }
        }
    }
}

/// What the user chose to answer `AI.ask` with.
enum AISource: String, Codable, CaseIterable {
    /// The claude or codex command line tool, on the account it is signed in to.
    case tools
    /// An OpenAI-compatible API, with the user's own key.
    case api
    /// The model macOS runs on this Mac.
    case appleIntelligence
}

/// The services Settings fills the API's address in for; anything else is typed by hand.
enum AIService: String, CaseIterable, Identifiable {
    case openAI
    case openRouter
    case ollama
    case lmStudio
    case other

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama, on this Mac"
        case .lmStudio: "LM Studio, on this Mac"
        case .other: "Another address"
        }
    }

    /// The address the service answers at; nil for one the user types.
    var baseURL: String? {
        switch self {
        case .openAI: AIEndpoint.defaultBaseURL
        case .openRouter: "https://openrouter.ai/api/v1"
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .other: nil
        }
    }

    /// The service an address belongs to, so the picker shows what was chosen without storing it.
    static func matching(_ baseURL: String) -> AIService {
        let chat = AIEndpoint.chatURL(baseURL: baseURL)
        return allCases.first { service in
            service.baseURL.flatMap { AIEndpoint.chatURL(baseURL: $0) } == chat && chat != nil
        } ?? .other
    }
}

/// Where an OpenAI-compatible API is, what to ask it for, and the key it takes.
struct AIEndpoint: Equatable, Sendable {
    static let defaultBaseURL = "https://api.openai.com/v1"
    /// The key's Keychain account. Extension secrets are "<extension>/<field>", and no extension is named "floe.ai".
    static let keychainAccount = "floe.ai/apiKey"

    let chatURL: URL
    let model: String
    let apiKey: String

    /// Whether an address is a server on this Mac. Everything that asks "local or remote" asks here.
    static func isOnThisMac(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    /// A server on this Mac, such as Ollama or LM Studio, takes requests without a key.
    static func needsKey(_ url: URL?) -> Bool {
        !isOnThisMac(url)
    }

    /// Nil until the address and the model are filled in, and the key where the server asks for one.
    init?(baseURL: String, model: String, apiKey: String?) {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chatURL = Self.chatURL(baseURL: baseURL), !model.isEmpty else { return nil }
        guard !apiKey.isEmpty || !Self.needsKey(chatURL) else { return nil }
        self.chatURL = chatURL
        self.model = model
        self.apiKey = apiKey
    }

    /// What an incomplete setup still needs, as one sentence for Settings; nil when it is complete.
    static func problem(baseURL: String, model: String, apiKey: String?) -> String? {
        var needs: [String] = []
        if chatURL(baseURL: baseURL) == nil {
            needs.append("an address that starts with http:// or https://")
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            needs.append("a model")
        }
        if needsKey(chatURL(baseURL: baseURL)), (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            needs.append("an API key")
        }
        guard let last = needs.popLast() else { return nil }
        let list = needs.isEmpty ? last : "\(needs.joined(separator: ", ")) and \(last)"
        return "AI can't answer yet. It needs \(list)."
    }

    /// The chat completions address under a base address like "https://api.openai.com/v1". An
    /// empty address means OpenAI's, and one that already ends in the path is taken as it is.
    static func chatURL(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = defaultBaseURL
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        let path = "/chat/completions"
        guard let url = URL(string: base.hasSuffix(path) ? base : base + path),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        return url
    }
}

/// The choice in Settings › General › AI, read where a request is answered.
enum AIAnswer {
    static let incompleteMessage = "AI is set to use an API, but its address, model or key is missing. Fill them in under Settings › General › AI."

    enum Choice: Equatable {
        case tools
        /// Nil when the API's settings are incomplete.
        case api(AIEndpoint?)
        case appleIntelligence
    }

    /// `key` reads the stored API key; it is only called when the API is the choice, so the
    /// Keychain is left alone otherwise.
    static func choice(source: AISource, baseURL: String, model: String, key: () -> String?) -> Choice {
        switch source {
        case .tools: .tools
        case .api: .api(AIEndpoint(baseURL: baseURL, model: model, apiKey: key()))
        case .appleIntelligence: .appleIntelligence
        }
    }

    static func configured(_ settings: AppSettings = .shared) -> Choice {
        choice(source: settings.aiSource, baseURL: settings.aiBaseURL, model: settings.aiModel) {
            Keychain.read(account: AIEndpoint.keychainAccount)
        }
    }

    /// Whether extensions should be told AI is there: a tool is installed, the API is filled in, or the Mac's own
    /// model is ready, and the source is not one the "only on this Mac" switch refuses.
    static var isAvailable: Bool {
        isAvailable(
            choice: configured(),
            localOnly: AppSettings.shared.aiOnThisMacOnly,
            toolInstalled: { AIEngine.isAvailable },
            appleIntelligenceReady: { AppleIntelligence.problem == nil }
        )
    }
}

/// Which command line tool answers `AI.ask`. Floe has no models of its own: it uses the Claude or
/// Codex tool the user has installed and signed in to.
enum AIEngine {
    static let missingMessage = "AI needs the claude or codex command line tool, installed and signed in."

    /// Whether extensions should be told AI is there. The tools are looked up on the PATH known so far.
    static var isAvailable: Bool {
        resolve(model: nil, which: { LoginEnvironment.which($0) }) != nil
    }

    /// Claude answers unless the extension asked for an OpenAI model and Codex is installed.
    /// `which` finds a tool by name, so a test can say what is installed.
    static func resolve(model: String?, which: (String) -> URL?) -> TextGeneration.Engine? {
        let claude = which("claude").map { TextGeneration.Engine.claude(executable: $0, model: claudeModel(for: model)) }
        // Codex keeps the model the user configured: Raycast's names for OpenAI models are not Codex's.
        let codex = which("codex").map { TextGeneration.Engine.codex(executable: $0, model: nil) }
        return asksForOpenAI(model) ? codex ?? claude : claude ?? codex
    }

    /// The Claude alias inside one of Raycast's model names ("Anthropic_Claude_Sonnet" gives "sonnet"),
    /// or nil to leave the choice to the engine.
    static func claudeModel(for requested: String?) -> String? {
        guard let name = requested?.lowercased() else { return nil }
        return ["opus", "sonnet", "haiku"].first { name.contains($0) }
    }

    private static func asksForOpenAI(_ model: String?) -> Bool {
        guard let name = model?.lowercased() else { return false }
        return name.contains("openai") || name.contains("gpt")
    }
}
