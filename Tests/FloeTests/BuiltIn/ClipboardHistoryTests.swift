//
//  ClipboardHistoryTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Synchronization
import Testing

/// Holds the worker inside one file operation or conversion until the test lets it go.
private final class Gate: Sendable {
    private let armed = Mutex(false)
    private let entered = Mutex(false)
    private let semaphore = DispatchSemaphore(value: 0)

    var isEntered: Bool {
        entered.withLock { $0 }
    }

    func arm() {
        armed.withLock { $0 = true }
    }

    func open() {
        armed.withLock { $0 = false }
        semaphore.signal()
    }

    func pass() {
        guard armed.withLock({ $0 }) else { return }
        entered.withLock { $0 = true }
        semaphore.wait()
    }
}

/// Counts the directory reads or the conversions the worker makes.
private final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int {
        count.withLock { $0 }
    }

    func increment() {
        count.withLock { $0 += 1 }
    }

    func reset() {
        count.withLock { $0 = 0 }
    }
}

/// Counts the bytes of copied data still alive anywhere, whoever holds them.
private final class LiveBytes: Sendable {
    private let bytes = Mutex(0)

    var value: Int {
        bytes.withLock { $0 }
    }

    /// A copy of the data that reports when its storage is freed.
    func tracked(_ data: Data) -> Data {
        let count = data.count
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
        data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: count)
        bytes.withLock { $0 += count }
        return Data(bytesNoCopy: pointer, count: count, deallocator: .custom { pointer, _ in
            pointer.deallocate()
            self.bytes.withLock { $0 -= count }
        })
    }
}

