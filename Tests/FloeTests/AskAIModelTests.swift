//
//  AskAIModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Synchronization
import Testing

/// Stands in for an AI source: it answers only when the test lets it, and notes what it was asked.
private final class FakeSource: Sendable {
    private struct State {
        var prompts: [String] = []
        var cancellations = 0
        var gates: [AsyncStream<Void>.Continuation] = []
    }

    private let state = Mutex(State())
    /// Sent before the gate, as a source that streams does.
    let early: [String]
    let result: Result<String, ProviderError>

    init(early: [String] = [], result: Result<String, ProviderError> = .success("")) {
        self.early = early
        self.result = result
    }

    var prompts: [String] {
        state.withLock { $0.prompts }
    }

    var cancellations: Int {
        state.withLock { $0.cancellations }
    }

    var request: AskAIModel.Request {
        { [self] prompt, emit in
            let (gate, opener) = AsyncStream.makeStream(of: Void.self)
            state.withLock {
                $0.prompts.append(prompt)
                $0.gates.append(opener)
            }
            for text in early {
                await emit(text)
            }
            for await _ in gate {
                break
            }
            if Task.isCancelled {
                state.withLock { $0.cancellations += 1 }
                throw CancellationError()
            }
            return try result.get()
        }
    }

    /// Lets every request waiting at the gate go on to its result.
    func open() {
        state.withLock { $0.gates }.forEach { $0.yield() }
    }
}

@MainActor
struct AskAIModelTests {
    private let scratch: ScratchDefaults
    private let source = AskAI.Source(line: "Apple Intelligence, on this Mac", isOnThisMac: true)

    init() throws {
        scratch = try ScratchDefaults()
    }

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 2000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    private func makeLauncher(_ fake: FakeSource, usage: UsageStore? = nil) -> LauncherModel {
        let model = LauncherModel(
            settings: AppSettings(defaults: scratch.defaults),
            usage: usage ?? UsageStore(defaults: scratch.defaults),
            snapshot: CatalogSnapshot(apps: [], commands: []),
            scopes: []
        )
        model.canAskAI = { true }
        model.askAIRequest = fake.request
        return model
    }

    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    // MARK: The answer's states

    @Test func aQuestionIsAskingUntilTextArrivesThenAnsweringThenFinished() async {
        let fake = FakeSource(early: ["Because ", "of Rayleigh"], result: .success("Because of Rayleigh scattering."))
        let asking = AskAIModel(question: "why is the sky blue", source: source, request: fake.request)
        let task = asking.ask()
        #expect(asking.state == .asking)
        #expect(asking.answer.isEmpty)
        #expect(asking.isWorking)

        await waitFor("the streamed text") { asking.answer == "Because of Rayleigh" }
        #expect(asking.state == .answering)
        #expect(asking.isWorking)

        fake.open()
        await task.value
        #expect(asking.state == .finished)
        #expect(asking.answer == "Because of Rayleigh scattering.", "the whole answer replaces what was streamed")
        #expect(!asking.isWorking)
        #expect(fake.prompts == ["why is the sky blue"])
    }

    @Test func aSourceThatDoesNotStreamShowsItsAnswerWhole() async {
        let fake = FakeSource(result: .success("# Whole\n\nAt once."))
        let asking = AskAIModel(question: "q", source: source, request: fake.request)
        let task = asking.ask()
        await waitFor("the request") { fake.prompts.count == 1 }
        #expect(asking.state == .asking, "nothing has arrived, so the view still says it is waiting")
        fake.open()
        await task.value
        #expect(asking.state == .finished)
        #expect(asking.answer == "# Whole\n\nAt once.")
    }

