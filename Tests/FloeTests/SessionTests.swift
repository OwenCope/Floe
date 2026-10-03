//
//  SessionTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

@testable import Floe
import Foundation
import Testing

/// Drives a session with the messages a host would send, without starting a process.
struct ExtensionSessionTests {
    /// What the session sent to the host and handed back to the model.
    private final class Recorder {
        var sent: [[String: Any]] = []
        var forwarded: [[String: Any]] = []

        func sentEvents(_ prop: String) -> [[String: Any]] {
            sent.filter { $0["type"] as? String == "event" && $0["prop"] as? String == prop }
        }
    }

    private let session = ExtensionSession(command: Fixture.command("planets"), arguments: ["text": "hi"])
    private let recorder = Recorder()

    init() {
        session.transport = { [recorder] in recorder.sent.append($0) }
        session.onMessage = { [recorder] in recorder.forwarded.append($0) }
    }

    private func render(_ view: [String: Any], screenID: Int = 50) {
        let tree = Fixture.node("root", id: 0, children: [Fixture.node("_screen", id: screenID, children: [view])])
        session.handle(["type": "render", "tree": tree])
    }

    private var planets: [String: Any] {
        Fixture.node("List", id: 60, children: [
            Fixture.item("Mercury", id: 1, actions: [Fixture.action("Show", id: 11), Fixture.action("Copy", id: 12)]),
            Fixture.item("Venus", id: 2, actions: [
                Fixture.action("Show", id: 21),
                Fixture.node("ActionPanel.Submenu", id: 22, props: ["title": "More"], handlers: ["onOpen"], children: [Fixture.action("Inner", id: 23)]),
            ]),
            Fixture.item("Mars", id: 3),
        ])
    }

    // MARK: Rendering

    @Test func keepsItsCommandAndArguments() {
        #expect(session.command.id == "sample/planets")
        #expect(session.arguments["text"] as? String == "hi")
        #expect(session.view == nil)
        #expect(session.rows.isEmpty)
    }

    @Test func aRenderShowsTheViewAndItsRows() {
        render(planets)
        #expect(session.view?.id == 60)
        #expect(session.isList)
        #expect(session.rows.map(\.id) == [1, 2, 3])
        #expect(session.selectedRow?.id == 1)
        #expect(session.actions.map(\.id) == [11, 12])
    }

    @Test func typingFiltersRowsAndResetsTheSelection() {
        render(planets)
        session.selection = 2
        session.searchText = "ma"
        #expect(session.rows.map(\.id) == [3])
        #expect(session.selection == 0)
        #expect(recorder.sent.isEmpty, "a list that filters itself does not ask the extension")
    }

    @Test func typingIsSentToAListThatHandlesSearchItself() {
        render(Fixture.node("List", id: 61, handlers: ["onSearchTextChange"], children: [Fixture.item("Mercury", id: 1)]))
        session.searchText = "swift"
        session.searchText = "swift"
        let events = recorder.sentEvents("onSearchTextChange")
        #expect(events.count == 1, "the same text is not sent twice")
        #expect(events.first?["id"] as? Int == 61)
        #expect(events.first?["args"] as? [String] == ["swift"])
    }

    @Test func aNewScreenClearsTheSearchSelectionAndFormWithoutTellingTheExtension() {
        render(Fixture.node("List", id: 61, handlers: ["onSearchTextChange"], children: [Fixture.item("A", id: 1), Fixture.item("B", id: 2)]))
        session.searchText = "b"
        session.selection = 1
        session.formValues = ["subject": "typed"]
        session.actionMenuOpen = true
        recorder.sent.removeAll()

        render(Fixture.node("Detail", id: 70), screenID: 51)
        #expect(session.searchText.isEmpty)
        #expect(session.selection == 0)
        #expect(session.formValues.isEmpty)
        #expect(session.actionMenuOpen == false)
        #expect(recorder.sent.isEmpty, "clearing the field for a new screen is not a search")
    }

    @Test func aRerenderOfTheSameScreenKeepsWhatTheUserTyped() {
        render(planets)
        session.searchText = "m"
        session.selection = 1
        render(planets)
        #expect(session.searchText == "m")
        #expect(session.selection == 1)
    }

