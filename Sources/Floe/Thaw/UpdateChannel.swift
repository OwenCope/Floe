//
//  UpdateChannel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3's Updates.swift, in its own file so it has no Sparkle import and
//  can be tested. Floe publishes stable and beta builds only, and both can be chosen. The
//  defaults suite is passed in.

import Foundation

/// Sparkle appcast channels Floe publishes to.
enum UpdateChannel: String, CaseIterable, Identifiable {
    /// Default channel (no sparkle:channel in the appcast).
    case stable
    /// Beta and release candidate builds (sparkle:channel = beta).
    case beta

    static let defaultsKey = "UpdateChannel"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .stable: String(localized: "Stable", bundle: .floe, comment: "The update channel that only offers finished releases.")
        case .beta: String(localized: "Beta", bundle: .floe, comment: "The update channel that also offers test releases.")
        }
    }

    /// Sparkle channel names to allow in addition to the default channel.
    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable:
            []
        case .beta:
            ["beta"]
        }
    }

    /// The stored choice, falling back to Stable for a missing or unknown value.
    static func stored(in defaults: UserDefaults) -> UpdateChannel {
        defaults.string(forKey: defaultsKey).flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
