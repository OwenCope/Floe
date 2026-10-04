//
//  FileSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

struct FileResult: Identifiable, Equatable {
    let url: URL
    let name: String
    let displayPath: String
    let contentType: String?
    let lastUsed: Date?
    var id: String {
        url.path
    }
}

final class FileSearch: ObservableObject {
    @Published private(set) var results: [FileResult] = []
    @Published private(set) var isSearching = false

    private var metadataQuery: NSMetadataQuery?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    func search(_ query: String) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.start(query) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        stopQuery()
        results = []
        isSearching = false
    }

    func open(_ file: FileResult) {
        NSWorkspace.shared.open(file.url)
    }

    func reveal(_ file: FileResult) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    private func start(_ query: String) {
        stopQuery()
        isSearching = true
        let metadata = NSMetadataQuery()
        metadata.searchScopes = [NSMetadataQueryUserHomeScope]
        if query.isEmpty {
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            metadata.predicate = NSPredicate(format: "%K >= %@", "kMDItemLastUsedDate", weekAgo as NSDate)
        } else {
            metadata.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(query)*")
        }
        metadata.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: metadata, queue: .main) { [weak self] _ in self?.finish() },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: metadata, queue: .main) { [weak self] _ in self?.finish() },
        ]
        metadataQuery = metadata
        metadata.start()
    }

    private func finish() {
        guard let metadata = metadataQuery else { return }
        metadata.disableUpdates()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var files: [FileResult] = []
        for item in metadata.results.prefix(50) {
            guard let metadataItem = item as? NSMetadataItem else { continue }
            let url: URL?
            if let direct = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL {
                url = direct
            } else if let path = metadataItem.value(forAttribute: NSMetadataItemPathKey) as? String {
                url = URL(fileURLWithPath: path)
            } else {
                continue
            }
            guard let fileURL = url else { continue }
            let path = fileURL.path
            if path.contains("/Library/") {
                continue
            }
            if fileURL.pathComponents.contains(where: { $0.hasPrefix(".") }) {
                continue
            }
            // Apps already have their own scope.
            if fileURL.lastPathComponent.hasSuffix(".app") {
                continue
            }
            let folder = fileURL.deletingLastPathComponent().path
            let displayPath = folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
            files.append(FileResult(
                url: fileURL,
                name: (metadataItem.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? fileURL.lastPathComponent,
                displayPath: displayPath,
                contentType: metadataItem.value(forAttribute: "kMDItemContentType") as? String,
                lastUsed: metadataItem.value(forAttribute: "kMDItemLastUsedDate") as? Date
            ))
        }
        results = files
        isSearching = false
        stopQuery()
    }

    private func stopQuery() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        metadataQuery?.stop()
        metadataQuery = nil
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        metadataQuery?.stop()
    }
}
