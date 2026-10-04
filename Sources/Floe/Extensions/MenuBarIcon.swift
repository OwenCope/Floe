//
//  MenuBarIcon.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// An icon of a menu-bar command, resolved to what it is drawn from. Equal icons draw the same image.
enum MenuBarIcon: Hashable {
    /// An SF Symbol, which tints with the menu bar and the menu.
    case symbol(String)
    /// An asset file or a file's Finder icon, from the shared thumbnail cache.
    case thumbnail(IconKey)
    /// What only IconView draws: an emoji, a data URI, a name nothing matches.
    case rendered(string: String, assetsPath: String, scale: CGFloat)

    /// The side AppKit gives an image in a menu row and in the menu bar, in points.
    static let points: CGFloat = 16

    var isTemplate: Bool {
        switch self {
        case .symbol: true
        case .thumbnail: false
        case let .rendered(string, _, _): string.hasPrefix("icon:")
        }
    }
}

/// Maps an icon value the way IconView does, without loading anything.
struct MenuBarIconResolver {
    let assetsPath: String
    let isDark: Bool
    let scale: CGFloat
    var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    var symbolExists: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

    /// The app's appearance and the sharpest display attached, so the bitmap is right on any of them.
    @MainActor static func system(assetsPath: String) -> MenuBarIconResolver {
        MenuBarIconResolver(
            assetsPath: assetsPath,
            isDark: NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            scale: NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        )
    }

    func icon(for value: Any?) -> MenuBarIcon? {
        if let dict = value as? [String: Any] {
            if let path = dict["fileIcon"] as? String {
                return .thumbnail(IconKey(source: .workspace(path: path), points: MenuBarIcon.points, scale: scale))
            }
            if let source = dict["source"] as? [String: Any] {
                return icon(for: isDark ? source["dark"] ?? source["light"] : source["light"] ?? source["dark"])
            }
            return icon(for: dict["source"] ?? dict["value"])
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if string.hasPrefix("icon:") {
            let name = String(string.dropFirst(5))
            let dotted = name.replacing(#/([a-z0-9])([A-Z])/#) { "\($0.1).\($0.2)" }.lowercased()
            if let symbol = [dotted, name.lowercased()].first(where: symbolExists) {
                return .symbol(symbol)
            }
        }
        if let path = assetPath(string) {
            return .thumbnail(IconKey(source: .file(path: path), points: MenuBarIcon.points, scale: scale))
        }
        return .rendered(string: string, assetsPath: assetsPath, scale: scale)
    }

    private func assetPath(_ name: String) -> String? {
        let path = name.hasPrefix("/") ? name : "\(assetsPath)/\(name)"
        if isDark {
            let url = URL(fileURLWithPath: path)
            let dark = url.deletingPathExtension().path + "@dark." + url.pathExtension
            if fileExists(dark) {
                return dark
            }
        }
        return fileExists(path) ? path : nil
    }
}

/// Turns resolved icons into images for the status button and the menu rows.
@MainActor final class MenuBarIconImages {
    enum Use {
        case statusButton, menuItem
    }

    /// Holds a row's image column open while its icon is made, so the titles do not shift when it arrives.
    static let placeholder = NSImage(size: NSSize(width: MenuBarIcon.points, height: MenuBarIcon.points), flipped: false) { _ in true }

    private static let renderedLimit = 64

    private let cache: IconThumbnailCache
    /// IconView drawings, which the thumbnail cache has no key for.
    private var rendered: [MenuBarIcon: CGImage] = [:]

    init(cache: IconThumbnailCache = .shared) {
        self.cache = cache
    }

    /// The image when nothing has to be decoded or drawn for it.
    func cached(_ icon: MenuBarIcon, for use: Use) -> NSImage? {
        switch icon {
        case let .symbol(name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = true
            if use == .statusButton {
                image?.size = NSSize(width: MenuBarIcon.points, height: MenuBarIcon.points)
            }
            return image
        case let .thumbnail(key):
            return cache.image(for: key).map { image($0, of: icon, for: use) }
        case .rendered:
            return rendered[icon].map { image($0, of: icon, for: use) }
        }
    }

    /// Makes the image in this pass: for the status button, which has one icon and nothing to fill in later.
    func now(_ icon: MenuBarIcon, for use: Use) -> NSImage? {
        switch icon {
        case .symbol:
            return cached(icon, for: use)
        case let .thumbnail(key):
            return cache.imageRenderingNow(for: key).map { image($0, of: icon, for: use) }
        case let .rendered(string, assetsPath, scale):
            if let drawn = rendered[icon] {
                return image(drawn, of: icon, for: use)
            }
            let renderer = ImageRenderer(content: IconView(value: string, assetsPath: assetsPath, size: MenuBarIcon.points, waitsForImage: true))
            renderer.scale = scale
            guard let drawn = renderer.cgImage else { return nil }
            if rendered.count >= Self.renderedLimit {
                rendered.removeAll()
            }
            rendered[icon] = drawn
            return image(drawn, of: icon, for: use)
        }
    }

    /// Decodes a thumbnail off the main thread; an IconView drawing waits its turn on it.
    func load(_ icon: MenuBarIcon, for use: Use) async -> NSImage? {
        switch icon {
        case .symbol:
            return cached(icon, for: use)
        case let .thumbnail(key):
            return await cache.load(key).map { image($0, of: icon, for: use) }
        case .rendered:
            await Task.yield()
            return now(icon, for: use)
        }
    }

    /// The status button squares its image; a menu row keeps the proportions at the row's height.
    static func size(of bitmap: CGImage, for use: Use) -> NSSize {
        let side = MenuBarIcon.points
        guard use == .menuItem, bitmap.height > 0 else { return NSSize(width: side, height: side) }
        return NSSize(width: (side * CGFloat(bitmap.width) / CGFloat(bitmap.height)).rounded(), height: side)
    }

    private func image(_ bitmap: CGImage, of icon: MenuBarIcon, for use: Use) -> NSImage {
        let image = NSImage(cgImage: bitmap, size: Self.size(of: bitmap, for: use))
        image.isTemplate = icon.isTemplate
        return image
    }
}
