//
//  LauncherAppearance.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// A colour that survives settings persistence as sRGB components, so the
/// stored shape never depends on SwiftUI's own colour encoding.
struct StoredColor: Codable, Hashable {
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var opacity = 1.0

    init() {}

    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        opacity = Double(resolved.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// How the launcher panel is tinted: Thaw's menu-bar tints, applied to the
/// launcher's glass instead of to the menu bar.
enum LauncherTintKind: String, Codable, CaseIterable, Identifiable {
    case none
    case solid
    case gradient

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .none: "None"
        case .solid: "Solid"
        case .gradient: "Gradient"
        }
    }
}

/// A two-stop linear gradient by angle in degrees; 0 runs top to bottom.
struct LauncherGradient: Codable, Hashable {
    var top = StoredColor(Color(red: 0.2, green: 0.4, blue: 0.95))
    var bottom = StoredColor(Color(red: 0.55, green: 0.25, blue: 0.9))
    var angle = 180.0

    var style: AnyShapeStyle {
        let radians = angle * .pi / 180
        let start = UnitPoint(x: 0.5 - sin(radians) / 2, y: 0.5 - cos(radians) / 2)
        return AnyShapeStyle(LinearGradient(
            colors: [top.color, bottom.color],
            startPoint: start,
            endPoint: UnitPoint(x: 1 - start.x, y: 1 - start.y)
        ))
    }
}

/// The tint drawn over the launcher's glass: the kind, its colours, and how
/// strongly it reads. Thaw's tints sit far below full opacity, so the glass
/// keeps its depth under the colour.
struct LauncherTint: Codable, Hashable {
    var kind = LauncherTintKind.none
    var solid = StoredColor(Color(red: 0.2, green: 0.35, blue: 0.9))
    var gradient = LauncherGradient()
    var opacity = 0.35

    /// The overlay style for the panel's shape, or nil when no tint is set.
    var overlayStyle: AnyShapeStyle? {
        switch kind {
        case .none: nil
        case .solid: AnyShapeStyle(solid.color.opacity(opacity))
        case .gradient: AnyShapeStyle(gradient.style.opacity(opacity))
        }
    }
}

/// A stroke drawn around the launcher's rounded shape.
struct LauncherBorder: Codable, Hashable {
    var color = StoredColor(Color.white.opacity(0.6))
    var width = 1.0
}
