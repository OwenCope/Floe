//
//  OnboardingWelcomeView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: the copy describes Floe, and the quiet exit skips the setup
//  instead of quitting, because Floe is usable without it.

import AppKit
import SwiftUI
import ThawUI

/// Capsules fit or scale uneven label lengths, with fuller claims in accessibility labels; matched spacers center the stack.
struct OnboardingWelcomeView: View {
    var onContinue: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Matched spacers center content; minimum spacing handles Larger Text with no spare height.
            Spacer(minLength: ThawSpacing.gutter)

            // VoiceOver skips the decorative icon because the title identifies the app.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 116)
                .thawShadow(.hero)
                .accessibilityHidden(true)

            copyBlock
                .padding(.top, ThawSpacing.inset)

            Button(action: onContinue) {
                Text("Continue")
                    .font(ThawType.heading)
                    .frame(minWidth: 140, minHeight: 34)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.top, ThawSpacing.section)

            Spacer(minLength: ThawSpacing.gutter)
        }
        .padding(.horizontal, ThawSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Offer a quiet exit before permissions so nobody has to sit through the setup.
        .overlay(alignment: .bottomTrailing) {
            Button(action: onSkip) {
                Text("Skip Setup")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close this window and start using \(AppInfo.displayName)")
            .padding(.trailing, ThawSpacing.gutter)
            .padding(.bottom, ThawSpacing.inset)
        }
        .background(VisualEffectBackground())
    }

    /// Keep the reading sequence together so centering spacers move it as one block.
    private var copyBlock: some View {
        VStack(spacing: 0) {
            Text(verbatim: "Welcome to \(AppInfo.displayName)")
                .font(ThawType.display)
                .multilineTextAlignment(.center)

            Text(verbatim: "\(AppInfo.displayName) is a launcher for your apps and commands. It runs Raycast extensions and searches your menu bar.")
                .font(ThawType.heading)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
                .padding(.top, ThawSpacing.compact)

            factsRow
                .padding(.top, ThawSpacing.gutter)
        }
    }

    /// Present pre-permission facts in one glanceable row.
    private var factsRow: some View {
        HStack(spacing: ThawSpacing.base) {
            fact(symbol: "lock.open", label: "Open source", spoken: "Free and open source")
            fact(symbol: "hand.raised", label: "No analytics or tracking", spoken: "No analytics, no tracking")
            fact(symbol: "checkmark.shield", label: "Permissions optional", spoken: "Every permission is optional")
        }
        .frame(maxWidth: 520)
    }

    /// Scale a long label rather than wrapping one capsule taller than its neighbours.
    private func fact(symbol: String, label: String, spoken: String) -> some View {
        HStack(spacing: ThawSpacing.compact) {
            Image(systemName: symbol)
                .font(ThawType.symbol)
                .foregroundStyle(.secondary)

            Text(verbatim: label)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, ThawSpacing.inset)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .thawGlass(.control, in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}
