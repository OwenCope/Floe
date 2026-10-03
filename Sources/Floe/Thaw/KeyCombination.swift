//
//  KeyCombination.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to the launcher: diagnostics logging and Thaw's CF bridging helpers removed.

import Carbon.HIToolbox
import Cocoa

struct KeyCombination: Hashable {
    let key: KeyCode
    let modifiers: Modifiers

    /// A string representation for the key combination suitable
    /// for display.
    var displayValue: String {
        modifiers.symbolicValue + " " + key.stringValue.capitalized
    }

    /// Returns a Boolean value that indicates whether this key
    /// combination is reserved for system use.
    var isSystemReserved: Bool {
        Self.systemReservedKeyCombinations().contains(self)
    }

    init(key: KeyCode, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        let key = KeyCode(rawValue: Int(event.keyCode))
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)
        self.init(key: key, modifiers: modifiers)
    }
}

private extension KeyCombination {
    /// Reads the symbolic hotkeys the system has claimed for itself.
    static func systemReservedKeyCombinations() -> [KeyCombination] {
        var symbolicHotkeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&symbolicHotkeys) == noErr,
              let reservedHotkeys = symbolicHotkeys?.takeRetainedValue() as? [[String: Any]]
        else {
            return []
        }

        return reservedHotkeys.compactMap { hotkey in
            guard
                hotkey[kHISymbolicHotKeyEnabled] as? Bool == true,
                let keyCode = hotkey[kHISymbolicHotKeyCode] as? Int,
                let modifiers = hotkey[kHISymbolicHotKeyModifiers] as? Int
            else {
                return nil
            }
            return KeyCombination(
                key: KeyCode(rawValue: keyCode),
                modifiers: Modifiers(carbonFlags: modifiers)
            )
        }
    }
}

extension KeyCombination: Codable {
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count == 2 else {
            let description = "Expected 2 encoded values, found \(container.count ?? 0)"
            throw DecodingError.dataCorruptedError(in: container, debugDescription: description)
        }
        self.key = try KeyCode(rawValue: container.decode(Int.self))
        self.modifiers = try Modifiers(rawValue: container.decode(Int.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(key.rawValue)
        try container.encode(modifiers.rawValue)
    }
}
