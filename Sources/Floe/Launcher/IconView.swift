//
//  IconView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

enum Palette {
    static func color(_ value: Any?) -> Color? {
        guard let string = value as? String else { return nil }
        if string.hasPrefix("#"), let hex = UInt32(string.dropFirst().prefix(6), radix: 16) {
            return Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        switch string.replacingOccurrences(of: "color:", with: "") {
        case "Red": return .red
        case "Orange": return .orange
        case "Yellow": return .yellow
        case "Green": return .green
        case "Blue": return .blue
        case "Purple": return .purple
        case "Magenta": return .pink
        case "PrimaryText": return .primary
        case "SecondaryText": return .secondary
        default: return nil
        }
    }
}

struct IconView: View {
    let value: Any?
    let assetsPath: String
    var size: CGFloat = 18

    private enum Resolved {
        case symbol(String), image(NSImage), remote(URL), text(String), none
    }

    /// Icons render at 18-32 points, so decoded bitmaps are kept at a 3x pixel target and the cache
    /// holds a bounded byte budget: a 1024 px asset then costs kilobytes instead of ~4 megabytes.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private static let symbols: [String: String] = [
        "Globe": "globe", "Star": "star.fill", "Clipboard": "doc.on.clipboard", "Link": "link", "Trash": "trash",
        "Finder": "folder", "Folder": "folder", "Document": "doc", "Calendar": "calendar", "Clock": "clock",
        "Person": "person", "Gear": "gearshape", "MagnifyingGlass": "magnifyingglass", "Terminal": "terminal",
        "Sidebar": "sidebar.right", "ArrowRight": "arrow.right", "Eye": "eye", "Bubble": "bubble.left",
        "Checkmark": "checkmark", "XMarkCircle": "xmark.circle", "Plus": "plus", "Pencil": "pencil",
        "Download": "arrow.down.circle", "Upload": "arrow.up.circle", "Bookmark": "bookmark", "Heart": "heart",
        "Info": "info.circle", "Warning": "exclamationmark.triangle", "Code": "chevron.left.forwardslash.chevron.right",
        "Window": "macwindow", "AppWindow": "macwindow", "Image": "photo", "Message": "message", "Envelope": "envelope",
        "ArrowClockwise": "arrow.clockwise", "Circle": "circle", "Dot": "circle.fill", "Lock": "lock", "Key": "key",
        "Tag": "tag", "Text": "text.alignleft", "List": "list.bullet", "Play": "play.fill", "Pause": "pause.fill",
    ]

    @Environment(\.colorScheme) private var colorScheme

    private func resolve(_ value: Any?) -> Resolved {
        let pixels = Self.pixelSize(for: size)
        if let dict = value as? [String: Any] {
            if let path = dict["fileIcon"] as? String {
                return cachedImage(key: "fileIcon:\(path)", pixels: pixels) { NSWorkspace.shared.icon(forFile: path) }.map(Resolved.image) ?? .none
            }
            // Raycast's { source: { light, dark } } picks per appearance.
            if let source = dict["source"] as? [String: Any] {
                return resolve(colorScheme == .dark ? source["dark"] ?? source["light"] : source["light"] ?? source["dark"])
            }
            return resolve(dict["source"] ?? dict["value"])
        }
        guard let string = value as? String, !string.isEmpty else { return .none }
        if string.hasPrefix("icon:") {
            let name = String(string.dropFirst(5))
            // Raycast names are CamelCase (ArrowUpCircle); most map onto SF Symbols as arrow.up.circle.
            let dotted = name.replacing(#/([a-z0-9])([A-Z])/#) { "\($0.1).\($0.2)" }.lowercased()
            let candidates = [Self.symbols[name], dotted, name.lowercased()].compactMap(\.self)
            let symbol = candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            return .symbol(symbol ?? "square.dashed")
        }
        if string.hasPrefix("http"), let url = URL(string: string) {
            return .remote(url)
        }
        if string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") {
            let image = cachedImage(key: string, pixels: pixels) {
                let payload = String(string[string.index(after: comma)...])
                let data = string[..<comma].contains(";base64")
                    ? Data(base64Encoded: payload)
                    : (payload.removingPercentEncoding ?? payload).data(using: .utf8)
                return data.flatMap(NSImage.init(data:))
            }
            return image.map(Resolved.image) ?? .none
        }
        // Asset names repeat across extensions (most ship an "icon.png"), so the cache key is the full path.
        if let path = assetPath(string), let image = cachedImage(key: path, pixels: pixels, load: { NSImage(contentsOfFile: path) }) {
            return .image(image)
        }
        return string.count <= 2 ? .text(string) : .none
    }

    /// An absolute path, or a file in the extension's assets; prefers Raycast's `name@dark.ext` variant in dark mode.
    private func assetPath(_ name: String) -> String? {
        let path = (name as NSString).isAbsolutePath ? name : URL(fileURLWithPath: assetsPath).appendingPathComponent(name).path
        if colorScheme == .dark {
            let url = URL(fileURLWithPath: path)
            let dark = url.deletingPathExtension().path + "@dark." + url.pathExtension
            if FileManager.default.fileExists(atPath: dark) {
                return dark
            }
        }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func cachedImage(key: String, pixels: Int, load: () -> NSImage?) -> NSImage? {
        if let cached = Self.cache.object(forKey: key as NSString) {
            return cached
        }
        guard let loaded = load() else { return nil }
        let image = Self.downsampled(loaded, to: pixels)
        let bytes = image.representations.reduce(0) { $0 + $1.pixelsWide * $1.pixelsHigh * 4 }
        Self.cache.setObject(image, forKey: key as NSString, cost: bytes)
        return image
    }

    /// Draws the image's bitmap into at most `pixels` on its longer side; smaller images pass through.
    private static func downsampled(_ image: NSImage, to pixels: Int) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              max(source.width, source.height) > pixels
        else { return image }
        let scale = CGFloat(pixels) / CGFloat(max(source.width, source.height))
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        else { return image }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let drawn = context.makeImage() else { return image }
        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(NSBitmapImageRep(cgImage: drawn))
        return result
    }

    static func pixelSize(for points: CGFloat) -> Int {
        Int((points * 3).rounded())
    }

    /// tintColor and mask can sit at any level: { value: { source, tintColor } } is common.
    private static func attribute(_ key: String, in value: Any?) -> Any? {
        guard let dict = value as? [String: Any] else { return nil }
        return dict[key] ?? attribute(key, in: dict["value"]) ?? attribute(key, in: dict["source"])
    }

    var body: some View {
        let tint = Palette.color(Self.attribute("tintColor", in: value))
        let isCircle = Self.attribute("mask", in: value) as? String == "circle"
        // Every icon sits in the same glass squircle, Raycast-style: bare
        // symbols next to squircled asset icons read as two different things.
        let squircle = self.squircle(isCircle)
        return Group {
            switch resolve(value) {
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(tint ?? .secondary)
            case let .image(image):
                // A tint makes the image a template, as Raycast does for monochrome assets.
                if let tint {
                    Image(nsImage: image)
                        .resizable().scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                }
            case let .remote(url):
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            case let .text(text):
                Text(text).font(.system(size: size * 0.55))
            case .none:
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(.quinary, in: squircle)
        .clipShape(squircle)
    }

    private func squircle(_ isCircle: Bool) -> RoundedRectangle {
        isCircle
            ? RoundedRectangle(cornerRadius: size / 2, style: .continuous)
            : RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    }
}
