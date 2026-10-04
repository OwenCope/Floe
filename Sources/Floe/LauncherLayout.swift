//
//  LauncherLayout.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// How much of the launcher shows before anything is typed.
enum LauncherLayout: String, Codable, CaseIterable, Identifiable {
    /// The panel is always full size, with the list under the search bar.
    case extended
    /// The root search is only its search bar until there is a query.
    case compact

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .extended: "Extended"
        case .compact: "Compact"
        }
    }
}

/// What the panel is showing, reduced to the facts its size depends on.
struct LauncherPanelState: Equatable {
    var menuBarSearch = false
    /// The plain root search: no setup, command, menu bar search, clipboard history or file search on screen.
    var isRootSearch = true
    var queryIsEmpty = true

    static let fullSize = NSSize(width: 750, height: 474)
    /// Thaw's inspector panel is 600 × 400; the launcher needs room for extension detail panes.
    static let menuBarSearchSize = NSSize(width: 600, height: 400)
    /// The search bar is 65 tall with less space under it than above; 2 more evens them out.
    static let collapsedHeight: CGFloat = 67

    /// Collapsed, the panel is the search bar alone.
    func isCollapsed(in layout: LauncherLayout) -> Bool {
        layout == .compact && isRootSearch && !menuBarSearch && queryIsEmpty
    }

    /// The one place the panel's size is decided.
    func contentSize(in layout: LauncherLayout) -> NSSize {
        if menuBarSearch {
            return Self.menuBarSearchSize
        }
        return isCollapsed(in: layout) ? NSSize(width: Self.fullSize.width, height: Self.collapsedHeight) : Self.fullSize
    }

    /// The window is the content plus `LauncherView.margin` on every side.
    func windowSize(in layout: LauncherLayout) -> NSSize {
        let size = contentSize(in: layout)
        return NSSize(width: size.width + LauncherView.margin * 2, height: size.height + LauncherView.margin * 2)
    }

    /// Where a panel goes when it is shown. It is placed as if it were at its full height,
    /// so the search bar is at the same spot on screen whether or not the panel is collapsed.
    func origin(in visibleFrame: NSRect, panelSize: NSSize) -> NSPoint {
        let top = visibleFrame.minY + visibleFrame.height * 0.62 + windowSize(in: .extended).height / 2
        return NSPoint(x: visibleFrame.midX - panelSize.width / 2, y: top - panelSize.height)
    }

    /// Return, the arrows and their kin, Command-K and Command-Shift-F all act on the selected row.
    static func isRowKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 36: true
        case 3, 40: flags.contains(.command)
        default: Shortcuts.navigationDelta(keyCode) != nil
        }
    }
}

extension LauncherModel {
    var panelState: LauncherPanelState {
        LauncherPanelState(
            showingSetup: setup != nil,
            showingCommand: session?.command.mode == "view",
            menuBarSearch: isSearchingMenuBar,
            clipboardHistory: isShowingClipboardHistory,
            fileSearch: isSearchingFiles,
            queryIsEmpty: query.isEmpty
        )
    }

    /// The panel's window size, sent again whenever the view on screen, the query or the layout changes it.
    func panelWindowSizes(settings: AppSettings) -> AnyPublisher<NSSize, Never> {
        // Published values arrive before they are stored, so the state is built from what is sent.
        let views = $setup.map { $0 != nil }
            .combineLatest($session.map { $0?.command.mode == "view" }, $isSearchingMenuBar, $isShowingClipboardHistory)
        return views.combineLatest($isSearchingFiles, $query.map(\.isEmpty), settings.$launcherLayout)
            .map { views, fileSearch, queryIsEmpty, layout in
                LauncherPanelState(
                    showingSetup: views.0,
                    showingCommand: views.1,
                    menuBarSearch: views.2,
                    clipboardHistory: views.3,
                    fileSearch: fileSearch,
                    queryIsEmpty: queryIsEmpty
                )
                .windowSize(in: layout)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Collapsed, there are no rows on screen, so the keys that act on the selected row do nothing.
    func handlePanelKey(_ event: NSEvent, layout: LauncherLayout) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if panelState.isCollapsed(in: layout), LauncherPanelState.isRowKey(event.keyCode, flags: flags) {
            return true
        }
        return handleKey(event)
    }
}

extension LauncherPanelState {
    /// Mirrors the order `LauncherView` picks its view in: anything but the last branch is not the root search.
    init(showingSetup: Bool, showingCommand: Bool, menuBarSearch: Bool, clipboardHistory: Bool, fileSearch: Bool, queryIsEmpty: Bool) {
        self.init(
            menuBarSearch: menuBarSearch,
            isRootSearch: !(showingSetup || showingCommand || menuBarSearch || clipboardHistory || fileSearch),
            queryIsEmpty: queryIsEmpty
        )
    }
}

extension NSWindow {
    /// Keeps the top edge and horizontal center where they are, so the search bar does not move.
    func resizeKeepingTop(to size: NSSize) {
        guard frame.size != size else { return }
        setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }
}
