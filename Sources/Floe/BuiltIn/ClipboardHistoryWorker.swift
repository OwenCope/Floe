//
//  ClipboardHistoryWorker.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Synchronization

/// The clipboard folder's file operations, so a test can count them, hold one back or make one fail.
struct ClipboardFiles: Sendable {
    static let historyName = "history.json"

    var directory: URL
    /// Every file in the folder with its size: the one read of the directory, made at load.
    var sizes: @Sendable () -> [String: Int]
    var read: @Sendable (_ name: String) -> Data?
    var write: @Sendable (_ data: Data, _ name: String, _ atomically: Bool) throws -> Void
    var remove: @Sendable (_ name: String) -> Void

    /// The real folder: private to the user, 0700 with 0600 files.
    static func onDisk(_ directory: URL) -> ClipboardFiles {
        @Sendable func ensureDirectory() {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        return ClipboardFiles(
            directory: directory,
            sizes: {
                ensureDirectory()
                let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                return Dictionary(
                    items.map { ($0.lastPathComponent, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) },
                    uniquingKeysWith: { first, _ in first }
                )
            },
            read: { try? Data(contentsOf: directory.appendingPathComponent($0)) },
            write: { data, name, atomically in
                ensureDirectory()
                let url = directory.appendingPathComponent(name)
                try data.write(to: url, options: atomically ? .atomic : [])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            },
            remove: { try? FileManager.default.removeItem(at: directory.appendingPathComponent($0)) }
        )
    }
}

/// The bytes the clipboard folder holds, kept as files come and go instead of measured again.
struct ClipboardByteLedger {
    private(set) var total = 0
    private var sizes: [String: Int] = [:]

    init(sizes: [String: Int] = [:]) {
        self.sizes = sizes
        total = sizes.values.reduce(0, +)
    }

    mutating func set(_ name: String, bytes: Int) {
        total += bytes - (sizes.updateValue(bytes, forKey: name) ?? 0)
    }

    mutating func remove(_ name: String) {
        total -= sizes.removeValue(forKey: name) ?? 0
    }
}

/// Does the clipboard history's slow work off the main thread, one job at a time in the order asked.
/// The store decides; what this produces waits in `takeEvents()` for it, in the same order.
final class ClipboardHistoryWorker: Sendable {
    enum Event: Sendable {
        case loaded([ClipboardEntry], sizes: [String: Int])
        case prepared(ClipboardEntry, bytes: Int, epoch: Int)
        case saved(bytes: Int)
    }

    private enum Job: Sendable {
        case load
        case prepare(ClipboardCapture, epoch: Int)
        case remove([String])
        case save
        case signal(DispatchSemaphore)
    }

    /// The jobs not started yet, in the order asked, and the original image data they hold.
    private struct Queue {
        var jobs: [Job] = []
        var imageBytes = 0

        mutating func next() -> Job? {
            guard !jobs.isEmpty else { return nil }
            let job = jobs.removeFirst()
            if case let .prepare(capture, _) = job {
                imageBytes -= capture.imageBytes
            }
            return job
        }

        /// Over budget, the oldest waiting images go and the newest copy always stays, even alone over it.
        /// One copied with text stays in its place as that text; nothing kept changes place.
        mutating func shed(to budget: Int) {
            var index = 0
            while imageBytes > budget, index < jobs.count - 1 {
                guard case let .prepare(capture, epoch) = jobs[index], case let .image(data, fallbackText) = capture.content else {
                    index += 1
                    continue
                }
                imageBytes -= data.count
                if let fallbackText, !fallbackText.isEmpty {
                    var kept = capture
                    kept.content = .text(fallbackText)
                    jobs[index] = .prepare(kept, epoch: epoch)
                    index += 1
                } else {
                    jobs.remove(at: index)
                }
            }
        }
    }

    /// What the worker's task and its owner both reach.
    private final class Shared: Sendable {
        let queue = Mutex(Queue())
        let events = Mutex<[Event]>([])
        /// The newest list waiting to be written; a burst of changes becomes one write.
        let unsaved = Mutex<[ClipboardEntry]?>(nil)
    }

    private let files: ClipboardFiles
    private let maxQueuedBytes: Int
    private let storedPNG: @Sendable (Data) -> Data?
    private let ticks: AsyncStream<Void>
    private let tick: AsyncStream<Void>.Continuation
    private let shared = Shared()
    private let wake: AsyncStream<Void>.Continuation

    /// Yields whenever events are waiting, and ends with the worker.
    let wakes: AsyncStream<Void>

    /// The original image data held by copies that are waiting and not yet started.
    var queuedBytes: Int {
        shared.queue.withLock { $0.imageBytes }
    }

