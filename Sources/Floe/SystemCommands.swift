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

    func perform() {
        switch self {
        case .lockScreen:
            lockScreen()
        case .sleep:
            runPmset(arguments: ["sleepnow"])
        case .sleepDisplays:
            runPmset(arguments: ["displaysleepnow"])
        case .restart:
            runAppleScript(#"tell application "System Events" to restart"#)
        case .shutDown:
            runAppleScript(#"tell application "System Events" to shut down"#)
        case .logOut:
            runAppleScript(#"tell application "System Events" to log out"#)
        case .emptyTrash:
            runAppleScript(#"tell application "Finder" to empty trash"#)
        case .toggleAppearance:
            runAppleScript(#"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#)
        case .hideOtherApps:
            hideOtherApps()
        case .quitAllApps:
            quitAllApps()
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
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            guard let error, let number = error[NSAppleScript.errorNumber] as? Int else { return }
            DispatchQueue.main.async {
                if number == -1743 {
                    let alert = NSAlert()
                    alert.messageText = "Floe needs permission to control System Events and Finder."
                    alert.informativeText = "Allow it in System Settings, Privacy and Security, Automation."
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn,
                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                    {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = (error[NSAppleScript.errorMessage] as? String) ?? "The system command failed."
                    alert.runModal()
                }
            }
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
