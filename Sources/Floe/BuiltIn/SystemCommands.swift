//
//  SystemCommands.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Subprocess
import System

enum SystemCommand: String, CaseIterable, Identifiable {
    case lockScreen
    case sleep
    case sleepDisplays
    case restart
    case shutDown
    case logOut
    case emptyTrash
    case toggleAppearance
    case toggleWiFi
    case toggleMute
    case toggleKeepAwake
    case hideOtherApps
    case quitAllApps

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .sleepDisplays: return "Sleep Displays"
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        case .logOut: return "Log Out"
        case .emptyTrash: return "Empty Trash"
        case .toggleAppearance: return "Toggle Dark Mode"
        case .toggleWiFi: return "Toggle Wi-Fi"
        case .toggleMute: return "Toggle Mute"
        case .toggleKeepAwake: return "Toggle Keep Awake"
        case .hideOtherApps: return "Hide Other Apps"
        case .quitAllApps: return "Quit All Apps"
        }
    }

    var symbol: String {
        switch self {
        case .lockScreen: return "lock"
        case .sleep: return "moon"
        case .sleepDisplays: return "display"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .emptyTrash: return "trash"
        case .toggleAppearance: return "circle.lefthalf.filled"
        case .toggleWiFi: return "wifi"
        case .toggleMute: return "speaker.slash"
        case .toggleKeepAwake: return "cup.and.saucer"
        case .hideOtherApps: return "eye.slash"
        case .quitAllApps: return "xmark.square"
        }
    }

    var keywords: [String] {
        switch self {
        case .lockScreen: return ["lock", "screen"]
        case .sleep: return ["sleep", "rest"]
        case .sleepDisplays: return ["sleep", "displays", "screen off", "monitor"]
        case .restart: return ["restart", "reboot"]
        case .shutDown: return ["shut down", "shutdown", "power off", "turn off"]
        case .logOut: return ["log out", "logout", "sign out"]
        case .emptyTrash: return ["empty trash", "trash", "delete trash"]
        case .toggleAppearance: return ["dark mode", "light mode", "appearance", "theme"]
        case .toggleWiFi: return ["wifi", "wireless", "airport", "turn wi-fi off", "turn wi-fi on"]
        case .toggleMute: return ["mute", "unmute", "sound", "volume", "silence"]
        case .toggleKeepAwake: return ["caffeinate", "awake", "prevent sleep", "no sleep"]
        case .hideOtherApps: return ["hide", "hide other apps", "hide others"]
        case .quitAllApps: return ["quit all apps", "quit all", "close all apps"]
        }
    }

    var confirmation: String? {
        switch self {
        case .restart: return "Restart your Mac now?"
        case .shutDown: return "Shut down your Mac now?"
        case .logOut: return "Log out now?"
        case .emptyTrash: return "Empty the Trash? This can't be undone."
        case .quitAllApps: return "Quit all apps now?"
        default: return nil
        }
    }

    /// What a command that flips a setting does, which answers with the line for the HUD.
    var flip: (() -> String)? {
        switch self {
        case .toggleWiFi: SystemToggle.flipWiFi
        case .toggleMute: SystemToggle.flipMute
        case .toggleKeepAwake: SystemToggle.flipKeepAwake
        default: nil
        }
    }

    /// What the commands that go through System Events or Finder tell it.
    private var appleScript: String? {
        switch self {
        case .restart: #"tell application "System Events" to restart"#
        case .shutDown: #"tell application "System Events" to shut down"#
        case .logOut: #"tell application "System Events" to log out"#
        case .emptyTrash: #"tell application "Finder" to empty trash"#
        case .toggleAppearance: #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
        default: nil
        }
    }

    func perform() {
        if let appleScript {
            runAppleScript(appleScript)
            return
        }
        switch self {
        case .lockScreen:
            lockScreen()
        case .sleep:
            runPmset(arguments: ["sleepnow"])
        case .sleepDisplays:
            runPmset(arguments: ["displaysleepnow"])
        case .hideOtherApps:
            hideOtherApps()
        case .quitAllApps:
            quitAllApps()
        default:
            _ = flip?()
        }
    }

    private func lockScreen() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let sym = dlsym(handle, "SACLockScreenImmediate") else { return }
        typealias LockFn = @convention(c) () -> Void
        unsafeBitCast(sym, to: LockFn.self)()
    }

    private func runPmset(arguments: [String]) {
        Task {
            _ = try? await Subprocess.run(.path("/usr/bin/pmset"), arguments: Arguments(arguments), output: .discarded)
        }
    }

    private func runAppleScript(_ source: String) {
        AppleScript.execute(source, qos: .utility) { execution in
            guard execution.errorNumber != nil else { return }
            if execution.isRefused {
                Self.askForAutomation(toControl: "System Events and Finder")
            } else {
                let alert = NSAlert()
                alert.messageText = execution.errorMessage ?? "The system command failed."
                alert.runModal()
            }
        }
    }

    /// What to show when macOS refused a script (error -1743): the pane where it is allowed.
    static func askForAutomation(toControl apps: String) {
        let alert = NSAlert()
        alert.messageText = "Floe needs permission to control \(apps)."
        alert.informativeText = "Allow it in System Settings, Privacy and Security, Automation."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func hideOtherApps() {
        let workspace = NSWorkspace.shared
        let frontmostPID = workspace.frontmostApplication?.processIdentifier
        for app in workspace.runningApplications
            where app.activationPolicy == .regular && app.processIdentifier != frontmostPID
        {
            app.hide()
        }
    }

    private func quitAllApps() {
        let me = ProcessInfo.processInfo.processIdentifier
        let myself = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if app.processIdentifier == me {
                continue
            }
            if app.bundleIdentifier == "com.apple.finder" {
                continue
            }
            if let myself, app.bundleIdentifier == myself {
                continue
            }
            app.terminate()
        }
    }
}
