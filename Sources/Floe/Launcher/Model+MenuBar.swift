//
//  Model+MenuBar.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The menu bar item search in the panel: scanning, matching, renaming and clicking an item.
extension LauncherModel {
    /// Switches the panel to the menu bar item search and rescans the menu bar.
    func openMenuBarSearch() {
        if let session {
            end(session)
        }
        setup = nil
        isShowingClipboardHistory = false
        isSearchingMenuBar = true
        if !settings.rememberMenuBarQuery {
            menuBarQuery = ""
        }
        showPanel()
        focusToken += 1
        scanMenuBar()
    }

    func closeMenuBarSearch() {
        isSearchingMenuBar = false
        focusToken += 1
    }

    /// Reads the menu bar once at launch, so the first search opens on a full list and not on a spinner.
    func warmMenuBar() {
        guard MenuBarExtras.isTrusted, menuBarExtras.isEmpty else { return }
        scanMenuBar()
    }

    private func scanMenuBar() {
        menuBarAccessGranted = MenuBarExtras.isTrusted
        guard menuBarAccessGranted else {
            menuBarExtras = []
            refreshMenuBar()
            return
        }
        isScanningMenuBar = menuBarExtras.isEmpty
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let extras = MenuBarExtras.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                menuBarExtras = extras
                isScanningMenuBar = false
                refreshMenuBar()
            }
        }
    }

    func requestMenuBarAccess() {
        MenuBarExtras.requestAccess()
        // The grant happens in System Settings; check again when the user comes back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.scanMenuBar() }
    }

    /// No query: recently opened items, then every item in menu bar order. With a query: items whose
    /// name or owning app matches.
    func refreshMenuBar() {
        menuBarSelection = 0
        let query = menuBarQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            let recents = menuBarRecents.resolve(in: menuBarExtras)
            let recentIDs = Set(recents.map(\.id))
            menuBarResults = recents.map { MenuBarResult(extra: $0, section: "Recent") }
                + menuBarExtras.filter { !recentIDs.contains($0.id) }.map { MenuBarResult(extra: $0, section: "Menu Bar") }
            return
        }
        menuBarResults = MenuBarSearchScope.ranked(menuBarExtras, query: query, names: settings.menuBarItemNames)
            .map { MenuBarResult(extra: $0, section: nil) }
    }

    /// The owning app's name, when it says something the item's name doesn't.
    func ownerLine(for extra: MenuBarExtra) -> String? {
        extra.ownerName.isEmpty || extra.ownerName == extra.name ? nil : extra.ownerName
    }

    /// The name the user gave the item, else the one its app reports.
    func displayName(for extra: MenuBarExtra) -> String {
        MenuBarSearchScope.displayName(for: extra, names: settings.menuBarItemNames)
    }

    var selectedMenuBarExtra: MenuBarExtra? {
        menuBarResults.indices.contains(menuBarSelection) ? menuBarResults[menuBarSelection].extra : nil
    }

    func beginRenamingSelection() {
        guard let extra = selectedMenuBarExtra else { return }
        menuBarRenameDraft = displayName(for: extra)
        renamingMenuBarItem = extra.id
    }

    /// An empty name goes back to the one the app reports.
    func commitRename() {
        guard let id = renamingMenuBarItem else { return }
        let name = menuBarRenameDraft.trimmingCharacters(in: .whitespaces)
        settings.menuBarItemNames[id] = name.isEmpty ? nil : name
        renamingMenuBarItem = nil
        let selected = menuBarSelection
        refreshMenuBar()
        menuBarSelection = min(selected, max(menuBarResults.count - 1, 0))
        focusToken += 1
    }

    func cancelRename() {
        renamingMenuBarItem = nil
        focusToken += 1
    }

    /// Things Floe can do with an item; Thaw's moving between sections stays with Thaw.
    func menuBarActions(for extra: MenuBarExtra) -> [ItemAction?] {
        var actions: [ItemAction?] = [
            ItemAction(title: "Click Item", symbol: "cursorarrow.click") { [weak self] in self?.openMenuBarExtra(extra) },
            ItemAction(title: "Edit Name", symbol: "pencil") { [weak self] in self?.beginRenamingSelection() },
            ItemAction(title: "Copy Name", symbol: "doc.on.doc") { [weak self] in
                guard let self else { return }
                NSPasteboard.general.copy(displayName(for: extra))
                showHUD("Copied \(displayName(for: extra))")
            },
        ]
        if settings.menuBarItemNames[extra.id] != nil {
            actions.append(ItemAction(title: "Restore Original Name", symbol: "arrow.uturn.backward") { [weak self] in
                self?.settings.menuBarItemNames[extra.id] = nil
                self?.refreshMenuBar()
            })
        }
        if let url = extra.ownerURL {
            actions.append(nil)
            actions.append(ItemAction(title: "Open \(extra.ownerName)", symbol: "app") { [weak self] in
                NSWorkspace.shared.open(url)
                self?.hidePanel()
            })
            actions.append(ItemAction(title: "Show \(extra.ownerName) in Finder", symbol: "folder") { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self?.hidePanel()
            })
        }
        return actions
    }

    func openMenuBarExtra(_ extra: MenuBarExtra) {
        menuBarRecents.record(extra.id)
        hidePanel()
        reset()
        // Pressed once the panel is gone, so the menu opens over the app the user came from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MenuBarExtras.open(extra) }
    }
}