    @Test func aFailureShowsTheSourcesOwnWords() async {
        let fake = FakeSource(result: .failure(.failed(AIAnswer.incompleteMessage)))
        let asking = AskAIModel(question: "q", source: nil, request: fake.request)
        let task = asking.ask()
        await waitFor("the request") { fake.prompts.count == 1 }
        fake.open()
        await task.value
        #expect(asking.state == .failed(AIAnswer.incompleteMessage))
        #expect(asking.answer.isEmpty)
        #expect(!asking.isWorking)
    }

    @Test func askingAgainStartsOverAndDropsTheFirstRequest() async {
        let fake = FakeSource(early: ["first"], result: .success("done"))
        let asking = AskAIModel(question: "q", source: source, request: fake.request)
        asking.ask()
        await waitFor("the first text") { asking.answer == "first" }
        let second = asking.ask()
        #expect(asking.state == .asking)
        #expect(asking.answer.isEmpty, "the first answer is cleared at once")
        await waitFor("the second request") { fake.prompts.count == 2 }
        await waitFor("the first request to be cancelled") { fake.cancellations == 1 }
        fake.open()
        await second.value
        #expect(asking.state == .finished)
        #expect(asking.answer == "done")
    }

    @Test func leavingCancelsTheRequestAndForgetsTheAnswer() async {
        let fake = FakeSource(early: ["partial"], result: .success("never shown"))
        let asking = AskAIModel(question: "q", source: source, request: fake.request)
        let task = asking.ask()
        await waitFor("the first text") { asking.answer == "partial" }
        asking.leave()
        #expect(asking.state == .cancelled)
        #expect(asking.answer.isEmpty)
        await task.value
        #expect(fake.cancellations == 1, "the request in flight was told to stop")
        #expect(asking.state == .cancelled, "a late result changes nothing")
        #expect(asking.answer.isEmpty)
    }

    // MARK: In the launcher

    @Test func returnOnTheRowReplacesTheListWithTheAnswerAndEscapeGoesBackWithTheQuery() async throws {
        let fake = FakeSource(result: .success("42"))
        let model = makeLauncher(fake)
        model.query = "ask the answer"
        #expect(model.results.first?.item.title == "Ask AI \u{201C}the answer\u{201D}")
        #expect(try model.handleKey(key(36)))
        let asking = try #require(model.askAI)
        #expect(asking.question == "the answer")
        #expect(!model.panelState.isRootSearch)
        await waitFor("the request") { fake.prompts == ["the answer"] }

        #expect(try model.handleKey(key(53)))
        #expect(model.askAI == nil)
        #expect(model.query == "ask the answer", "the search is as it was left")
        #expect(model.panelState.isRootSearch)
        #expect(asking.state == .cancelled)
        await waitFor("the cancellation") { fake.cancellations == 1 }
    }

    @Test func hidingThePanelCancelsARequestInFlight() async {
        let fake = FakeSource(early: ["par"], result: .success("partial"))
        let model = makeLauncher(fake)
        model.query = "why"
        model.openAskAI("why")
        let asking = model.askAI
        await waitFor("the first text") { asking?.answer == "par" }
        model.panelDidHide()
        #expect(model.askAI == nil)
        #expect(asking?.state == .cancelled)
        #expect(asking?.answer.isEmpty == true)
        await waitFor("the cancellation") { fake.cancellations == 1 }
    }

    @Test func theRowIsNotOfferedByAModelThatCannotAsk() {
        let model = makeLauncher(FakeSource())
        model.canAskAI = { false }
        model.query = "ask why"
        #expect(!model.results.contains { $0.id == "ask-ai" })
    }

