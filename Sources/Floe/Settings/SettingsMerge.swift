//
//  SettingsMerge.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Two processes save the same settings blob. These compare and combine two copies of it by its
/// top-level keys, so one process's save does not undo what the other just changed.
enum SettingsMerge {
    private static func object(_ data: Data?) -> [String: NSObject] {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: NSObject] else { return [:] }
        return object
    }

    /// Whether two blobs say the same thing, whatever order their keys were written in.
    static func isSame(_ left: Data?, _ right: Data?) -> Bool {
        guard let left, let right else { return left == nil && right == nil }
        return left == right || object(left) == object(right)
    }

    /// `mine` with every key the other process changed since `base`, except those changed here too:
    /// an edit made in this process and not yet saved is the newer one.
    static func merged(base: Data?, mine: Data, theirs: Data) -> Data {
        let base = object(base)
        let theirs = object(theirs)
        var result = object(mine)
        for key in Set(base.keys).union(theirs.keys) where theirs[key] != base[key] && result[key] == base[key] {
            result[key] = theirs[key]
        }
        return (try? JSONSerialization.data(withJSONObject: result)) ?? mine
    }
}