    @Test func messagesArriveSplitAcrossChunksAndSeveralPerChunk() throws {
        let first = try JSONSerialization.data(withJSONObject: ["type": "hud", "title": "Copied"])
        let second = try JSONSerialization.data(withJSONObject: ["type": "close"])
        var stream = first + Data("\n".utf8) + second + Data("\nnot json\n".utf8)
        let tail = stream.suffix(from: 10)
        stream = stream.prefix(10)

        session.receive(stream)
        #expect(recorder.forwarded.isEmpty, "nothing is handled until its line is complete")
        session.receive(Data(tail))
        #expect(recorder.forwarded.compactMap { $0["type"] as? String } == ["hud", "close"])
    }

    // MARK: Toasts and errors

    @Test func aToastIsShownAndHiddenByItsIdentifier() {
        session.handle(["type": "toast", "id": 4, "style": "animated", "title": "Loading", "message": "planets"])
        #expect(session.toast == ToastState(id: 4, style: "animated", title: "Loading", message: "planets"))
        session.handle(["type": "toast", "id": 9, "hidden": true])
        #expect(session.toast?.id == 4, "hiding another toast leaves this one")
        session.handle(["type": "toast", "id": 4, "hidden": true])
        #expect(session.toast == nil)
    }

    @Test func aToastWithoutDetailsGetsDefaults() {
        session.handle(["type": "toast"])
        #expect(session.toast == ToastState(id: 0, style: "success", title: "", message: nil))
    }

    @Test func aNonFatalErrorIsAFailureToastAndTheViewStays() {
        render(planets)
        session.handle(["type": "error", "message": "Request failed", "fatal": false])
        #expect(session.toast == ToastState(id: -1, style: "failure", title: "Extension error", message: "Request failed"))
        #expect(session.failure == nil)
        #expect(session.rows.count == 3)
    }

    @Test func aFatalErrorBecomesAFailureWithTheStackAndTheLog() {
        session.appendLog(Data("stderr line\n".utf8))
        session.handle(["type": "error", "message": "Render failed", "stack": "Error: Render failed\n  at Command", "fatal": true])
        #expect(session.failure?.kind == .error)
        #expect(session.failure?.message == "Render failed")
        #expect(session.failure?.details == "Error: Render failed\n  at Command\n\nstderr line\n")
    }

    @Test func anErrorWithoutAMessageStillSaysSomething() {
        session.handle(["type": "error", "fatal": true])
        #expect(session.failure?.message == "Unknown error")
        #expect(session.failure?.details.isEmpty == true)
    }

    @Test func theLogKeepsOnlyItsTail() {
        session.appendLog(Data(String(repeating: "a", count: 19000).utf8))
        session.appendLog(Data(String(repeating: "b", count: 2000).utf8))
        #expect(session.log.count == 16000)
        #expect(session.log.hasSuffix("bbbb"))
    }

    // MARK: Process outcome and watchdog

    @Test func aCleanExitIsForwardedAsExit() {
        session.processEnded(status: 0, wasSignalled: false)
        #expect(recorder.forwarded.compactMap { $0["type"] as? String } == ["exit"])
        #expect(session.failure == nil)
    }

    @Test(arguments: [(3, false, "exited with status 3"), (9, true, "was killed by signal 9")] as [(Int32, Bool, String)])
    func anythingElseIsACrash(status: Int32, wasSignalled: Bool, how: String) {
        session.appendLog(Data("last words".utf8))
        session.processEnded(status: status, wasSignalled: wasSignalled)
        #expect(session.failure?.kind == .crashed)
        #expect(session.failure?.message == "The extension stopped unexpectedly. It \(how).")
        #expect(session.failure?.details == "last words")
        #expect(recorder.forwarded.compactMap { $0["type"] as? String } == ["crashed"])
    }

    @Test func aProcessWeStoppedIsNotACrash() {
        session.isStopping = true
        session.processEnded(status: 15, wasSignalled: true)
        #expect(session.failure == nil)
        #expect(recorder.forwarded.isEmpty)
    }

    @Test func aCrashAfterAnErrorKeepsTheError() {
        session.handle(["type": "error", "message": "Render failed", "fatal": true])
        session.processEnded(status: 1, wasSignalled: false)
        #expect(session.failure?.kind == .error)
        #expect(recorder.forwarded.isEmpty)
    }

    @Test func theWatchdogPingsThenReportsAHostThatStopsAnswering() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        session.heartbeat(now: start)
        #expect(recorder.sent.compactMap { $0["type"] as? String } == ["ping"])

        session.heartbeat(now: start + 6)
        #expect(session.failure == nil, "still within the 8 seconds a ping may take")
        #expect(recorder.sent.count == 1, "no second ping while one is outstanding")

