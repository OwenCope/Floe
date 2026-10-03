//
//  PermissionsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Settings → General: each permission's state with the button that grants it, and a way back to the welcome window.
struct PermissionsSettingsSection: View {
    var permissions: AppPermissions = .shared

    var body: some View {
        ThawSection("Permissions") {
            ForEach(permissions.allPermissions) { permission in
                LabeledContent {
                    PermissionStatusControl(permission: permission)
                } label: {
                    PermissionLabel(permission: permission)
                    if let detail = permission.details.first {
                        Text(verbatim: detail)
                    }
                }
            }
            LabeledContent {
                Button("Show Welcome") { OnboardingWindowController.shared.showIfNeeded(replayRequested: true) }
            } label: {
                Text("Welcome window")
                Text("The introduction from the first launch.")
            }
        }
        // The grant happens in System Settings; look again whenever this page comes back.
        .onAppear { permissions.refreshPermissionsState() }
    }
}
