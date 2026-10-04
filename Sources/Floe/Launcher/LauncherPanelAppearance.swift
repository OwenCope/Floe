//
//  LauncherPanelAppearance.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The launcher's glass, tint, border and shadow, layered in that order under the content.
/// The shadow follows the rounded shape: the window's own is a square, `margin` larger than the launcher.
struct LauncherPanelAppearance: ViewModifier {
    let glass: LauncherGlass
    let tint: LauncherTint
    let border: LauncherBorder?
    let hasShadow: Bool

    init(glass: LauncherGlass, tint: LauncherTint, border: LauncherBorder?, hasShadow: Bool) {
        self.glass = glass
        self.tint = tint
        self.border = border
        self.hasShadow = hasShadow
    }

    init(_ look: LauncherLook) {
        self.init(glass: look.glass, tint: look.tint, border: look.border, hasShadow: look.hasShadow)
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.panel, style: .continuous)
    }

    func body(content: Content) -> some View {
        let style = glass.resolvedStyle()
        // The tint is the content's background, so the order is glass, tint,
        // content: a colour wash must never sit on top of the launcher's text.
        let tinted = content.background {
            if let style = tint.backgroundStyle {
                shape.fill(style)
            }
        }
        let glazed = Group {
            // Regular is the panel's own glass, which also knows what to draw
            // when the system has transparency turned down.
            if style == .regular || reduceTransparency {
                tinted.thawGlass(.panel, in: shape)
            } else {
                tinted
                    // The fade is black at the top whatever the appearance, so
                    // the content over it is always the dark one's.
                    .environment(\.colorScheme, style.usesDarkFade ? .dark : colorScheme)
                    .background {
                        LauncherGlassBackdrop(style: style, tint: glass.tintColor(for: style), cornerRadius: ThawRadius.panel)
                    }
            }
        }
        let bordered = Group {
            if let border {
                glazed.overlay(shape.strokeBorder(border.color.color, lineWidth: border.width))
            } else {
                glazed
            }
        }
        return Group {
            if hasShadow {
                bordered.shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            } else {
                bordered
            }
        }
    }
}
