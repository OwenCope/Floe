//
//  DebugOptions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import ArgumentParser

/// What `Floe` can do from a terminal instead of starting the app; `Floe --help` lists them.
struct DebugOptions: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "Floe", abstract: "With no options, starts the app.")

    @Option(help: ArgumentHelp("Print the ranked root results for a query, for checking aliases and ranking.", valueName: "query"))
    var search: String?

    @Flag(help: "Time laying out each settings page off screen. FLOE_BENCH_DUMP=<folder> saves what each page looks like.")
    var benchSettings = false

    @Flag(help: "Time the catalog scan and each keystroke of the queries after it, drawn off screen.")
    var benchSearch = false

    @Flag(help: "Print a fingerprint of each command's icon and how much of it is drawn. FLOE_ICON_DUMP=<folder> also writes the PNGs.")
    var iconCheck = false

    @Flag(name: .customLong("menubar"), help: "List the menu bar items Floe can open, ranked for the query after it if there is one.")
    var menuBar = false

    @Option(help: ArgumentHelp("Draw the launcher's root, compact and menu bar views off screen and save them.", valueName: "folder"))
    var panelSnapshot: String?

    @Flag(help: "Choose one of the lines on standard input in a search panel and print it. Exits 1 if nothing is chosen. FLOE_PICK_AUTO=1 prints the first match without showing the panel; FLOE_PICK_SNAPSHOT=<file> saves a picture of the panel instead.")
    var pick = false

    @Option(help: ArgumentHelp("With --pick, the search field's placeholder.", valueName: "text"))
    var prompt: String?

    @Option(help: ArgumentHelp("With --pick, the text the search field starts with.", valueName: "text"))
    var query: String?

    @Flag(help: "With --pick, print the chosen line's position in the input, counting from 0, instead of its text.")
    var index = false

    @Option(parsing: .upToNextOption, help: ArgumentHelp("Run a command without UI and report the first view it renders.", valueName: "extension> <command"))
    var selftest: [String] = []

    /// The menu bar query, and whatever macOS or Xcode adds to the command line.
    @Argument(parsing: .allUnrecognized, help: .hidden)
    var rest: [String] = []

    func validate() throws {
        guard selftest.isEmpty || selftest.count == 2 else {
            throw ValidationError("--selftest takes an extension and a command.")
        }
        guard pick || (prompt == nil && query == nil && !index) else {
            throw ValidationError("--prompt, --query and --index only go with --pick.")
        }
    }
}
