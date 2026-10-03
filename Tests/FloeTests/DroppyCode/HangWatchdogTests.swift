//
//  HangWatchdogTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// The thread, the ping and `sample` itself are not run here: a test would have to freeze the main thread.
struct HangWatchdogTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-hang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aSilenceShorterThanTheThresholdIsNotAStall() {
        var state = HangWatchdog.State(lastPong: start)
        #expect(state.stall(at: start.addingTimeInterval(3.9), threshold: 4) == nil)
        #expect(!state.reportedThisStall)
    }

    @Test func aStallIsReportedOnceWithHowLongItHasLasted() {
        var state = HangWatchdog.State(lastPong: start)
        #expect(state.stall(at: start.addingTimeInterval(4), threshold: 4) == 4)
        #expect(state.stall(at: start.addingTimeInterval(4.5), threshold: 4) == nil)
        #expect(state.stall(at: start.addingTimeInterval(60), threshold: 4) == nil)
    }

    @Test func anAnswerEndsTheStallSoTheNextOneIsReportedToo() {
        var state = HangWatchdog.State(lastPong: start)
        _ = state.stall(at: start.addingTimeInterval(5), threshold: 4)
        state.answer(at: start.addingTimeInterval(6))
        #expect(state.stall(at: start.addingTimeInterval(9), threshold: 4) == nil)
        #expect(state.stall(at: start.addingTimeInterval(11), threshold: 4) == 5)
    }

    @Test func theDefaultThresholdIsTheWatchdogsOwn() {
        var state = HangWatchdog.State(lastPong: start)
        #expect(state.stall(at: start.addingTimeInterval(HangWatchdog.stallThreshold - 0.1)) == nil)
        #expect(state.stall(at: start.addingTimeInterval(HangWatchdog.stallThreshold)) != nil)
    }

    @Test func aReportIsNamedByItsDateWithoutColons() {
        #expect(HangWatchdog.reportName(at: start) == "hang-2027-01-15T08-00-00Z.txt")
    }

    @Test func reportNamesSortByDate() {
        let names = [0, 3600, 86400, 40_000_000].map { HangWatchdog.reportName(at: start.addingTimeInterval($0)) }
        #expect(names.sorted() == names)
    }

    @Test func reportsGoToFloesLogsFolder() {
        let folder = HangWatchdog.reportsFolder(library: URL(fileURLWithPath: "/Users/ada/Library"))
        #expect(folder.path == "/Users/ada/Library/Logs/Floe")
        #expect(HangWatchdog.reportsFolder(library: nil).path == NSHomeDirectory() + "/Library/Logs/Floe")
        #expect(HangWatchdog.reportsFolder().path.hasSuffix("/Library/Logs/Floe"))
    }

    @Test func theHeaderSaysHowLongWhichBuildAndWhen() {
        let header = HangWatchdog.reportHeader(stalledFor: 4.26, version: "0.1.0", build: "7", at: start)
        #expect(header == "Floe main thread unresponsive for 4.3s\nVersion 0.1.0 (7)\nSampled at \(start)\n\n")
        #expect(HangWatchdog.reportHeader(stalledFor: 4, version: nil, build: nil, at: start).contains("Version ? (?)"))
    }

    @Test func theOldestReportsBeyondTheKeptOnesAreDropped() {
        let names = (1 ... 12).map { String(format: "hang-2026-10-%02dT10-00-00Z.txt", $0) }
        let dropped = HangWatchdog.reportsToDrop(among: names.shuffled() + ["notes.txt", "hang-old.log", ".DS_Store"])
        #expect(dropped == Array(names.prefix(2)))
    }

    @Test func nothingIsDroppedUpToTheLimit() {
        let names = (1 ... 10).map { String(format: "hang-2026-10-%02dT10-00-00Z.txt", $0) }
        #expect(HangWatchdog.reportsToDrop(among: names).isEmpty)
        #expect(HangWatchdog.reportsToDrop(among: []).isEmpty)
        #expect(HangWatchdog.reportsToDrop(among: names, keeping: 0) == names)
        #expect(HangWatchdog.reportsToDrop(among: names, keeping: -1) == names)
    }

    @Test func aReportHoldsTheHeaderAndWhatTheSampleSaw() throws {
        let folder = try temporaryFolder().appendingPathComponent("Logs/Floe")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = HangWatchdog.writeReport(stalledFor: 5, in: folder, at: start) { "Call graph:\n  main\n" }
        #expect(file == folder.appendingPathComponent("hang-2027-01-15T08-00-00Z.txt"))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix("Floe main thread unresponsive for 5.0s\nVersion "))
        #expect(text.hasSuffix("\n\nCall graph:\n  main\n"))
    }

    @Test func writingAReportTrimsTheFolderToTheNewestOnes() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for hour in 0 ..< 12 {
            HangWatchdog.writeReport(stalledFor: 4, in: folder, at: start.addingTimeInterval(Double(hour) * 3600)) { "" }
        }
        try "kept".write(to: folder.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names.count == HangWatchdog.keptReports + 1)
        #expect(names.first == HangWatchdog.reportName(at: start.addingTimeInterval(2 * 3600)))
        #expect(names.contains("other.txt"))
    }
}
