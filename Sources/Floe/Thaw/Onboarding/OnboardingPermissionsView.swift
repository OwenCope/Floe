//
//  OnboardingPermissionsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: only the layout that lists every permission is kept, and its
//  button never waits for a grant, because Floe's launcher and extensions work without any.

import AppKit
import SwiftUI
import ThawUI

/// The permission step of onboarding. Each card grants its own permission;
/// the page's button moves on whatever has been granted.
struct ThawPermissionsView: View {
    private let permissions: AppPermissions
    /// The button's title once nothing is left to grant.
    private let finishTitle: String
    private let onContinue: () -> Void

    @State private var appeared = false

    /// - Parameters:
    ///   - permissions: Defaults to the app's shared permissions.
    ///   - finishTitle: The button's title once every permission is granted.
    ///   - onContinue: Called once the user has finished with the step.
    init(permissions: AppPermissions? = nil, finishTitle: String, onContinue: @escaping () -> Void) {
        self.permissions = permissions ?? .shared
        self.finishTitle = finishTitle
        self.onContinue = onContinue
    }

    private var continueTitle: String {
        switch permissions.permissionsState {
        case .hasAll: finishTitle
        case .missing: "Continue Without Menu Bar Search"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            HStack(alignment: .top, spacing: 14) {
                ForEach(permissions.allPermissions) { permission in
                    OnboardingPermissionCard(permission: permission)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 30)

            privacyPanel

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    // Preflight only: continuing must never raise a prompt.
                    permissions.refreshPermissionsState()
                    onContinue()
                } label: {
                    Text(verbatim: continueTitle)
                        .font(ThawType.heading)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)

                Text("You can grant either one later in Settings, under General.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(permissions.permissionsState == .hasAll ? 0 : 1)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .onAppear {
            // Preflight only: appearing must never raise a prompt.
            permissions.refreshPermissionsState()
            // A local curve because ThawMotion has no bouncy one.
            withThawAnimation(.spring(duration: 0.6, bounce: 0.3)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 7) {
            Text("Allow access")
                .font(ThawType.display)
                .multilineTextAlignment(.center)

            Text(verbatim: "Searching the menu bar needs Accessibility. The launcher and your extensions work without it.")
                .font(ThawType.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            privacyFact("No analytics or usage tracking")
            privacyFact("Permission checks stay on your Mac")
            privacyFact("Open source under the AGPL, so you can read how it works")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .padding(.horizontal, 30)
    }

    private func privacyFact(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(ThawType.micro.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 1.5)

            Text(verbatim: text)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingPermissionCard: View {
    let permission: Permission

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionLabel(
                permission: permission,
                titleFont: ThawType.heading,
                badgePlacement: .below
            )

            VStack(alignment: .leading, spacing: 5) {
                ForEach(permission.details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 6) {
                        // A 3pt bullet, not type: no text style is this small.
                        Image(systemName: "circle.fill")
                            .font(.system(size: 3))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 5)

                        Text(verbatim: detail)
                            .font(ThawType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            PermissionStatusControl(permission: permission, layout: .filled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .thawAnimation(ThawMotion.settle, value: permission.hasPermission)
    }
}
