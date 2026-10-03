//
//  MenuBarItems.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices
import ScreenCaptureKit

/// One item in the menu bar's status area. Thaw finds items through its own runtime; Floe reads them
/// through the public Accessibility API and opens one by pressing it.
struct MenuBarExtra: Identifiable {
    let id: String
    let name: String
    let ownerName: String
    let ownerURL: URL?
    /// Where the item sits, in global top-left-origin points (Accessibility's coordinates).
    let frame: CGRect
    fileprivate let element: AXUIElement
}

enum MenuBarExtras {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    /// Walks every running app's extras menu bar. Slow enough (one AX round trip per app) to keep off the main thread.
    static func scan() -> [MenuBarExtra] {
        var extras: [MenuBarExtra] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ownPID {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.25)
            guard let bar: AXUIElement = value(application, "AXExtrasMenuBar"),
                  let items: [AXUIElement] = value(bar, kAXChildrenAttribute) else { continue }
            let ownerName = app.localizedName ?? ""
            for (index, item) in items.enumerated() {
                let identifier: String? = value(item, "AXIdentifier")
                // Thaw's own section dividers are not items anyone opens.
                if identifier?.hasPrefix("Thaw.ControlItem") == true { continue }
                let title: String? = value(item, kAXTitleAttribute)
                let description: String? = value(item, kAXDescriptionAttribute)
                let help: String? = value(item, kAXHelpAttribute)
                // Some items put a whole status readout in their description; the first line is the name.
                let label = [title, description, help]
                    .compactMap { $0?.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } }
                    .first { !$0.isEmpty }
                // Unnamed items from a host process such as MenuBarAgent would all be rows called "MenuBarAgent".
                if label == nil, ownerName.isEmpty || ownerName == "MenuBarAgent" { continue }
                let key = "\(app.bundleIdentifier ?? ownerName)|\(identifier ?? label ?? "#\(index)")"
                extras.append(MenuBarExtra(id: key, name: label ?? ownerName, ownerName: ownerName,
                                           ownerURL: app.bundleURL, frame: frame(of: item), element: item))
            }
        }
        // Left to right, the order they sit in the menu bar.
        return extras.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let position: AXValue = value(element, kAXPositionAttribute) { AXValueGetValue(position, .cgPoint, &origin) }
        if let extent: AXValue = value(element, kAXSizeAttribute) { AXValueGetValue(extent, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    /// Opens the item's menu, the way a click on it would.
    @discardableResult
    static func open(_ extra: MenuBarExtra) -> Bool {
        AXUIElementPerformAction(extra.element, kAXPressAction as CFString) == .success
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// Items recently opened from the menu bar search, most recent first; ported from Thaw's MenuBarSearchRecents.
final class MenuBarSearchRecents {
    /// A hard cap keeps the empty-query list from turning into a second full inventory.
    private static let limit = 8
    private static let key = "menuBarSearchRecents"

    var identifiers: [String] {
        UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func record(_ extra: MenuBarExtra) {
        var updated = identifiers.filter { $0 != extra.id }
        updated.insert(extra.id, at: 0)
        UserDefaults.standard.set(Array(updated.prefix(Self.limit)), forKey: Self.key)
    }

    /// Live items for the stored identifiers, in recency order; ones that aren't in the menu bar now are skipped.
    func resolve(in extras: [MenuBarExtra]) -> [MenuBarExtra] {
        let byID = Dictionary(extras.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { byID[$0] }
    }
}

/// Pictures of each item as the menu bar draws it, for the inspector rows. Needs Screen Recording;
/// without it the previews stay empty, as in Thaw.
final class MenuBarPreviews: ObservableObject {
    @Published private(set) var images: [String: CGImage] = [:]

    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccess() {
        CGRequestScreenCaptureAccess()
    }

    func capture(_ extras: [MenuBarExtra]) {
        guard Self.hasAccess else { return }
        for extra in extras where extra.frame.width > 0 && extra.frame.height > 0 {
            Task { @MainActor [weak self] in
                guard let image = try? await SCScreenshotManager.captureImage(in: extra.frame),
                      Self.showsSomething(image) else { return }
                self?.images[extra.id] = image
            }
        }
    }

    /// A hidden item leaves only the menu bar's backdrop where it would be; a capture that is one flat
    /// tone shows nothing worth previewing.
    private static func showsSomething(_ image: CGImage) -> Bool {
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
