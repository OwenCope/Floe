//
//  Preferences.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// Converts between the text a field editor holds and the typed values a command receives.
enum FieldValues {
    /// Checkboxes edit as "true" or "false"; everything else as its text.
    static func text(from value: Any) -> String {
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return value as? String ?? "\(value)"
    }

    /// What an editor starts with: the stored or default value, else a dropdown's first option, else empty.
    static func initialText(for field: FieldSpec, stored: Any?) -> String {
        (stored ?? field.defaultValue).map(text(from:))
            ?? (field.type == "dropdown" ? field.options.first?.value : nil)
            ?? ""
    }

    static func typed(_ texts: [String: String], fields: [FieldSpec]) -> [String: Any] {
        fields.reduce(into: [String: Any]()) { result, field in
            let text = texts[field.name] ?? ""
            result[field.name] = field.type == "checkbox" ? (text == "true") : text
        }
    }

    /// Required fields still empty. A checkbox always has a value, so it never counts.
    static func missing(_ fields: [FieldSpec], texts: [String: String]) -> [FieldSpec] {
        fields.filter { $0.required && $0.type != "checkbox" && (texts[$0.name] ?? "").isEmpty }
    }
}

/// Works out the values `getPreferenceValues()` returns, given where each value is kept.
enum PreferenceResolver {
    /// Command preferences are stored under "command/name" so two commands can reuse a name.
    static func storageKey(_ field: FieldSpec, commandName: String?) -> String {
        commandName.map { "\($0)/\(field.name)" } ?? field.name
    }

    /// Stored values first, then manifest defaults; an unset checkbox is false.
    /// `stored` holds the plain values by storage key and `secret` looks up password fields.
    static func resolve(extensionFields: [FieldSpec], commandFields: [FieldSpec], commandName: String,
                        stored: [String: Any], secret: (String) -> String?) -> [String: Any] {
        var result: [String: Any] = [:]
        let scoped = extensionFields.map { ($0, String?.none) } + commandFields.map { ($0, String?.some(commandName)) }
        for (field, scope) in scoped {
            let key = storageKey(field, commandName: scope)
            if let value: Any = field.isSecret ? secret(key) : stored[key] {
                result[field.name] = value
            } else if let fallback = field.defaultValue {
                result[field.name] = fallback
            } else if field.type == "checkbox" {
                result[field.name] = false
            }
        }
        return result
    }

    static func missingRequired(_ fields: [FieldSpec], values: [String: Any]) -> [FieldSpec] {
        fields.filter { field in
            guard field.required else { return false }
            if let text = values[field.name] as? String { return text.isEmpty }
            return values[field.name] == nil
        }
    }
}
