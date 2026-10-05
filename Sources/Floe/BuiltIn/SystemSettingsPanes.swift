//
//  SystemSettingsPanes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One pane of System Settings, opened from the root search.
nonisolated struct SystemSettingsPane: Identifiable, Hashable, Sendable {
    /// The pane's extension identifier, which is also what its link names.
    let identifier: String
    let title: String
    let symbol: String
    let keywords: [String]
    /// The pane's own bundle, when macOS has an icon of its own for it. Nil draws the symbol.
    var iconPath: String?

    var id: String {
        identifier
    }

    var url: URL? {
        URL(string: "x-apple.systempreferences:\(identifier)")
    }
}

nonisolated extension SystemSettingsPane {
    /// What Floe knows about a pane beyond what the pane says of itself.
    struct Known {
        /// Used when the pane carries no localized name of its own.
        let title: String
        let symbol: String
        var keywords: [String] = []
    }

    static let fallbackSymbol = "gearshape"

    /// Panes are found on disk, so this table never decides which ones exist: it gives the found
    /// ones a symbol and the words people type for them, and a name where the pane has none.
    static let known: [String: Known] = [
        "com.apple.systempreferences.AppleIDSettings": Known(
            title: String(localized: "Apple Account (System Settings)", defaultValue: "Apple Account", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "person.crop.circle",
            keywords: String(localized: "apple id, icloud", bundle: .floe, comment: "Words that find the Apple Account pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.wifi-settings-extension": Known(
            title: "Wi-Fi",
            symbol: "wifi",
            keywords: String(localized: "wifi, wireless, internet", bundle: .floe, comment: "Words that find the Wi-Fi pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.BluetoothSettings": Known(
            title: "Bluetooth",
            symbol: "wave.3.right",
            keywords: String(localized: "headphones, pair", bundle: .floe, comment: "Words that find the Bluetooth pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Network-Settings.extension": Known(
            title: String(localized: "Network (System Settings)", defaultValue: "Network", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "network",
            keywords: String(localized: "ethernet, dns, proxy, firewall", bundle: .floe, comment: "Words that find the Network pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension": Known(
            title: "VPN",
            symbol: "lock.shield"
        ),
        "com.apple.Battery-Settings.extension": Known(
            title: String(localized: "Battery (System Settings)", defaultValue: "Battery", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "battery.75percent",
            keywords: String(localized: "energy, power, low power mode", bundle: .floe, comment: "Words that find the Battery pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.systempreferences.GeneralSettings": Known(
            title: String(localized: "General (System Settings)", defaultValue: "General", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "gearshape"
        ),
        "com.apple.SystemProfiler.AboutExtension": Known(
            title: String(localized: "About (System Settings)", defaultValue: "About", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "info.circle",
            keywords: String(localized: "about this mac, serial number", bundle: .floe, comment: "Words that find the About pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Software-Update-Settings.extension": Known(
            title: String(localized: "Software Update (System Settings)", defaultValue: "Software Update", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "arrow.down.circle",
            keywords: String(localized: "macos update, upgrade", bundle: .floe, comment: "Words that find the Software Update pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.settings.Storage": Known(
            title: String(localized: "Storage (System Settings)", defaultValue: "Storage", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "internaldrive",
            keywords: String(localized: "disk space", bundle: .floe, comment: "Words that find the Storage pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.AirDrop-Handoff-Settings.extension": Known(
            title: String(localized: "AirDrop & Handoff (System Settings)", defaultValue: "AirDrop & Handoff", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "airplayvideo",
            keywords: String(localized: "airdrop, handoff, airplay, continuity", bundle: .floe, comment: "Words that find the AirDrop & Handoff pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.LoginItems-Settings.extension": Known(
            title: String(localized: "Login Items (System Settings)", defaultValue: "Login Items", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "list.bullet.rectangle",
            keywords: String(localized: "startup, background items, extensions", bundle: .floe, comment: "Words that find the Login Items pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Localization-Settings.extension": Known(
            title: String(localized: "Language & Region (System Settings)", defaultValue: "Language & Region", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "globe"
        ),
        "com.apple.Date-Time-Settings.extension": Known(
            title: String(localized: "Date & Time (System Settings)", defaultValue: "Date & Time", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "clock",
            keywords: String(localized: "time zone, timezone", bundle: .floe, comment: "Words that find the Date & Time pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Sharing-Settings.extension": Known(
            title: String(localized: "Sharing (System Settings)", defaultValue: "Sharing", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "square.and.arrow.up",
            keywords: String(localized: "screen sharing, file sharing, remote login, computer name", bundle: .floe, comment: "Words that find the Sharing pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Time-Machine-Settings.extension": Known(
            title: "Time Machine",
            symbol: "clock.arrow.circlepath",
            keywords: String(localized: "backup", bundle: .floe, comment: "Words that find the Time Machine pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Transfer-Reset-Settings.extension": Known(
            title: String(localized: "Transfer or Reset (System Settings)", defaultValue: "Transfer or Reset", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "arrow.triangle.2.circlepath",
            keywords: String(localized: "erase, migration", bundle: .floe, comment: "Words that find the Transfer or Reset pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Startup-Disk-Settings.extension": Known(
            title: String(localized: "Startup Disk (System Settings)", defaultValue: "Startup Disk", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "externaldrive"
        ),
        "com.apple.Accessibility-Settings.extension": Known(
            title: String(localized: "Accessibility (System Settings)", defaultValue: "Accessibility", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "accessibility",
            keywords: String(localized: "voiceover, zoom, reduce motion", bundle: .floe, comment: "Words that find the Accessibility pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Appearance-Settings.extension": Known(
            title: String(localized: "Appearance (System Settings)", defaultValue: "Appearance", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "circle.lefthalf.filled",
            keywords: String(localized: "dark mode, light mode, accent color, liquid glass", bundle: .floe, comment: "Words that find the Appearance pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.ControlCenter-Settings.extension": Known(
            title: String(localized: "Control Center (System Settings)", defaultValue: "Control Center", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "switch.2",
            keywords: String(localized: "menu bar", bundle: .floe, comment: "Words that find the Control Center pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Desktop-Settings.extension": Known(
            title: String(localized: "Desktop & Dock (System Settings)", defaultValue: "Desktop & Dock", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "dock.rectangle",
            keywords: String(localized: "dock, stage manager, mission control, hot corners, widgets", bundle: .floe, comment: "Words that find the Desktop & Dock pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Displays-Settings.extension": Known(
            title: String(localized: "Displays (System Settings)", defaultValue: "Displays", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "display",
            keywords: String(localized: "monitor, screen, resolution, night shift, brightness", bundle: .floe, comment: "Words that find the Displays pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Siri-Settings.extension": Known(
            title: "Siri",
            symbol: "mic",
            keywords: String(localized: "apple intelligence", bundle: .floe, comment: "Words that find the Siri pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Spotlight-Settings.extension": Known(
            title: "Spotlight",
            symbol: "magnifyingglass"
        ),
        "com.apple.Wallpaper-Settings.extension": Known(
            title: String(localized: "Wallpaper (System Settings)", defaultValue: "Wallpaper", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "photo",
            keywords: String(localized: "desktop picture, background", bundle: .floe, comment: "Words that find the Wallpaper pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.ScreenSaver-Settings.extension": Known(
            title: String(localized: "Screen Saver (System Settings)", defaultValue: "Screen Saver", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "sparkles.tv"
        ),
        "com.apple.Notifications-Settings.extension": Known(
            title: String(localized: "Notifications (System Settings)", defaultValue: "Notifications", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "bell.badge",
            keywords: String(localized: "alerts, banners", bundle: .floe, comment: "Words that find the Notifications pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Sound-Settings.extension": Known(
            title: String(localized: "Sound (System Settings)", defaultValue: "Sound", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "speaker.wave.2",
            keywords: String(localized: "volume, audio, output, input, microphone", bundle: .floe, comment: "Words that find the Sound pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Focus-Settings.extension": Known(
            title: String(localized: "Focus (System Settings)", defaultValue: "Focus", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "moon",
            keywords: String(localized: "do not disturb, dnd", bundle: .floe, comment: "Words that find the Focus pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Screen-Time-Settings.extension": Known(
            title: String(localized: "Screen Time (System Settings)", defaultValue: "Screen Time", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "hourglass",
            keywords: String(localized: "downtime, app limits", bundle: .floe, comment: "Words that find the Screen Time pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Lock-Screen-Settings.extension": Known(
            title: String(localized: "Lock Screen (System Settings)", defaultValue: "Lock Screen", bundle: .floe, comment: "The name of a pane of System Settings, which is a place and not a command."),
            symbol: "lock.display",
            keywords: String(localized: "screen lock, turn display off", bundle: .floe, comment: "Words that find the Lock Screen pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.settings.PrivacySecurity.extension": Known(
            title: String(localized: "Privacy & Security (System Settings)", defaultValue: "Privacy & Security", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "hand.raised",
            keywords: String(localized: "permissions, filevault, full disk access, screen recording, automation, location", bundle: .floe, comment: "Words that find the Privacy & Security pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Touch-ID-Settings.extension": Known(
            title: String(localized: "Touch ID & Password (System Settings)", defaultValue: "Touch ID & Password", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "touchid",
            keywords: String(localized: "fingerprint, login password", bundle: .floe, comment: "Words that find the Touch ID & Password pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Users-Groups-Settings.extension": Known(
            title: String(localized: "Users & Groups (System Settings)", defaultValue: "Users & Groups", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "person.2",
            keywords: String(localized: "accounts, guest user", bundle: .floe, comment: "Words that find the Users & Groups pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Internet-Accounts-Settings.extension": Known(
            title: String(localized: "Internet Accounts (System Settings)", defaultValue: "Internet Accounts", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "at",
            keywords: String(localized: "mail accounts, google, exchange", bundle: .floe, comment: "Words that find the Internet Accounts pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Game-Center-Settings.extension": Known(
            title: "Game Center",
            symbol: "gamecontroller"
        ),
        "com.apple.Game-Controller-Settings.extension": Known(
            title: String(localized: "Game Controllers (System Settings)", defaultValue: "Game Controllers", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "gamecontroller"
        ),
        "com.apple.WalletSettingsExtension": Known(
            title: String(localized: "Wallet & Apple Pay (System Settings)", defaultValue: "Wallet & Apple Pay", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "creditcard"
        ),
        "com.apple.Keyboard-Settings.extension": Known(
            title: String(localized: "Keyboard (System Settings)", defaultValue: "Keyboard", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "keyboard",
            keywords: String(localized: "keyboard shortcuts, input sources, dictation, text replacements", bundle: .floe, comment: "Words that find the Keyboard pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Mouse-Settings.extension": Known(
            title: String(localized: "Mouse (System Settings)", defaultValue: "Mouse", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "computermouse",
            keywords: String(localized: "scroll direction, tracking speed", bundle: .floe, comment: "Words that find the Mouse pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Trackpad-Settings.extension": Known(
            title: String(localized: "Trackpad (System Settings)", defaultValue: "Trackpad", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "rectangle.and.hand.point.up.left",
            keywords: String(localized: "gestures, tap to click", bundle: .floe, comment: "Words that find the Trackpad pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Print-Scan-Settings.extension": Known(
            title: String(localized: "Printers & Scanners (System Settings)", defaultValue: "Printers & Scanners", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "printer"
        ),
        "com.apple.Family-Settings.extension": Known(
            title: String(localized: "Family (System Settings)", defaultValue: "Family", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "figure.2.and.child.holdinghands",
            keywords: String(localized: "family sharing", bundle: .floe, comment: "Words that find the Family pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Profiles-Settings.extension": Known(
            title: String(localized: "Device Management (System Settings)", defaultValue: "Device Management", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "checkmark.shield",
            keywords: String(localized: "profiles, mdm", bundle: .floe, comment: "Words that find the Device Management pane of System Settings, separated by commas.").keywordList
        ),
        "com.apple.Coverage-Settings.extension": Known(
            title: String(localized: "AppleCare & Warranty (System Settings)", defaultValue: "AppleCare & Warranty", bundle: .floe, comment: "The name of a pane of System Settings."),
            symbol: "checkmark.seal",
            keywords: String(localized: "applecare, coverage", bundle: .floe, comment: "Words that find the AppleCare & Warranty pane of System Settings, separated by commas.").keywordList
        ),
    ]

    /// Panes that open on a prompt the system raises itself, or only with hardware attached.
    static let hidden: Set<String> = [
        "com.apple.FollowUpSettings.FollowUpSettingsExtension",
        "com.apple.HeadphoneSettings",
    ]

    /// A pane as the root search lists it, or nil when it has neither a name of its own nor a known one.
    static func pane(identifier: String, localizedName: String?) -> SystemSettingsPane? {
        guard !hidden.contains(identifier) else { return nil }
        let known = known[identifier]
        guard let title = localizedName ?? known?.title else { return nil }
        return SystemSettingsPane(
            identifier: identifier,
            title: title,
            symbol: known?.symbol ?? fallbackSymbol,
            // The known title stays findable when the system calls the pane something else.
            keywords: (known?.keywords ?? []) + (known.map(\.title).flatMap { $0 == title ? nil : [$0.lowercased()] } ?? [])
        )
    }
}

nonisolated extension SystemSettingsPane {
    private static let extensionsFolder = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    /// The panes this Mac's System Settings has, by name. Reads a few hundred small property lists,
    /// so it runs in the catalog worker.
    static func scan(folder: URL = extensionsFolder) -> [SystemSettingsPane] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let found = entries.compactMap { url -> (pane: SystemSettingsPane, url: URL)? in
            // The property list is read as a file first: a Bundle stays in memory for good, and most extensions here are not panes.
            guard url.pathExtension == "appex",
                  let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
                  let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier
            else { return nil }
            // Only the localized table is trusted: the plain Info.plist names are internal ones like "PowerPreferences".
            let localized = bundle.localizedInfoDictionary
            let name = (localized?["CFBundleDisplayName"] ?? localized?["CFBundleName"]) as? String
            return pane(identifier: identifier, localizedName: name).map { ($0, url) }
        }
        return found.map { $0.pane.withIcon(at: $0.url.path) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Panes macOS has no icon of its own for: their bundle draws as the generic extension block.
    static let withoutOwnIcon: Set<String> = [
        "com.apple.Battery-Settings.extension",
        "com.apple.HeadphoneSettings",
    ]

    /// The pane with its bundle as its icon, which is the picture System Settings shows for it.
    func withIcon(at bundlePath: String) -> SystemSettingsPane {
        var pane = self
        pane.iconPath = Self.withoutOwnIcon.contains(identifier) ? nil : bundlePath
        return pane
    }
}
