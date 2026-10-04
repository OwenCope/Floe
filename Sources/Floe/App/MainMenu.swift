//
//  MainMenu.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

enum MainMenu {
    /// Floe has no menu bar of its own unless it is in the Dock, but the main menu is still where
    /// AppKit looks up key equivalents: without it ⌘Q, ⌘W and the editing keys do nothing.
    /// The launcher and the settings process each make one, with their own About and Settings actions.
    static func make(target: AnyObject, about: Selector, settings: Selector) -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Floe", action: about, keyEquivalent: "").target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",").target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Floe", action: #selector(NSApplication.hide), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Floe", action: #selector(NSApplication.terminate), keyEquivalent: "q")

        // Sent to whatever has focus, which is how a text field gets Select All, Copy and Paste.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
