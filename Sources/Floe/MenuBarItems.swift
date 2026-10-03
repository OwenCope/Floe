//
//  MenuBarItems.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices

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
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

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
                let label = MenuBarNaming.label(
                    title: value(item, kAXTitleAttribute),
                    description: value(item, kAXDescriptionAttribute),
                    help: value(item, kAXHelpAttribute)
                )
                guard MenuBarNaming.isListed(identifier: identifier, label: label, ownerName: ownerName) else { continue }
                let key = MenuBarNaming.identifier(
                    bundleIdentifier: app.bundleIdentifier,
                    ownerName: ownerName,
                    identifier: identifier,
                    label: label,
                    index: index
                )
                extras.append(MenuBarExtra(
                    id: key,
                    name: label ?? ownerName,
                    ownerName: ownerName,
                    ownerURL: app.bundleURL,
                    frame: frame(of: item),
                    element: item
                ))
            }
        }
        // Left to right, the order they sit in the menu bar.
        return extras.sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let position: AXValue = value(element, kAXPositionAttribute) {
            AXValueGetValue(position, .cgPoint, &origin)
        }
        if let extent: AXValue = value(element, kAXSizeAttribute) {
            AXValueGetValue(extent, .cgSize, &size)
        }
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
