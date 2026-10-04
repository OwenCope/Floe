//
//  Model+FileSearch.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The file search in the panel: opening it, and what is done with the selected file.
extension LauncherModel {
    /// Switches the panel to the file search, starting with the given text.
    func openFileSearch(with text: String) {
        if let session {
            end(session)
        }
        setup = nil
        isSearchingFiles = true
        fileSearchQuery = text
        showPanel()
        focusToken += 1
    }

    func closeFileSearch() {
        isSearchingFiles = false
        fileSearch.cancel()
        focusToken += 1
    }

    var selectedFile: FileResult? {
        fileSearch.results.indices.contains(fileSearchSelection) ? fileSearch.results[fileSearchSelection] : nil
    }

    func openSelectedFile() {
        guard let file = selectedFile else { return }
        open(file)
    }

    func open(_ file: FileResult) {
        fileSearch.open(file)
        hidePanel()
        reset()
    }

    func revealSelectedFile() {
        guard let file = selectedFile else { return }
        fileSearch.reveal(file)
        hidePanel()
        reset()
    }

    func copySelectedFilePath() {
        guard let file = selectedFile else { return }
        NSPasteboard.general.copy(file.url.path)
        showHUD("Copied")
    }
}
