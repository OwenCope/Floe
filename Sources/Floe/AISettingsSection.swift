//
//  AISettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// General's AI section: what answers an extension's `AI.ask`.
struct AISettingsSection: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKey: String

    /// `storedKey` is the Keychain's unless a snapshot passes its own.
    init(settings: AppSettings, storedKey: String? = Keychain.read(account: AIEndpoint.keychainAccount)) {
        self.settings = settings
        _apiKey = State(initialValue: storedKey ?? "")
    }

    var body: some View {
        ThawSection("AI") {
            Picker(selection: $settings.aiSource) {
                Text("The claude or codex tool").tag(AISource.tools)
                Text("An OpenAI-compatible API").tag(AISource.api)
            } label: {
                Text("Answer AI requests with")
                Text("Extensions that ask AI a question get their answer from here.")
            }
            switch settings.aiSource {
            case .tools:
                if let engine = AIEngine.resolve(model: nil, which: { LoginEnvironment.which($0) }) {
                    LabeledContent("Tool") {
                        Text(engine.executable.path).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else {
                    warning("AI can't answer yet. Install claude or codex and sign in.")
                }
            case .api:
                TextField("Address", text: $settings.aiBaseURL, prompt: Text(AIEndpoint.defaultBaseURL))
                TextField("Model", text: $settings.aiModel, prompt: Text("The model's name, as the API lists it"))
                SecureField("API key", text: $apiKey, prompt: Text("Kept in the Keychain"))
                    .onChange(of: apiKey) { _, key in
                        if key.isEmpty {
                            Keychain.delete(account: AIEndpoint.keychainAccount)
                        } else {
                            Keychain.write(key, account: AIEndpoint.keychainAccount)
                        }
                    }
                if let problem = AIEndpoint.problem(baseURL: settings.aiBaseURL, model: settings.aiModel, apiKey: apiKey) {
                    warning(problem)
                }
            }
        }
    }

    /// The text stays in the label color, which red body text does not match for contrast; the symbol carries the red.
    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
