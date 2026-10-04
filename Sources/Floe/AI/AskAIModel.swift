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
    /// Parses the answer so far, away from the main actor. It is handed what is shown, to keep the blocks that did not change.
    typealias Parse = @Sendable (String, MarkdownContent) async -> MarkdownContent
    /// Waits out the time between two updates of an answer that is streaming.
    typealias Pause = @Sendable () async -> Void

    /// Twelve updates a second still read as text arriving, and a source sends several tokens in that time.
    static let batchInterval = Duration.milliseconds(80)

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
    /// Everything received so far, for copy and paste. Not published: the view draws `shown`.
    private(set) var answer = ""
    /// The answer as it is drawn: parsed, and at most one batch behind `answer` while it streams.
    @Published private(set) var shown = MarkdownContent.empty
    @Published private(set) var scroll = Scroll()

    private let request: Request
    private let parse: Parse
    private let pause: Pause
    private var task: Task<Void, Never>?
    /// Draws the text of a streaming answer in batches; nil when everything received is shown.
    /// Readable so a test can wait for it.
    private(set) var showing: Task<Void, Never>?
    /// Counts the parses started, so the result of an older one is dropped when it lands late.
    private var revision = 0
    /// Bumped per request, so text from one that was replaced or left is dropped.
    private var generation = 0

    /// The one way a prompt is answered, shared with an extension's `AI.ask`.
    static let live: Request = { prompt, emit in
        try await HostRequest.answer(.askAI(prompt: prompt, model: nil), emit: emit) as? String ?? ""
    }

    init(
        question: String,
        source: AskAI.Source?,
        request: @escaping Request = AskAIModel.live,
        parse: @escaping Parse = { await MarkdownContent.parsed($0, reusing: $1) },
        pause: @escaping Pause = { try? await Task.sleep(for: AskAIModel.batchInterval) }
    ) {
        self.question = question
        self.source = source
        self.request = request
        self.parse = parse
        self.pause = pause
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
        clear()
        state = .asking
        let request = request
        let question = question
        let task = Task { @MainActor [weak self] in
            let result: Result<String, Error>
            do {
                result = try await .success(request(question) { [weak self] text in
                    await MainActor.run { [weak self] in self?.receive(text, generation: started) }
                })
            } catch {
                result = .failure(error)
            }
            await self?.finish(result, generation: started)
        }
        self.task = task
        return task
    }

    /// Stops the request and forgets the answer. Called when the view is left or the panel hides.
    func leave() {
        generation += 1
        task?.cancel()
        task = nil
        clear()
        state = .cancelled
    }

    /// Forgets the text and stops drawing it. A parse still running is for an older generation, and is dropped.
    private func clear() {
        showing?.cancel()
        showing = nil
        answer = ""
        shown = .empty
    }

    func scroll(by lines: Int) {
        scroll = Scroll(id: scroll.id + 1, lines: lines)
    }

    private func receive(_ text: String, generation started: Int) {
        guard started == generation else { return }
        answer += text
        // Published once, not per token: every change here evaluates the view again.
        if state != .answering {
            state = .answering
        }
        show(generation: started)
    }

    /// Draws what has arrived and then waits, for as long as text keeps arriving: one parse per interval,
    /// however many tokens came in it. The first text is drawn at once.
    private func show(generation started: Int) {
        guard showing == nil else { return }
        showing = Task { @MainActor [weak self, parse, pause] in
            while !Task.isCancelled, let next = self?.nextToShow(generation: started) {
                let content = await parse(next.text, next.shown)
                guard self?.apply(content, revision: next.revision, generation: started) == true else { return }
                await pause()
            }
        }
    }

    /// The text to parse next, or nil when all of it is shown, which ends the batch loop.
    private func nextToShow(generation started: Int) -> (text: String, shown: MarkdownContent, revision: Int)? {
        guard started == generation else { return nil }
        guard answer != shown.text else {
            showing = nil
            return nil
        }
        revision += 1
        return (answer, shown, revision)
    }

    /// False when the parse is stale: the request was replaced or left, or a newer parse has started since.
    private func apply(_ content: MarkdownContent, revision parsed: Int, generation started: Int) -> Bool {
        guard started == generation, parsed == revision else { return false }
        shown = content
        return true
    }

    private func finish(_ result: Result<String, Error>, generation started: Int) async {
        guard started == generation else { return }
        // A source that does not stream hands over everything here.
        if case let .success(whole) = result, !whole.isEmpty {
            answer = whole
        }
        showing?.cancel()
        showing = nil
        // The whole text is drawn before the state changes, so nothing reads as finished over part of an answer.
        if answer != shown.text {
            revision += 1
            let content = await parse(answer, shown)
            guard started == generation else { return }
            shown = content
        }
        task = nil
        switch result {
        case .success:
            state = .finished
        case let .failure(error):
            state = .failed(error.localizedDescription)
        }
    }

    deinit {
        task?.cancel()
        showing?.cancel()
    }
}
