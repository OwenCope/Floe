//
//  SearchBench.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

private func milliseconds(_ work: () -> Void) -> Int {
    let start = Date()
    work()
    return Int(Date().timeIntervalSince(start) * 1000)
}

/// The catalog, scanned a part at a time with each part's time printed.
private func timedCatalog() -> CatalogSnapshot {
    var apps: [AppEntry] = []
    var commands: [ExtensionCommand] = []
    var scripts = ScriptScan(commands: [], failures: [])
    var panes: [SystemSettingsPane] = []
    print("SCAN apps \(milliseconds { apps = AppEntry.scan() }) ms (\(apps.count))")
    print("SCAN commands \(milliseconds { commands = ExtensionCommand.scan(includeRaycast: true) }) ms (\(commands.count))")
    print("SCAN scripts \(milliseconds { scripts = ScriptCommand.scan() }) ms (\(scripts.commands.count))")
    print("SCAN settings panes \(milliseconds { panes = SystemSettingsPane.scan() }) ms (\(panes.count))")
    return CatalogSnapshot(apps: apps, commands: commands, scripts: scripts.commands, scriptFailures: scripts.failures, settingsPanes: panes)
}

/// `Floe --bench-search [query ...]` times the catalog scan and each keystroke of a query, drawn off screen.
func runSearchBench(queries: [String]) -> Never {
    _ = NSApplication.shared
    let model = LauncherModel(snapshot: timedCatalog())
    model.canAskAI = AskAI.availabilityCheck { AIAnswer.isAvailable }
    let frame = NSRect(origin: NSPoint(x: -4000, y: -4000), size: model.panelState.windowSize(in: .extended))
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    func draw() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    print("FIRST RENDER \(milliseconds { window.contentView = NSHostingView(rootView: LauncherView(model: model)); window.orderFrontRegardless(); draw() }) ms")
    for query in queries.isEmpty ? ["safari", "settings", "ask why is the sky blue"] : queries {
        var typed = ""
        var times: [String] = []
        for character in query {
            typed.append(character)
            // The 20 ms the draw waits for the run loop is taken back out.
            times.append("\(typed.suffix(1))=\(max(0, milliseconds { model.query = typed; draw() } - 20))")
        }
        model.query = ""
        draw()
        print("TYPE \"\(query)\" ms per key: \(times.joined(separator: " ")) rows=\(model.results.count)")
    }
    exit(0)
}
