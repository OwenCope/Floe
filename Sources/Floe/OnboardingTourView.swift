//
//  OnboardingTourView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The middle of onboarding: what Floe does, before it asks for anything.
struct OnboardingTourView: View {
    @ObservedObject private var settings = AppSettings.shared

    let continueTitle: String
    var onContinue: () -> Void

    private var hotkeyText: String {
        if let hotkey = settings.toggleHotkey {
            return "Press \(hotkey.displayValue) to show or hide Floe from any app. You can change the hotkey in Settings."
        }
        return "Open Floe from its menu bar icon. You can set a hotkey in Settings."
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("How Floe works")
                    .font(ThawType.display)
                Text("Type to find an app or a command, then press Return.")
                    .font(ThawType.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            // Matched spacers center the cards between the heading and the button.
            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 14) {
                card(symbol: "keyboard", title: "Open it with a hotkey", text: hotkeyText)
                card(
                    symbol: "puzzlepiece.extension",
                    title: "Run Raycast extensions",
                    text: "Floe runs the extensions in its own folder and the ones you have installed in Raycast."
                )
                card(
                    symbol: "menubar.rectangle",
                    title: "Search the menu bar",
                    text: "Find a menu bar item by name and open its menu. This is the one feature that needs Accessibility."
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

            Spacer(minLength: 0)

            Button(action: onContinue) {
                Text(verbatim: continueTitle)
                    .font(ThawType.heading)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
    }

    private func card(symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: ThawSpacing.base) {
            GlassIconBubble(symbol: symbol, size: 44)
                .thawGlass(.control, in: RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(ThawType.heading)
            Text(verbatim: text)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