@MainActor
@Suite("Clipboard history")
final class ClipboardHistoryTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("floe-clipboard-tests-\(UUID().uuidString)", isDirectory: true)
    private let directoryReads = Counter()
    private let conversions = Counter()
    private let conversionGate = Gate()
    private let live = LiveBytes()
    private let imageGate = Gate()
    private let loadGate = Gate()

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    /// The real file operations and conversion on the temporary folder, counted and passing the gates.
    private func makeStore(
        maxEntries: Int = 300, maxBytes: Int = .max, maxQueuedBytes: Int = .max, failingImageWrites: Bool = false
    ) -> ClipboardHistoryStore {
        var files = ClipboardFiles.onDisk(directory)
        let (sizes, write) = (files.sizes, files.write)
        files.sizes = { [directoryReads, loadGate] in
            directoryReads.increment()
            loadGate.pass()
            return sizes()
        }
        files.write = { [imageGate] data, name, atomically in
            if name.hasSuffix(".png") {
                imageGate.pass()
                if failingImageWrites {
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
            try write(data, name, atomically)
        }
        return ClipboardHistoryStore(
            files: files,
            limits: .init(maxEntries: maxEntries, maxBytes: maxBytes, maxQueuedBytes: maxQueuedBytes),
            monitorsPasteboard: false,
            storedPNG: { [conversions, conversionGate] data in
                conversions.increment()
                conversionGate.pass()
                return ClipboardHistoryStore.storedPNG(data)
            }
        )
    }

    private func waitFor(_ label: String, _ condition: () -> Bool) async {
        for _ in 0 ..< 5000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("the expected state never arrived: \(label)")
    }

    /// Noise, so the PNG has a real size; each height is its own image to the history.
    private func png(width: Int = 64, height: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        ))
        var generator = SystemRandomNumberGenerator()
        let pixels = try #require(rep.bitmapData)
        for offset in 0 ..< width * height * 4 {
            pixels[offset] = offset % 4 == 3 ? 255 : UInt8.random(in: 0 ... 255, using: &generator)
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func text(_ string: String, at seconds: TimeInterval) -> ClipboardCapture {
        ClipboardCapture(content: .text(string), date: Date(timeIntervalSince1970: seconds), sourceApp: "Tests")
    }

    private func image(_ data: Data, at seconds: TimeInterval, fallbackText: String? = nil) -> ClipboardCapture {
        ClipboardCapture(content: .image(data, fallbackText: fallbackText), date: Date(timeIntervalSince1970: seconds), sourceApp: "Tests")
    }

    private func filesOnDisk() -> [String: Int] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.lastPathComponent, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) })
    }

    private func bytesOnDisk() -> Int {
        filesOnDisk().values.reduce(0, +)
    }

    private func historyOnDisk() throws -> [ClipboardEntry] {
        let data = try Data(contentsOf: directory.appendingPathComponent(ClipboardFiles.historyName))
        return try JSONDecoder().decode([ClipboardEntry].self, from: data)
    }

    /// The disk holds the history file and exactly the images the list names, and the total agrees.
    private func expectConsistent(_ store: ClipboardHistoryStore, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let onDisk = filesOnDisk()
        let images = Set(store.entries.compactMap(\.imageFile))
        #expect(Set(onDisk.keys) == images.union([ClipboardFiles.historyName]), sourceLocation: sourceLocation)
        #expect(store.storedBytes == bytesOnDisk(), sourceLocation: sourceLocation)
        #expect(try historyOnDisk().map(\.id) == store.entries.map(\.id), sourceLocation: sourceLocation)
        #expect(try historyOnDisk().map(\.pinned) == store.entries.map(\.pinned), sourceLocation: sourceLocation)
    }

    // MARK: Order

    @Test func copiesThatOverlapKeepTheOrderTheyWereCopiedIn() async throws {
        let store = makeStore()
        imageGate.arm()
        try store.record(image(png(height: 40), at: 1))
        store.record(text("second", at: 2))
        store.record(text("third", at: 3))
        await waitFor("the image write starts") { imageGate.isEntered }
        // Nothing shows while the first copy is still being written, not even the text behind it.
        #expect(store.entries.isEmpty)

        imageGate.open()
        await waitFor("all three arrive") { store.entries.count == 3 }
        #expect(store.entries.map(\.kind) == [.text, .text, .image])
        #expect(store.entries.map(\.text).prefix(2) == ["third", "second"])
        store.flush()
        try expectConsistent(store)
    }

    @Test func aRepeatedCopyMergesToTheTopAndKeepsItsPin() async {
        let store = makeStore()
        store.record(text("one", at: 1))
        store.record(text("two", at: 2))
        await waitFor("both arrive") { store.entries.count == 2 }
        store.togglePin(store.entries[1])
        let pinned = store.entries[1].id
        store.record(text("one", at: 3))
        await waitFor("the repeat moves up") { store.entries.first?.text == "one" }
        #expect(store.entries.count == 2)
        #expect(store.entries[0].id == pinned)
        #expect(store.entries[0].pinned)
    }

    // MARK: Bytes

    @Test func theByteTotalMatchesTheDiskAfterAddsAndRemovals() throws {
        let store = makeStore()
        let first = try png(height: 40)
        store.record(image(first, at: 1))
        try store.record(image(png(height: 41), at: 2))
        store.record(text("some text", at: 3))
        store.flush()
        #expect(store.entries.count == 3)
        #expect(filesOnDisk().count == 3)
        try expectConsistent(store)

        // The same image again replaces the stored file instead of adding one.
        store.record(image(first, at: 4))
        store.flush()
        #expect(store.entries.count == 3)
        try expectConsistent(store)

        store.delete(store.entries[0])
        store.flush()
        #expect(store.entries.count == 2)
        try expectConsistent(store)

        store.clear()
        store.flush()
        #expect(store.entries.isEmpty)
        try expectConsistent(store)
        #expect(directoryReads.value == 1)
    }

    @Test func evictionDropsTheOldestUnpinnedWithoutReadingTheDirectoryAgain() throws {
        let pngs = try (0 ..< 4).map { try png(height: 40 + $0) }
        // A first store learns what each image weighs once stored.
        let measuring = makeStore()
        for (index, data) in pngs.enumerated() {
            measuring.record(image(data, at: Double(index)))
        }
        measuring.flush()
        let stored = filesOnDisk()
        let sizes = measuring.entries.reversed().map { stored[$0.imageFile ?? ""] ?? 0 }
        #expect(sizes.count == 4 && sizes.allSatisfy { $0 > 8192 })
        measuring.clear()
        measuring.flush()
        directoryReads.reset()

        // Room for three images and the history file, so the fourth pushes one out.
        let store = makeStore(maxBytes: sizes[0] + sizes[2] + sizes[3] + 4096)
        store.record(image(pngs[0], at: 0))
        store.flush()
        store.togglePin(store.entries[0])
        for index in 1 ..< 4 {
            store.record(image(pngs[index], at: Double(index)))
        }
        store.flush()

        // The oldest is pinned and stays; the oldest unpinned went.
        #expect(store.entries.map(\.date.timeIntervalSince1970) == [3, 2, 0])
        #expect(store.storedBytes <= sizes[0] + sizes[2] + sizes[3] + 4096)
        try expectConsistent(store)
        #expect(directoryReads.value == 1)
    }

    @Test func theCountCapDropsTheOldestUnpinnedAndTheirImages() throws {
        let store = makeStore(maxEntries: 3)
        try store.record(image(png(height: 40), at: 1))
        store.record(text("pinned", at: 2))
        store.flush()
        store.togglePin(store.entries[0])
        for index in 3 ... 5 {
            store.record(text("text \(index)", at: Double(index)))
        }
        store.flush()
        #expect(store.entries.map(\.text) == ["text 5", "text 4", "pinned"])
        try expectConsistent(store)
        #expect(directoryReads.value == 1)
    }

    // MARK: Changes during a write

    @Test func clearDuringAPendingWriteDropsThatCopyAndKeepsPins() async throws {
        let store = makeStore()
        store.record(text("kept", at: 1))
        store.record(text("cleared", at: 2))
        store.flush()
        store.togglePin(store.entries[1])

        imageGate.arm()
        try store.record(image(png(height: 40), at: 3))
        await waitFor("the image write starts") { imageGate.isEntered }
        store.clear()
        #expect(store.entries.map(\.text) == ["kept"])
        // A copy made after Clear is kept, though it waits behind the one being dropped.
        store.record(text("after", at: 4))

        imageGate.open()
        await waitFor("the later copy arrives") { store.entries.count == 2 }
        store.flush()
        #expect(store.entries.map(\.text) == ["after", "kept"])
        try expectConsistent(store)
    }

    @Test func deleteAndPinDuringAPendingWriteLeaveDiskAndMemoryAgreeing() async throws {
        let store = makeStore()
        store.record(text("stays", at: 1))
        try store.record(image(png(height: 40), at: 2))
        store.flush()
        #expect(store.entries.count == 2)

        imageGate.arm()
        try store.record(image(png(height: 41), at: 3))
        await waitFor("the image write starts") { imageGate.isEntered }
        store.delete(store.entries[0])
        store.togglePin(store.entries[0])
        #expect(store.entries.map(\.text) == ["stays"])

        imageGate.open()
        await waitFor("the new image arrives") { store.entries.count == 2 }
        store.flush()
        #expect(store.entries.map(\.kind) == [.image, .text])
        #expect(store.entries.map(\.pinned) == [false, true])
        #expect(filesOnDisk().count == 2)
        try expectConsistent(store)
    }

    @Test func clearBeforeTheHistoryHasLoadedStillKeepsThePins() async throws {
        let first = makeStore()
        first.record(text("pinned", at: 1))
        first.record(text("plain", at: 2))
        first.flush()
        first.togglePin(first.entries[1])
        first.flush()

        loadGate.arm()
        let store = makeStore()
        await waitFor("the load starts") { loadGate.isEntered }
        store.clear()
        store.record(text("after", at: 3))
        loadGate.open()
        store.flush()
        #expect(store.entries.map(\.text) == ["after", "pinned"])
        try expectConsistent(store)
    }

    @Test func flushWritesWhatWasCopiedJustBeforeQuitting() throws {
        let store = makeStore()
        try store.record(image(png(height: 40), at: 1))
        store.record(text("last words", at: 2))
        store.flush()
        #expect(try historyOnDisk().map(\.kind) == [.text, .image])
        try expectConsistent(store)
    }

    // MARK: Copies waiting for the worker

    @Test func waitingCopiesAreCountedUntilTheWorkerTakesThem() async throws {
        let store = makeStore()
        let pngs = try (0 ..< 4).map { try png(height: 40 + $0) }
        conversionGate.arm()
        for (index, data) in pngs.enumerated() {
            store.record(image(live.tracked(data), at: Double(index)))
        }
        store.record(text("small", at: 9))
        await waitFor("the first conversion starts") { conversionGate.isEntered }
        // The one being converted is no longer waiting; text does not count.
        #expect(store.queuedBytes == pngs.dropFirst().map(\.count).reduce(0, +))

        conversionGate.open()
        store.flush()
        #expect(store.queuedBytes == 0)
        #expect(store.entries.count == 5)
        #expect(conversions.value == 4)
        try expectConsistent(store)
    }

    @Test func overTheBudgetTheOldestWaitingImagesGoAndTheRestKeepTheirOrder() async throws {
        let pngs = try (0 ..< 5).map { try png(height: 40 + $0) }
        // Three fit; the fourth is larger than the first, so two must go to admit it.
        try #require(pngs[4].count > pngs[1].count)
        let store = makeStore(maxQueuedBytes: pngs[1].count + pngs[2].count + pngs[3].count)
        conversionGate.arm()
        store.record(image(live.tracked(pngs[0]), at: 0))
        await waitFor("the first conversion starts") { conversionGate.isEntered }
        store.record(image(live.tracked(pngs[1]), at: 1, fallbackText: "cells as text"))
        store.record(text("between", at: 2))
        store.record(image(live.tracked(pngs[2]), at: 3))
        store.record(image(live.tracked(pngs[3]), at: 4))
        #expect(store.queuedBytes == pngs[1].count + pngs[2].count + pngs[3].count)
        store.record(image(live.tracked(pngs[4]), at: 5))
        // The two oldest waiting images made room for the newest.
        #expect(store.queuedBytes == pngs[3].count + pngs[4].count)
        #expect(live.value == pngs[0].count + pngs[3].count + pngs[4].count)

        conversionGate.open()
        store.flush()
        // The one copied with text stays where it was, as that text; the one without is gone.
        #expect(store.entries.map(\.kind) == [.image, .image, .text, .text, .image])
        #expect(store.entries.map(\.date.timeIntervalSince1970) == [5, 4, 2, 1, 0])
        #expect(store.entries[2].text == "between")
        #expect(store.entries[3].text == "cells as text")
        #expect(conversions.value == 3)
        #expect(store.queuedBytes == 0)
        try expectConsistent(store)
    }

    @Test func theNewestCopyIsKeptEvenAloneOverTheBudgetAndTextIsNeverDropped() async throws {
        let pngs = try (0 ..< 3).map { try png(height: 40 + $0) }
        let store = makeStore(maxQueuedBytes: 1)
        conversionGate.arm()
        store.record(image(live.tracked(pngs[0]), at: 0))
        await waitFor("the first conversion starts") { conversionGate.isEntered }
        for index in 1 ... 40 {
            store.record(text("text \(index)", at: Double(index)))
        }
        store.record(image(live.tracked(pngs[1]), at: 41))
        store.record(image(live.tracked(pngs[2]), at: 42))
        for index in 43 ... 60 {
            store.record(text("text \(index)", at: Double(index)))
        }
        #expect(store.queuedBytes == pngs[2].count)

        conversionGate.open()
        store.flush()
        #expect(store.entries.map(\.date.timeIntervalSince1970) == (0 ... 60).reversed().filter { $0 != 41 }.map(Double.init))
        #expect(store.entries.count { $0.kind == .text } == 58)
        #expect(conversions.value == 2)
        try expectConsistent(store)
    }

    @Test func clearDropsWaitingCopiesBeforeTheyAreConverted() async throws {
        let store = makeStore()
        let pngs = try (0 ..< 6).map { try png(height: 40 + $0) }
        conversionGate.arm()
        for (index, data) in pngs.enumerated() {
            store.record(image(live.tracked(data), at: Double(index)))
        }
        store.record(text("before", at: 7))
        await waitFor("the first conversion starts") { conversionGate.isEntered }
        #expect(live.value == pngs.map(\.count).reduce(0, +))

        store.clear()
        // The five waiting are freed at once; only the one being converted is still held.
        #expect(store.queuedBytes == 0)
        #expect(live.value == pngs[0].count)
        store.record(text("after", at: 8))

        conversionGate.open()
        let clock = ContinuousClock()
        let began = clock.now
        store.flush()
        #expect(clock.now - began < .seconds(2))
        // The one mid-conversion finished, was not kept, and its file is gone.
        #expect(conversions.value == 1)
        #expect(store.entries.map(\.text) == ["after"])
        try expectConsistent(store)
        await waitFor("the converted copy is freed") { live.value == 0 }
    }

    @Test func copiesWaitingWhenRecordingStopsAreNotKept() async throws {
        let store = makeStore()
        store.record(text("kept", at: 1))
        store.flush()
        let pngs = try (0 ..< 3).map { try png(height: 40 + $0) }
        conversionGate.arm()
        for (index, data) in pngs.enumerated() {
            store.record(image(live.tracked(data), at: Double(2 + index)))
        }
        await waitFor("the first conversion starts") { conversionGate.isEntered }

        store.dropPendingCopies()
        #expect(store.queuedBytes == 0)
        #expect(live.value == pngs[0].count)
        conversionGate.open()
        store.flush()
        #expect(conversions.value == 1)
        #expect(store.entries.map(\.text) == ["kept"])
        try expectConsistent(store)
    }

    @Test func anAppCopyingLargeImagesWhileTheWorkerIsBusyHoldsABoundedAmount() async throws {
        let base = try png(width: 512, height: 512)
        let store = makeStore(maxQueuedBytes: 3 * base.count)
        conversionGate.arm()
        store.record(image(live.tracked(base), at: 0))
        await waitFor("the first conversion starts") { conversionGate.isEntered }
        for index in 1 ..< 8 {
            store.record(image(live.tracked(base), at: Double(index)))
            // What waits fits the budget, and one more is with the worker.
            #expect(store.queuedBytes <= 3 * base.count)
            #expect(live.value <= 4 * base.count)
        }
        #expect(store.queuedBytes == 3 * base.count)
        #expect(live.value == 4 * base.count)

        store.clear()
        #expect(store.queuedBytes == 0)
        #expect(live.value == base.count)
        conversionGate.open()
        store.flush()
        #expect(conversions.value == 1)
        #expect(store.entries.isEmpty)
        try expectConsistent(store)
        await waitFor("the converted copy is freed") { live.value == 0 }
    }

    // MARK: What a copy becomes

    @Test func aLargeImageIsStoredSmaller() throws {
        let store = makeStore()
        try store.record(image(png(width: 4096, height: 8), at: 1))
        store.flush()
        let name = try #require(store.entries.first?.imageFile)
        let rep = try #require(NSBitmapImageRep(data: Data(contentsOf: directory.appendingPathComponent(name))))
        #expect(rep.pixelsWide < 4096)
        try expectConsistent(store)
    }

    @Test func anImageThatCannotBeReadBecomesItsText() {
        let store = makeStore()
        store.record(image(Data("not an image".utf8), at: 1, fallbackText: "https://example.com/page "))
        store.record(image(Data("not an image".utf8), at: 2))
        store.flush()
        #expect(store.entries.map(\.kind) == [.link])
        #expect(store.entries.first?.text == "https://example.com/page")
    }

    @Test func anImageThatCannotBeWrittenIsNotRecorded() throws {
        let store = makeStore(failingImageWrites: true)
        try store.record(image(png(height: 40), at: 1))
        store.record(text("still here", at: 2))
        store.flush()
        #expect(store.entries.map(\.text) == ["still here"])
        try expectConsistent(store)
    }

    // MARK: The history file

    @Test func aHistoryFileWrittenBeforeStillLoadsAndRoundTrips() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png(height: 40).write(to: directory.appendingPathComponent("kept.png"))
        let saved = """
        [{"id":"11111111-1111-1111-1111-111111111111","kind":"text","text":"hello","date":770000000,"pinned":true,"sourceApp":"Notes"},
         {"id":"22222222-2222-2222-2222-222222222222","kind":"image","text":"abc","imageFile":"kept.png","date":769999000,"pinned":false},
         {"id":"33333333-3333-3333-3333-333333333333","kind":"image","text":"def","imageFile":"gone.png","date":769998000,"pinned":false},
         {"id":"44444444-4444-4444-4444-444444444444","kind":"file","filePaths":["/tmp/a.txt","/tmp/b.txt"],"date":769997000,"pinned":false}]
        """
        try Data(saved.utf8).write(to: directory.appendingPathComponent(ClipboardFiles.historyName))

        let store = makeStore()
        store.flush()
        #expect(store.entries.map(\.id.uuidString.first) == ["1", "2", "4"])
        #expect(store.entries[0].pinned)
        #expect(store.entries[0].date == Date(timeIntervalSinceReferenceDate: 770_000_000))
        #expect(store.entries[2].filePaths == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(store.storedBytes == bytesOnDisk())

        store.togglePin(store.entries[1])
        store.flush()
        try expectConsistent(store)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(ClipboardFiles.historyName)))
        let first = try #require((written as? [[String: Any]])?.first)
        #expect(Set(first.keys) == ["id", "kind", "text", "date", "pinned", "sourceApp"])
        #expect(first["date"] as? Double == 770_000_000)

        let reloaded = makeStore()
        reloaded.flush()
        #expect(reloaded.entries.map(\.id) == store.entries.map(\.id))
        #expect(reloaded.entries.map(\.pinned) == [true, true, false])
        #expect(reloaded.storedBytes == bytesOnDisk())
    }

    @Test func theLedgerFollowsFilesAsTheyComeAndGo() {
        var ledger = ClipboardByteLedger(sizes: ["a.png": 10, "history.json": 5])
        #expect(ledger.total == 15)
        ledger.set("b.png", bytes: 7)
        ledger.set("history.json", bytes: 9)
        #expect(ledger.total == 26)
        ledger.remove("a.png")
        ledger.remove("never there")
        #expect(ledger.total == 16)
    }
}