    init(files: ClipboardFiles, maxQueuedBytes: Int, storedPNG: @escaping @Sendable (Data) -> Data?) {
        self.files = files
        self.maxQueuedBytes = maxQueuedBytes
        self.storedPNG = storedPNG
        // The jobs wait in `shared.queue`, where one can be dropped; the stream only says there are some.
        (ticks, tick) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        (wakes, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        tick.finish()
    }

    /// Starts the one task that runs the jobs.
    func start() {
        Task.detached { [ticks, files, storedPNG, shared, wake] in
            for await _ in ticks {
                while let job = shared.queue.withLock({ $0.next() }) {
                    // The pool frees what decoding an image leaves behind before the next job starts.
                    let events = autoreleasepool { Self.run(job, files: files, storedPNG: storedPNG, shared: shared) }
                    guard !events.isEmpty else { continue }
                    shared.events.withLock { $0 += events }
                    wake.yield()
                }
            }
            wake.finish()
        }
    }

    private func enqueue(_ job: Job) {
        shared.queue.withLock { $0.jobs.append(job) }
        tick.yield()
    }

    func load() {
        enqueue(.load)
    }

    /// Queues a copy, making room for it first: this never waits for the worker.
    func prepare(_ capture: ClipboardCapture, epoch: Int) {
        shared.queue.withLock { queue in
            queue.jobs.append(.prepare(capture, epoch: epoch))
            queue.imageBytes += capture.imageBytes
            // Only a new image makes room, so text arriving later never costs the image before it.
            if capture.imageBytes > 0 {
                queue.shed(to: maxQueuedBytes)
            }
        }
        tick.yield()
    }

    /// Drops every copy not started yet, so none is decoded or written and its data is freed now.
    func discardQueuedCopies() {
        shared.queue.withLock { queue in
            queue.jobs.removeAll { job in
                if case .prepare = job {
                    true
                } else {
                    false
                }
            }
            queue.imageBytes = 0
        }
    }

    func remove(_ names: [String]) {
        enqueue(.remove(names))
    }

    func save(_ entries: [ClipboardEntry]) {
        let alreadyQueued = shared.unsaved.withLock { unsaved in
            defer { unsaved = entries }
            return unsaved != nil
        }
        if !alreadyQueued {
            enqueue(.save)
        }
    }

    /// Blocks until every job asked for so far has run, or the time is up.
    func wait(timeout: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        enqueue(.signal(done))
        _ = done.wait(timeout: .now() + timeout)
    }

    func takeEvents() -> [Event] {
        shared.events.withLock { events in
            defer { events = [] }
            return events
        }
    }

    // MARK: Jobs

    private static func run(_ job: Job, files: ClipboardFiles, storedPNG: (Data) -> Data?, shared: Shared) -> [Event] {
        switch job {
        case .load:
            return [load(files)]
        case let .prepare(capture, epoch):
            guard let (entry, bytes) = entry(for: capture, files: files, storedPNG: storedPNG) else { return [] }
            return [.prepared(entry, bytes: bytes, epoch: epoch)]
        case let .remove(names):
            names.forEach(files.remove)
            return []
        case .save:
            guard let entries = shared.unsaved.withLock({ $0.take() }), let data = try? JSONEncoder().encode(entries) else { return [] }
            do {
                try files.write(data, ClipboardFiles.historyName, true)
            } catch {
                // The history is a cache; a failed write is picked up on the next change.
                return []
            }
            return [.saved(bytes: data.count)]
        case let .signal(done):
            done.signal()
            return []
        }
    }

    /// The saved history, without the images whose file is gone, and what the folder holds.
    private static func load(_ files: ClipboardFiles) -> Event {
        let sizes = files.sizes()
        let stored = files.read(ClipboardFiles.historyName).flatMap { try? JSONDecoder().decode([ClipboardEntry].self, from: $0) } ?? []
        let entries = stored.filter { entry in
            guard entry.kind == .image, let name = entry.imageFile else { return true }
            return sizes[name] != nil
        }
        return .loaded(entries, sizes: sizes)
    }

    /// Turns a capture into an entry, converting and storing its image. Nil when there is nothing to keep.
    private static func entry(for capture: ClipboardCapture, files: ClipboardFiles, storedPNG: (Data) -> Data?) -> (ClipboardEntry, bytes: Int)? {
        switch capture.content {
        case let .files(paths):
            return (.files(paths, date: capture.date, sourceApp: capture.sourceApp), 0)
        case let .text(string):
            return ClipboardEntry.text(string, date: capture.date, sourceApp: capture.sourceApp).map { ($0, 0) }
        case let .image(data, fallbackText):
            guard let png = storedPNG(data) else {
                return fallbackText.flatMap { ClipboardEntry.text($0, date: capture.date, sourceApp: capture.sourceApp) }.map { ($0, 0) }
            }
            let name = "\(UUID().uuidString).png"
            do {
                try files.write(png, name, false)
            } catch {
                return nil
            }
            return (.image(named: name, png: png, date: capture.date, sourceApp: capture.sourceApp), png.count)
        }
    }
}