    @Test func nothingAboutAQuestionIsStoredOnceTheViewIsLeft() async throws {
        let fake = FakeSource(early: ["a secret answer"], result: .success("a secret answer"))
        let usage = UsageStore(defaults: scratch.defaults)
        let model = makeLauncher(fake, usage: usage)
        model.query = "ask a secret question"
        let row = try #require(model.results.first?.item)
        model.activate(row)
        let asking = try #require(model.askAI)
        await waitFor("the request") { fake.prompts == ["a secret question"] }
        fake.open()
        await waitFor("the answer") { asking.state == .finished }
        // Command-Shift-F on the row would favorite anything else.
        model.toggleFavorite(row)
        model.closeAskAI()
        model.settings.save()

        #expect(model.askAI == nil)
        #expect(asking.answer.isEmpty)
        #expect(usage.records.isEmpty, "opening the row leaves no usage record")
        #expect(model.settings.favorites.isEmpty)
        let stored = scratch.defaults.persistentDomain(forName: scratch.name) ?? [:]
        #expect(stored.keys.contains("settings"), "the settings were saved, so there is something to look through")
        let text = stored.values.map { value in
            (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: value)
        }.joined()
        #expect(!text.contains("secret"), "neither the question nor the answer is in what Floe saves")
    }

    // MARK: Keys and actions

    @Test func theActionsAreCopyPasteAndAskAgainOnceThereIsAnAnswer() async {
        let fake = FakeSource(result: .success("an answer"))
        let model = makeLauncher(fake)
        #expect(model.askAIActions().isEmpty, "there is no menu without the view")
        model.openAskAI("q")
        #expect(model.askAIActions().compactMap { $0?.title } == ["Ask Again"], "nothing to copy while waiting")
        await waitFor("the request") { fake.prompts.count == 1 }
        fake.open()
        await waitFor("the answer") { model.askAI?.state == .finished }
        #expect(model.askAIActions().compactMap { $0?.title } == ["Copy Answer", "Paste Answer", "Ask Again"])
    }

    @Test func commandRAndTheMenuAskAgain() async throws {
        let fake = FakeSource(result: .success("an answer"))
        let model = makeLauncher(fake)
        model.openAskAI("q")
        await waitFor("the first request") { fake.prompts.count == 1 }
        #expect(try model.handleKey(key(15, .command)))
        await waitFor("the second request") { fake.prompts.count == 2 }
        model.askAIActions().compactMap(\.self).last?.run()
        await waitFor("the third request") { fake.prompts.count == 3 }
        #expect(fake.prompts == ["q", "q", "q"])
        model.closeAskAI()
    }

    @Test func returnAsksAFailedQuestionAgain() async throws {
        let fake = FakeSource(result: .failure(.failed("No.")))
        let model = makeLauncher(fake)
        model.openAskAI("q")
        await waitFor("the request") { fake.prompts.count == 1 }
        fake.open()
        await waitFor("the failure") { model.askAI?.state == .failed("No.") }
        #expect(try model.handleKey(key(36)))
        #expect(model.askAI?.state == .asking)
        await waitFor("the second request") { fake.prompts.count == 2 }
        model.closeAskAI()
    }

    @Test func theArrowsScrollTheAnswerAndPlainTypingGoesNowhere() throws {
        let model = makeLauncher(FakeSource())
        model.query = "why"
        model.openAskAI("why")
        #expect(try model.handleKey(key(125)))
        #expect(model.askAI?.scroll == AskAIModel.Scroll(id: 1, lines: 1))
        #expect(try model.handleKey(key(126)))
        #expect(model.askAI?.scroll == AskAIModel.Scroll(id: 2, lines: -1))
        #expect(try model.handleKey(key(0)), "a letter has no field to land in")
        #expect(try !model.handleKey(key(8, .command)), "Command-C is left to the selected text")
        #expect(model.query == "why")
        model.closeAskAI()
    }

    @Test func thePanelStateCountsTheAnswerViewAsNotTheRootSearch() {
        let state = LauncherPanelState(
            showingSetup: false, showingCommand: false, menuBarSearch: false, clipboardHistory: false,
            fileSearch: false, queryIsEmpty: true, askingAI: true
        )
        #expect(!state.isRootSearch)
        #expect(!state.isCollapsed(in: .compact), "the answer keeps the full panel in the compact layout")
        #expect(state.contentSize(in: .compact) == LauncherPanelState.fullSize)
    }
}
