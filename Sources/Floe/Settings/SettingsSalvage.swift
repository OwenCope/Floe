//
//  SettingsSalvage.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Reads a stored JSON object key by key in effect: one value that cannot be read costs that key, not the rest.
/// A newer build's value an older one does not know, or one bad entry, would otherwise reset every setting.
enum SettingsSalvage {
    struct Result<Value> {
        let value: Value
        /// The top-level keys that were left out because their values could not be read.
        let dropped: [String]
    }

    /// Decodes `type`, leaving out each top-level key whose value fails, until the rest reads. Nil when
    /// the data is not a JSON object, or a key the type requires is missing.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) -> Result<Value>? {
        if let value = try? JSONDecoder().decode(type, from: data) {
            return Result(value: value, dropped: [])
        }
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var dropped: [String] = []
        // Each pass removes one key, so the object's size bounds the loop.
        for _ in 0 ... object.count {
            guard let remaining = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            do {
                return try Result(value: JSONDecoder().decode(type, from: remaining), dropped: dropped)
            } catch let error as DecodingError {
                guard let key = failedKey(of: error), object.removeValue(forKey: key) != nil else { return nil }
                dropped.append(key)
            } catch {
                return nil
            }
        }
        return nil
    }

    /// The top-level key a decoding error is about, or nil when it is about a key that is not there.
    private static func failedKey(of error: DecodingError) -> String? {
        switch error {
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            context.codingPath.first?.stringValue
        case .keyNotFound:
            nil
        @unknown default:
            nil
        }
    }
}
