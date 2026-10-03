//
//  Shortcuts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit

/// Keyboard handling that doesn't need a window: list navigation steps and Raycast shortcut matching.
enum Shortcuts {
    /// ↑↓ move by one, Page Up/Down by a screenful, Home/End to the ends.
    static func navigationDelta(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 125: 1
        case 126: -1
        case 121: 9
        case 116: -9
        case 119: Int.max / 2
        case 115: -(Int.max / 2)
        default: nil
        }
    }

    /// Raycast's modifier names as AppKit flags; names it doesn't know are ignored.
    static func flags(_ modifiers: [String]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt", "alt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        return flags
    }

    /// Whether a pressed key, with its modifiers, is the action's `{ modifiers, key }` shortcut.
    static func matches(_ shortcut: Any?, key pressed: String?, flags: NSEvent.ModifierFlags) -> Bool {
        guard let shortcut = shortcut as? [String: Any], let key = shortcut["key"] as? String else { return false }
        return flags == Self.flags(shortcut["modifiers"] as? [String] ?? []) && pressed?.lowercased() == key.lowercased()
    }

    /// The shortcut as shown beside an action, such as ⌘⇧C.
    static func label(_ shortcut: Any?) -> String? {
        guard let shortcut = shortcut as? [String: Any], let key = shortcut["key"] as? String else { return nil }
        let symbols = ["cmd": "⌘", "shift": "⇧", "opt": "⌥", "alt": "⌥", "ctrl": "⌃"]
        let modifiers = (shortcut["modifiers"] as? [String] ?? []).compactMap { symbols[$0] }.joined()
        return modifiers + key.uppercased()
    }
}
