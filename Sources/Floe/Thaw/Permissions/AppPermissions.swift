//
//  AppPermissions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: Floe asks only for Accessibility, so the Screen Recording,
//  Full Disk Access and Control Center grants, the diagnostics log and the preview protocol are
//  left out. The permission is injectable for tests.

import Foundation

/// A type that manages the permissions of the app.
@MainActor
@Observable
final class AppPermissions {
    static let shared = AppPermissions()

    /// The state of the app's granted permissions.
    enum PermissionsState: Equatable {
        /// At least one permission that menu bar search needs hasn't been granted.
        case missing
        /// Every permission has been granted.
        case hasAll
    }

    /// The permission for Accessibility features.
    let accessibility: Permission

    /// Fired after any permission's granted state transitions, for owners
    /// that must react to a specific grant.
    @ObservationIgnored
    var onPermissionTransition: ((Permission, Bool) -> Void)?

    /// The state of the app's granted permissions.
    private(set) var permissionsState: PermissionsState = .missing

    /// Every permission Floe can use.
    var allPermissions: [Permission] {
        [accessibility]
    }

    /// Creates a new permissions manager. Tests pass their own permission; nil uses the system's.
    init(accessibility: Permission? = nil) {
        self.accessibility = accessibility ?? AccessibilityPermission()
        self.updatePermissionsState()
        // Permission is @Observable, so changes arrive via onChange.
        for permission in allPermissions {
            permission.onChange = { [weak self] in
                guard let self else { return }
                updatePermissionsState()
                onPermissionTransition?(permission, permission.hasPermission)
            }
        }
    }

    /// Updates the current permissions state.
    private func updatePermissionsState() {
        permissionsState = allPermissions.allSatisfy(\.hasPermission) ? .hasAll : .missing
    }

    /// Refreshes permission grants from the system immediately.
    ///
    /// Also re-arms exhausted ungranted polls, since callers are surfaces the
    /// user is looking at.
    func refreshPermissionsState() {
        for permission in allPermissions {
            permission.resumePollingIfNeeded()
            permission.refreshStatus()
        }
        updatePermissionsState()
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}