        session.heartbeat(now: start + 9)
        #expect(session.failure?.kind == .unresponsive)
    }

    @Test func aPongClearsTheWaitAndAnUnresponsiveFailure() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        session.heartbeat(now: start)
        session.heartbeat(now: start + 9)
        session.handle(["type": "pong"])
        #expect(session.failure == nil)
        #expect(session.pingSentAt == nil)

        session.heartbeat(now: start + 12)
        #expect(recorder.sent.count == 2, "pinging resumes")
    }

    @Test func aPongDoesNotClearAnErrorOrCrash() {
        session.handle(["type": "error", "message": "Render failed", "fatal": true])
        session.handle(["type": "pong"])
        #expect(session.failure?.kind == .error)
    }

    // MARK: Other messages

    @Test func clearSearchBarEmptiesTheField() {
        render(planets)
        session.searchText = "ma"
        session.handle(["type": "clearSearchBar"])
        #expect(session.searchText.isEmpty)
    }

    @Test(arguments: ["close", "exit", "popToRoot", "hud", "open", "copy", "paste", "openPreferences"])
    func messagesTheSessionDoesNotOwnGoToTheModel(type: String) {
        session.handle(["type": type, "title": "payload"])
        #expect(recorder.forwarded.count == 1)
        #expect(recorder.forwarded.first?["type"] as? String == type)
        #expect(recorder.forwarded.first?["title"] as? String == "payload")
    }

    // MARK: Actions

    @Test func runningAnActionSendsItsHandlerAndClosesTheMenu() {
        render(planets)
        session.actionMenuOpen = true
        session.run(session.actions[1])
        #expect(session.actionMenuOpen == false)
        #expect(recorder.sentEvents("onAction").first?["id"] as? Int == 12)
    }

    @Test func anActionWithoutAHandlerSendsNothing() {
        session.run(Fixture.tree(Fixture.node("Action", props: ["title": "Inert"])))
        #expect(recorder.sent.isEmpty)
    }

    @Test func submittingSendsTheFormsValues() throws {
        render(Fixture.node("Form", id: 80, children: [
            Fixture.slot("actions", Fixture.node("ActionPanel", children: [
                Fixture.node("Action", id: 81, props: ["title": "Send", "isSubmit": true], handlers: ["onSubmit"]),
            ])),
            Fixture.node("Form.TextField", id: 82, props: ["id": "subject"], handlers: ["onChange"]),
            Fixture.node("Form.DatePicker", id: 83, props: ["id": "due"], handlers: ["onChange"]),
            Fixture.node("Form.Checkbox", id: 84, props: ["id": "urgent"]),
        ]))
        let fields = try #require(session.view?.content)
        session.setFormValue(fields[0], "Crash")
        session.setFormValue(fields[1], "2026-10-09T00:00:00Z")
        session.setFormValue(fields[2], true)

        #expect(session.formValue(fields[0]) as? String == "Crash")
        let changes = recorder.sentEvents("onChange")
        #expect(changes.count == 2, "a field without onChange is not reported")
        #expect((changes[1]["args"] as? [[String: String]])?.first == ["$date": "2026-10-09T00:00:00Z"])

        session.run(session.actions[0])
        let submitted = try #require((recorder.sentEvents("onSubmit").first?["args"] as? [[String: Any]])?.first)
        #expect(submitted["subject"] as? String == "Crash")
        #expect(submitted["urgent"] as? Bool == true)
        #expect(submitted["due"] as? [String: String] == ["$date": "2026-10-09T00:00:00Z"])
    }

    @Test func aSubmitActionWithoutAHandlerOrAValueWithoutAFieldIdDoesNothing() {
        session.run(Fixture.tree(Fixture.node("Action", props: ["isSubmit": true])))
        session.setFormValue(Fixture.tree(Fixture.node("Form.Separator")), "x")
        #expect(recorder.sent.isEmpty)
        #expect(session.formValues.isEmpty)
    }

    // MARK: Selection and the action menu

    @Test func arrowKeysMoveTheListSelectionAndStopAtTheEnds() {
        render(planets)
        session.moveSelection(by: 1)
        #expect(session.selectedRow?.id == 2)
        session.moveSelection(by: 50)
        #expect(session.selection == 2)
        session.moveSelection(by: -50)
        #expect(session.selection == 0)
    }

    @Test func whileTheMenuIsOpenArrowsMoveWithinIt() {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        session.moveSelection(by: 5)
        #expect(session.actionSelection == 1)
        #expect(session.selection == 1, "the list selection does not move")
        #expect(session.menuEntries.map(\.id) == [21, 22])
    }

    @Test func enteringASubmenuTellsTheExtensionAndListsItsActions() {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        session.actionQuery = "mo"
        session.activateMenuEntry(at: 0)
        #expect(recorder.sentEvents("onAction").first?["id"] as? Int == nil, "the query matched no action, only the submenu's title")

        session.actionQuery = ""
        session.activateMenuEntry(at: 1)
        #expect(recorder.sentEvents("onOpen").first?["id"] as? Int == 22)
        #expect(session.actionPath.map(\.id) == [22])
        #expect(session.menuEntries.map(\.id) == [23])
        #expect(session.actionSelection == 0)

        session.activateMenuEntry(at: 0)
        #expect(recorder.sentEvents("onAction").first?["id"] as? Int == 23)
        #expect(session.actionMenuOpen == false)
        #expect(session.actionPath.isEmpty, "closing the menu leaves the submenu")
    }

    @Test func escapeClearsTheQueryThenLeavesTheSubmenuThenClosesTheMenu() throws {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        let submenu = try #require(session.menuEntries.first { $0.isSubmenu })
        session.openSubmenu(submenu.node)
        session.actionQuery = "inn"

        session.closeSubmenuOrMenu()
        #expect(session.actionQuery.isEmpty)
        #expect(session.actionPath.count == 1)
        session.closeSubmenuOrMenu()
        #expect(session.actionPath.isEmpty)
        #expect(session.actionMenuOpen)
        session.closeSubmenuOrMenu()
        #expect(session.actionMenuOpen == false)
    }

    @Test func anOpenSubmenuThatDisappearsFromTheTreeIsLeft() throws {
        render(planets)
        session.selection = 1
        session.actionMenuOpen = true
        let submenu = try #require(session.menuEntries.first { $0.isSubmenu })
        session.openSubmenu(submenu.node)

        render(planets)
        #expect(session.actionPath.count == 1, "still in the tree, so it stays open")

        render(Fixture.node("List", id: 60, children: [Fixture.item("Mercury", id: 1), Fixture.item("Venus", id: 2, actions: [Fixture.action("Show", id: 21)])]))
        #expect(session.actionPath.isEmpty)
    }

    @Test func activatingAnEntryThatIsNotThereDoesNothing() {
        render(planets)
        session.activateMenuEntry(at: 9)
        #expect(recorder.sent.isEmpty)
    }

    // MARK: Receive timings

    /// Opt-in samples (FLOE_PERF_REPORT=1) for how long the host's bytes take to frame, decode and
    /// apply through the session's receive path, which does all of that on one thread. The samples
    /// include the row recomputation, since the receive path cannot separate the two.
    @Test(.disabled(if: ProcessInfo.processInfo.environment["FLOE_PERF_REPORT"] == nil))
    func reportReceiveTimings() throws {
        for count in [1000, 10000] {
            let message = try JSONSerialization.data(withJSONObject: ["type": "render", "tree": Self.syntheticTree(count: count)]) + Data("\n".utf8)
            let chunks = stride(from: 0, to: message.count, by: 1024).map { start in
                message[start ..< min(start + 1024, message.count)]
            }
            var oneChunk: [Double] = []
            var inKibChunks: [Double] = []
            for _ in 0 ..< 5 {
                oneChunk.append(Self.milliseconds { session.receive(message) })
                #expect(session.rows.map(\.id) == Array(100 ..< 100 + count), "the whole tree is applied")
                inKibChunks.append(Self.milliseconds { for chunk in chunks {
                    session.receive(chunk)
                } })
                #expect(session.rows.map(\.id) == Array(100 ..< 100 + count), "chunks reassemble into the same tree")
            }
            Self.report("receive", items: count, oneChunk: oneChunk, inKibChunks: inKibChunks)
        }
    }

    private static func syntheticTree(count: Int) -> [String: Any] {
        Fixture.node("root", id: 0, children: [
            Fixture.node("_screen", id: 2, children: [
                Fixture.node("List", id: 3, children: (0 ..< count).map { index in
                    Fixture.item("Item \(index)", id: 100 + index, actions: [Fixture.action("Show", id: 100_000 + index)])
                }),
            ]),
        ])
    }

    private static func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now()
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private static func report(_ label: String, items: Int, oneChunk: [Double], inKibChunks: [Double]) {
        func format(_ samples: [Double]) -> String {
            samples.map { String(format: "%.2f", $0) }.joined(separator: ", ")
        }
        print("[perf] \(label) items=\(items) oneChunk(ms)=\(format(oneChunk)) kibChunks(ms)=\(format(inKibChunks))")
    }
}
