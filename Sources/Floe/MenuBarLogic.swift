//
//  MenuBarLogic.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// Names and identifies menu bar items from what Accessibility reports about them.
enum MenuBarNaming {
    /// The first non-empty line of the title, description or help; some items put a whole status readout there.
    static func label(title: String?, description: String?, help: String?) -> String? {
        [title, description, help]
            .compactMap { $0?.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } }
            .first { !$0.isEmpty }
    }

    /// Thaw's own section dividers are not items anyone opens, and an unnamed item from a host
    /// process such as MenuBarAgent would only be one more row with the host's name.
    static func isListed(identifier: String?, label: String?, ownerName: String) -> Bool {
        if identifier?.hasPrefix("Thaw.ControlItem") == true { return false }
        if label == nil, ownerName.isEmpty || ownerName == "MenuBarAgent" { return false }
        return true
    }

    /// Stable across launches: the owning app plus the item's identifier, name or position.
    static func identifier(bundleIdentifier: String?, ownerName: String, identifier: String?, label: String?, index: Int) -> String {
        "\(bundleIdentifier ?? ownerName)|\(identifier ?? label ?? "#\(index)")"
    }
}

/// Recently opened menu bar items, most recent first; ported from Thaw's MenuBarSearchRecents.
final class MenuBarSearchRecents {
    /// A hard cap keeps the empty-query list from turning into a second full inventory.
    static let limit = 8
    private static let key = "menuBarSearchRecents"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var identifiers: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func record(_ identifier: String) {
        var updated = identifiers.filter { $0 != identifier }
        updated.insert(identifier, at: 0)
        defaults.set(Array(updated.prefix(Self.limit)), forKey: Self.key)
    }

    /// Live items for the stored identifiers, in recency order; ones not in the menu bar now are skipped.
    func resolve<Item: Identifiable>(in items: [Item]) -> [Item] where Item.ID == String {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { byID[$0] }
    }
}

enum ImageCheck {
    /// A hidden item leaves only the menu bar's backdrop where it would be; a capture that is one flat
    /// tone shows nothing worth previewing.
    static func showsSomething(_ image: CGImage) -> Bool {
        let width = 48
        let height = 12
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return true }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let mean = pixels.reduce(0) { $0 + Double($1) } / Double(pixels.count)
        let variance = pixels.reduce(0) { $0 + pow(Double($1) - mean, 2) } / Double(pixels.count)
        return variance.squareRoot() > 12
    }
}
