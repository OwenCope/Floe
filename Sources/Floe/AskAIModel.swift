//
//  AskAIModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One question and its answer, for as long as the answer view is on screen. There is no history:
/// nothing here is written anywhere, and leaving the view drops the text.
final class AskAIModel: ObservableObject {
    /// Answers a prompt, handing over text as it arrives, and returns the whole answer.
    typealias Request = @Sendable (String, @Sendable (String) async -> Void) async throws -> String

    enum State: Equatable {
        /// Sent, and nothing has come back yet.
        case asking
        /// Text is arriving.
        case answering
        case finished
        /// The source's own words for why there is no answer.
        case failed(String)
        /// The view was left before the answer was complete, or after it.
        case cancelled
    }

    /// A request to scroll the answer, made by the arrow keys. `id` tells two equal steps apart.
    struct Scroll: Equatable {
        var id = 0
        var lines = 0
    }

    let question: String
    let source: AskAI.Source?
    @Published private(set) var state = State.asking
    @Published private(set) var answer = ""
    @Published private(set) var scroll = Scroll()

    private let request: Request
    private var task: Task<Void, Never>?
    /// Bumped per request, so text from one that was replaced or left is dropped.
    private var generation = 0

    /// The one way a prompt is answered, shared with an extension's `AI.ask`.
    static let live: Request = { prompt, emit in
        try await HostRequest.answer(.askAI(prompt: prompt, model: nil), emit: emit) as? String ?? ""
    }

    init(question: String, source: AskAI.Source?, request: @escaping Request = AskAIModel.live) {
        self.question = question
        self.source = source
        self.request = request
    }

    var isWorking: Bool {
        state == .asking || state == .answering
    }

    /// Sends the question, replacing any request still in flight. The task is returned so a test can wait for it.
    @discardableResult
    func ask() -> Task<Void, Never> {
        task?.cancel()
        generation += 1
        let started = generation
        answer = ""
        state = .asking
        let request = request
        let question = question
        let task = Task { @MainActor [weak self] in
            do {
                let whole = try await request(question) { [weak self] text in
                    await MainActor.run { [weak self] in self?.receive(text, generation: started) }
                }
                self?.finish(.success(whole), generation: started)
            } catch {
                self?.finish(.failure(error), generation: started)
            }
        }
        self.task = task
        return task
    }

    /// Stops the request and forgets the answer. Called when the view is left or the panel hides.
    func leave() {
        generation += 1
        task?.cancel()
        task = nil
        answer = ""
        state = .cancelled
    }

    func scroll(by lines: Int) {
        scroll = Scroll(id: scroll.id + 1, lines: lines)
    }

    private func receive(_ text: String, generation started: Int) {
        guard started == generation else { return }
        answer += text
        state = .answering
    }

    private func finish(_ result: Result<String, Error>, generation started: Int) {
        guard started == generation else { return }
        task = nil
        switch result {
        case let .success(whole):
            // A source that does not stream hands over everything here.
            if !whole.isEmpty {
                answer = whole
            }
            state = .finished
        case let .failure(error):
            state = .failed(error.localizedDescription)
        }
    }

    deinit {
        task?.cancel()
    }
}
