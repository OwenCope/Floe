//
//  ReadingWindow.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// A window one of the reading pages opens in. It is built when asked for and let go when closed.
@MainActor
final class ReadingWindow {
    static let releaseNotes = ReadingWindow(title: "What’s New") { AnyView(WhatsNewView()) }
    static let acknowledgements = ReadingWindow(title: "Acknowledgements") { AnyView(AcknowledgementsView()) }

    /// Called after one of them has closed. The settings process sets it: it stays alive while one is open.
    static var onClose: (() -> Void)?

    static var isAnyOpen: Bool {
        releaseNotes.isOpen || acknowledgements.isOpen
    }

    private let title: String
    private let content: () -> AnyView
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init(title: String, content: @escaping () -> AnyView) {
        self.title = title
        self.content = content
    }

    var isOpen: Bool {
        window != nil
    }

    func show() {
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
        created.title = title
        created.contentView = NSHostingView(rootView: content())
        created.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: created, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closed()
            }
        }
        window = created
        NSApp.activate()
        created.makeKeyAndOrderFront(nil)
    }

    private func closed() {
        window = nil
        closeObserver.map(NotificationCenter.default.removeObserver)
        closeObserver = nil
        Self.onClose?()
    }
}
