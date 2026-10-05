//
//  SettingsCatalog.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// What the settings pages list: the commands, scripts and apps found on this Mac. The settings
/// process scans them itself, away from the main thread, and never runs any of them.
final class SettingsCatalog: ObservableObject {
    /// Every command found, including those of disabled extensions.
    @Published private(set) var allCommands: [ExtensionCommand] = []
    @Published private(set) var allScripts: [ScriptCommand] = []
    /// Files in the Scripts folder that failed to parse.
    @Published private(set) var scriptFailures: [ScriptFailure] = []
    @Published private(set) var apps: [AppEntry] = []

    private let scanner: any CatalogScanning
    private let settings: AppSettings
    /// Bumped per request, so a scan that was overtaken by a newer one is dropped.
    private var commandsGeneration = 0
    private var scriptsGeneration = 0
    private var appsGeneration = 0

    /// With a snapshot the catalog is complete at once, for the modes that draw one state and exit.
    init(scanner: any CatalogScanning = CatalogLoader(), settings: AppSettings = .shared, snapshot: CatalogSnapshot? = nil) {
        self.scanner = scanner
        self.settings = settings
        if let snapshot {
            allCommands = snapshot.commands
            allScripts = snapshot.scripts
            scriptFailures = snapshot.scriptFailures
            apps = snapshot.apps
        }
    }

    func reloadAll() {
        reloadCommands()
        reloadScripts()
        reloadApps()
    }

    func reloadCommands() {
        commandsGeneration += 1
        let generation = commandsGeneration
        let includeRaycast = settings.includeRaycastExtensions
        Task { @concurrent [weak self, scanner] in
            let commands = await scanner.scanCommands(includeRaycast: includeRaycast)
            await self?.finish(generation: generation, commands: commands)
        }
    }

    func reloadScripts() {
        scriptsGeneration += 1
        let generation = scriptsGeneration
        Task { @concurrent [weak self, scanner] in
            let scan = await scanner.scanScripts()
            await self?.finish(generation: generation, scripts: scan)
        }
    }

    func reloadApps() {
        appsGeneration += 1
        let generation = appsGeneration
        Task { @concurrent [weak self, scanner] in
            let apps = await scanner.scanApps()
            await self?.finish(generation: generation, apps: apps)
        }
    }

    @MainActor
    private func finish(generation: Int, commands: [ExtensionCommand]) {
        guard generation == commandsGeneration else { return }
        allCommands = commands
    }

    @MainActor
    private func finish(generation: Int, scripts: ScriptScan) {
        guard generation == scriptsGeneration else { return }
        allScripts = scripts.commands
        scriptFailures = scripts.failures
    }

    @MainActor
    private func finish(generation: Int, apps: [AppEntry]) {
        guard generation == appsGeneration else { return }
        self.apps = apps
    }
}
