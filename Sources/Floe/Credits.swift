//
//  Credits.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Written by scripts/generate-credits.py. Change the script and run it again instead of editing this file.

/// One project Floe is built from, as the About page's Credits sheet lists it.
struct Credit: Identifiable {
    let name: String
    let detail: String
    /// Names an entry in Info.plist's FloeLinks.
    let link: String

    var id: String {
        name
    }
}

enum Credits {
    static let all: [Credit] = [
        Credit(name: "Thaw", detail: "ThawUI, ThawConcurrency, the hotkey code, the HUD, the glass styles and the search panel design. Copyright © 2026 Toni Förster et al. GPL-3.0.", link: "thaw"),
        Credit(name: "Droppy Code", detail: "Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app. Floe uses its login shell environment, its process runner, the tools and the streamed API request that answer AI.ask, its hang watchdog and the folder watcher behind hot reload, each modified for Floe. AGPL-3.0.", link: "droppyCode"),
        Credit(name: "CompactSlider", detail: "Used by ThawUI. MIT.", link: "compactSlider"),
        Credit(name: "Sparkle", detail: "Checks for updates and installs them. MIT.", link: "sparkle"),
        Credit(name: "swift-subprocess", detail: "Starts and stops the process an extension runs in. Apache-2.0.", link: "swiftSubprocess"),
        Credit(name: "swift-system", detail: "Used by swift-subprocess. Apache-2.0.", link: "swiftSystem"),
        Credit(name: "swift-markdown", detail: "Reads the Markdown in detail views. Apache-2.0.", link: "swiftMarkdown"),
        Credit(name: "swift-cmark", detail: "Used by swift-markdown. BSD-2-Clause.", link: "swiftCmark"),
        Credit(name: "swift-argument-parser", detail: "Reads the command line options. Apache-2.0.", link: "swiftArgumentParser"),
        Credit(name: "swift-algorithms", detail: "Picks the best matches and drops repeats in lists. Apache-2.0.", link: "swiftAlgorithms"),
        Credit(name: "swift-numerics", detail: "Used by swift-algorithms. Apache-2.0.", link: "swiftNumerics"),
        Credit(name: "swift-async-algorithms", detail: "Waits for typing and folder changes to settle. Apache-2.0.", link: "swiftAsyncAlgorithms"),
        Credit(name: "swift-collections", detail: "Used by swift-async-algorithms. Apache-2.0.", link: "swiftCollections"),
        Credit(name: "Bun", detail: "Runs extensions. MIT.", link: "bun"),
        Credit(name: "React", detail: "Renders extensions. MIT.", link: "react"),
        Credit(name: "react-reconciler", detail: "Turns what an extension renders into Floe's views. MIT.", link: "react"),
        Credit(name: "Raycast extensions", detail: "The API Floe implements; each extension keeps its own license.", link: "raycastExtensions"),
    ]

    static let trademark = "Raycast is a trademark of Raycast Technologies Inc. Floe is not affiliated with Raycast."
}
