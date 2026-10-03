//
//  PropFormat.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// Reads the loosely typed values Raycast accepts for accessories and metadata.
enum PropFormat {
    /// A string, a number, or `{ value }` wrapping either.
    static func text(_ value: Any?) -> String? {
        if let number = value as? NSNumber, !(value is String) { return number.stringValue }
        return value as? String ?? ((value as? [String: Any])?["value"]).flatMap(text)
    }

    /// The `color` beside a `{ value, color }` text or tag.
    static func color(_ value: Any?) -> Any? {
        (value as? [String: Any])?["color"]
    }

    /// An ISO 8601 date, bare or as `{ value }`; dates arrive as strings because JSON has no date type.
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String ?? (value as? [String: Any])?["value"] as? String else { return nil }
        return (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(string, strategy: .iso8601))
    }
}
