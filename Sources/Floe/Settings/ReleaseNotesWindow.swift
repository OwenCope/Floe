//
//  ReleaseNotesWindow.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// The window the release notes are read in. It is built when asked for and let go when closed.
@MainActor
enum ReleaseNotesWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.isReleasedWhenClosed = false
        created.title = "What’s New"
        created.contentView = NSHostingView(rootView: WhatsNewView())
        created.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: created, queue: .main) { _ in
            MainActor.assumeIsolated {
                window = nil
                closeObserver.map(NotificationCenter.default.removeObserver)
                closeObserver = nil
            }
        }
        window = created
        NSApp.activate()
        created.makeKeyAndOrderFront(nil)
    }
}
