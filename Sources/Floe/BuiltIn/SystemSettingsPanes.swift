//
//  SystemSettingsPanes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One pane of System Settings, opened from the root search.
struct SystemSettingsPane: Identifiable, Hashable, Sendable {
    /// The pane's extension identifier, which is also what its link names.
    let identifier: String
    let title: String
    let symbol: String
    let keywords: [String]

    var id: String {
        identifier
    }

    var url: URL? {
        URL(string: "x-apple.systempreferences:\(identifier)")
    }
}

extension SystemSettingsPane {
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
        "com.apple.systempreferences.AppleIDSettings": Known(title: "Apple Account", symbol: "person.crop.circle", keywords: ["apple id", "icloud"]),
        "com.apple.wifi-settings-extension": Known(title: "Wi-Fi", symbol: "wifi", keywords: ["wifi", "wireless", "internet"]),
        "com.apple.BluetoothSettings": Known(title: "Bluetooth", symbol: "dot.radiowaves.left.and.right", keywords: ["headphones", "pair"]),
        "com.apple.Network-Settings.extension": Known(title: "Network", symbol: "network", keywords: ["ethernet", "dns", "proxy", "firewall"]),
        "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension": Known(title: "VPN", symbol: "lock.shield"),
        "com.apple.Battery-Settings.extension": Known(title: "Battery", symbol: "battery.75percent", keywords: ["energy", "power", "low power mode"]),
        "com.apple.systempreferences.GeneralSettings": Known(title: "General", symbol: "gearshape"),
        "com.apple.SystemProfiler.AboutExtension": Known(title: "About", symbol: "info.circle", keywords: ["about this mac", "serial number"]),
        "com.apple.Software-Update-Settings.extension": Known(title: "Software Update", symbol: "arrow.down.circle", keywords: ["macos update", "upgrade"]),
        "com.apple.settings.Storage": Known(title: "Storage", symbol: "internaldrive", keywords: ["disk space"]),
        "com.apple.AirDrop-Handoff-Settings.extension": Known(title: "AirDrop & Handoff", symbol: "airplayvideo", keywords: ["airdrop", "handoff", "airplay", "continuity"]),
        "com.apple.LoginItems-Settings.extension": Known(title: "Login Items", symbol: "list.bullet.rectangle", keywords: ["startup", "background items", "extensions"]),
        "com.apple.Localization-Settings.extension": Known(title: "Language & Region", symbol: "globe"),
        "com.apple.Date-Time-Settings.extension": Known(title: "Date & Time", symbol: "clock", keywords: ["time zone", "timezone"]),
        "com.apple.Sharing-Settings.extension": Known(title: "Sharing", symbol: "square.and.arrow.up", keywords: ["screen sharing", "file sharing", "remote login", "computer name"]),
        "com.apple.Time-Machine-Settings.extension": Known(title: "Time Machine", symbol: "clock.arrow.circlepath", keywords: ["backup"]),
        "com.apple.Transfer-Reset-Settings.extension": Known(title: "Transfer or Reset", symbol: "arrow.triangle.2.circlepath", keywords: ["erase", "migration"]),
        "com.apple.Startup-Disk-Settings.extension": Known(title: "Startup Disk", symbol: "externaldrive"),
        "com.apple.Accessibility-Settings.extension": Known(title: "Accessibility", symbol: "accessibility", keywords: ["voiceover", "zoom", "reduce motion"]),
        "com.apple.Appearance-Settings.extension": Known(title: "Appearance", symbol: "circle.lefthalf.filled", keywords: ["dark mode", "light mode", "accent color", "liquid glass"]),
        "com.apple.ControlCenter-Settings.extension": Known(title: "Control Center", symbol: "switch.2", keywords: ["menu bar"]),
        "com.apple.Desktop-Settings.extension": Known(title: "Desktop & Dock", symbol: "dock.rectangle", keywords: ["dock", "stage manager", "mission control", "hot corners", "widgets"]),
        "com.apple.Displays-Settings.extension": Known(title: "Displays", symbol: "display", keywords: ["monitor", "screen", "resolution", "night shift", "brightness"]),
        "com.apple.Siri-Settings.extension": Known(title: "Siri", symbol: "mic", keywords: ["apple intelligence"]),
        "com.apple.Spotlight-Settings.extension": Known(title: "Spotlight", symbol: "magnifyingglass"),
        "com.apple.Wallpaper-Settings.extension": Known(title: "Wallpaper", symbol: "photo", keywords: ["desktop picture", "background"]),
        "com.apple.ScreenSaver-Settings.extension": Known(title: "Screen Saver", symbol: "sparkles.tv"),
        "com.apple.Notifications-Settings.extension": Known(title: "Notifications", symbol: "bell.badge", keywords: ["alerts", "banners"]),
        "com.apple.Sound-Settings.extension": Known(title: "Sound", symbol: "speaker.wave.2", keywords: ["volume", "audio", "output", "input", "microphone"]),
        "com.apple.Focus-Settings.extension": Known(title: "Focus", symbol: "moon", keywords: ["do not disturb", "dnd"]),
        "com.apple.Screen-Time-Settings.extension": Known(title: "Screen Time", symbol: "hourglass", keywords: ["downtime", "app limits"]),
        "com.apple.Lock-Screen-Settings.extension": Known(title: "Lock Screen", symbol: "lock.display", keywords: ["screen lock", "turn display off"]),
        "com.apple.settings.PrivacySecurity.extension": Known(title: "Privacy & Security", symbol: "hand.raised", keywords: ["permissions", "filevault", "full disk access", "screen recording", "automation", "location"]),
        "com.apple.Touch-ID-Settings.extension": Known(title: "Touch ID & Password", symbol: "touchid", keywords: ["fingerprint", "login password"]),
        "com.apple.Users-Groups-Settings.extension": Known(title: "Users & Groups", symbol: "person.2", keywords: ["accounts", "guest user"]),
        "com.apple.Internet-Accounts-Settings.extension": Known(title: "Internet Accounts", symbol: "at", keywords: ["mail accounts", "google", "exchange"]),
        "com.apple.Game-Center-Settings.extension": Known(title: "Game Center", symbol: "gamecontroller"),
        "com.apple.Game-Controller-Settings.extension": Known(title: "Game Controllers", symbol: "gamecontroller"),
        "com.apple.WalletSettingsExtension": Known(title: "Wallet & Apple Pay", symbol: "creditcard"),
        "com.apple.Keyboard-Settings.extension": Known(title: "Keyboard", symbol: "keyboard", keywords: ["keyboard shortcuts", "input sources", "dictation", "text replacements"]),
        "com.apple.Mouse-Settings.extension": Known(title: "Mouse", symbol: "computermouse", keywords: ["scroll direction", "tracking speed"]),
        "com.apple.Trackpad-Settings.extension": Known(title: "Trackpad", symbol: "rectangle.and.hand.point.up.left", keywords: ["gestures", "tap to click"]),
        "com.apple.Print-Scan-Settings.extension": Known(title: "Printers & Scanners", symbol: "printer"),
        "com.apple.Family-Settings.extension": Known(title: "Family", symbol: "figure.2.and.child.holdinghands", keywords: ["family sharing"]),
        "com.apple.Profiles-Settings.extension": Known(title: "Device Management", symbol: "checkmark.shield", keywords: ["profiles", "mdm"]),
        "com.apple.Coverage-Settings.extension": Known(title: "AppleCare & Warranty", symbol: "checkmark.seal", keywords: ["applecare", "coverage"]),
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

extension SystemSettingsPane {
    private static let extensionsFolder = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    /// The panes this Mac's System Settings has, by name. Reads a few hundred small property lists,
    /// so it runs in the catalog worker.
    static func scan(folder: URL = extensionsFolder) -> [SystemSettingsPane] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { url -> SystemSettingsPane? in
            guard url.pathExtension == "appex", let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier,
                  let attributes = bundle.object(forInfoDictionaryKey: "EXAppExtensionAttributes") as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint
            else { return nil }
            // Only the localized table is trusted: the plain Info.plist names are internal ones like "PowerPreferences".
            let localized = bundle.localizedInfoDictionary
            let name = (localized?["CFBundleDisplayName"] ?? localized?["CFBundleName"]) as? String
            return pane(identifier: identifier, localizedName: name)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
