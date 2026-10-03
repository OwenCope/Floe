//
//  AboutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: Floe has no updater or changelog yet, so the updates card and
//  What's New are left out, and the "more" menu keeps the destinations Floe has. Credits open
//  Floe's own acknowledgements.

import AppKit
import SwiftUI
import ThawUI

/// What the About page shows, read from the bundle so a build stamps its own version and commit.
enum AppInfo {
    static let displayName = "Floe"
    static let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    static let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    static let commitString = Bundle.main.object(forInfoDictionaryKey: "GitCommitSHA") as? String ?? "unknown"
    static let copyrightString = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    private static let links = Bundle.main.object(forInfoDictionaryKey: "FloeLinks") as? [String: String] ?? [:]

    /// A web link from Info.plist's FloeLinks; nil when run outside the app bundle (`swift run`).
    static func link(_ name: String) -> URL? {
        links[name].flatMap(URL.init(string:))
    }

    static var repositoryURL: URL? { link("repository") }
    static var issuesURL: URL? { repositoryURL?.appendingPathComponent("issues") }

    static var buildDescription: String {
        """
        \(displayName) \(versionString) (\(buildString))
        Commit: \(commitString)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }
}

/// The About page: who Floe is and which build this is, then help actions.
/// Project links and copyright form a quiet footer.
struct AboutSettingsPane: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let iconSize: CGFloat = 96

    /// Half the icon, so the name beside it does not outweigh it.
    private static let nameSize: CGFloat = 48

    @State private var applicationIcon = AboutSettingsPane.currentApplicationIcon()
    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var menuAnchor = MoreMenuAnchor()
    @State private var isShowingCredits = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                identity
                actions
                footer
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The sidebar's behind-window material, so About reads as one surface
        // with it. Other panes keep the window background for their forms.
        .background {
            BehindWindowMaterialBackground(material: .sidebar)
                .ignoresSafeArea()
        }
        .onChange(of: colorScheme, initial: true) {
            applicationIcon = Self.currentApplicationIcon()
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
        .sheet(isPresented: $isShowingCredits) {
            CreditsView()
        }
        .navigationTitle("About")
    }

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text(verbatim: AppInfo.displayName)
                        .font(.system(size: Self.nameSize, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Image(nsImage: applicationIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                        .accessibilityHidden(true)
                }
                Text("The open source launcher for macOS")
                    .font(.callout)
                    .foregroundStyle(ThawInk.supporting)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            details
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Details

    /// Labels right-aligned against a shared edge, values in monospace so a
    /// hash and a build number line up and can be selected and pasted.
    private var details: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                detailRow("Version", value: AppInfo.versionString, isPrimary: true)
                detailRow("Build", value: AppInfo.buildString)
                detailRow("Commit", value: AppInfo.commitString)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            // Beside what it copies.
            Button {
                copyVersionInfo()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .buttonStyle(.settingsGlass)
            .controlSize(.small)
            .help(didCopy ? "Copied" : "Copy the version, build and commit for a bug report")
            .accessibilityLabel(didCopy ? "Copied" : "Copy version information")
        }
    }

    private func detailRow(_ label: LocalizedStringKey, value: String, isPrimary: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(ThawInk.supporting)
                .gridColumnAlignment(.trailing)
            Text(verbatim: value)
                .monospaced()
                .fontWeight(isPrimary ? .medium : .regular)
                .foregroundStyle(isPrimary ? Color.primary : ThawInk.supporting)
                .textSelection(.enabled)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Report a Bug") {
                if let url = AppInfo.issuesURL { openURL(url) }
            }
            Button("Extensions Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([Paths.extensions])
            }
            // A plain button that pops the menu, so it takes the same style,
            // size and corner as its neighbours; a SwiftUI Menu does not.
            Button {
                showMoreMenu()
            } label: {
                // Inside a Text the symbol takes a line of text's height, so
                // the button matches its neighbours instead of sitting short.
                Text(Image(systemName: "ellipsis"))
            }
            .help("More about \(AppInfo.displayName)")
            .accessibilityLabel("More about \(AppInfo.displayName)")
            .background { MoreMenuAnchorView(anchor: menuAnchor) }
        }
        .buttonStyle(.settingsGlass)
        .controlSize(.regular)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let url = AppInfo.repositoryURL {
                    Link(destination: url) {
                        Text("Source Code").underline()
                    }
                    footerSeparator
                }
                Button {
                    isShowingCredits = true
                } label: {
                    Text("Credits").underline()
                }
                if let url = AppInfo.link("thaw") {
                    footerSeparator
                    Link(destination: url) {
                        Text("Thaw").underline()
                    }
                }
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)

            Text(AppInfo.copyrightString)
        }
        .font(.footnote)
        .foregroundStyle(ThawInk.supporting)
        .multilineTextAlignment(.center)
    }

    private var footerSeparator: some View {
        Text(verbatim: "·")
            .accessibilityHidden(true)
    }

    /// Pops the secondary destinations under the actions button, for both
    /// clicks and keyboard activation.
    private func showMoreMenu() {
        let menu = NSMenu()
        func item(_ title: String, _ symbol: String, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
            let entry = ClosureMenuItem(title: title, handler: handler)
            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return entry
        }
        let openURL = openURL
        menu.addItem(item(String(localized: "Data Folder"), "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([Paths.data])
        })
        menu.addItem(item(String(localized: "Raycast Extensions Folder"), "folder.badge.gearshape") {
            NSWorkspace.shared.activateFileViewerSelecting([Paths.raycastExtensions])
        })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Raycast Extension Store"), "storefront") {
            if let url = AppInfo.link("raycastExtensions") { openURL(url) }
        })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Acknowledgements"), "text.book.closed") { isShowingCredits = true })
        guard let anchor = menuAnchor.view else { return }
        // The anchor's own coordinate system is not flipped, so minY is its
        // bottom edge and the menu opens just below the button.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY), in: anchor)
    }

    // MARK: Helpers

    private static func currentApplicationIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        return (icon.copy() as? NSImage) ?? icon
    }

    private func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppInfo.buildDescription, forType: .string)

        copyFeedbackTask?.cancel()
        didCopy = true
        copyFeedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            didCopy = false
            copyFeedbackTask = nil
        }
    }
}

/// What Floe is built from.
private struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    /// `link` names an entry in Info.plist's FloeLinks.
    private let credits: [(name: String, detail: String, link: String)] = [
        ("Thaw", "ThawUI, the hotkey code and the search panel design. GPL-3.0.", "thaw"),
        ("CompactSlider", "Used by ThawUI. MIT.", "compactSlider"),
        ("Bun", "Runs extensions. MIT.", "bun"),
        ("React", "Extension rendering, with react-reconciler. MIT.", "react"),
        ("Raycast extensions", "The API Floe implements; each extension keeps its own license.", "raycastExtensions"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            Text("Acknowledgements").font(ThawType.heading)
            ForEach(credits, id: \.name) { credit in
                VStack(alignment: .leading, spacing: 2) {
                    if let url = AppInfo.link(credit.link) {
                        Link(credit.name, destination: url)
                    } else {
                        Text(credit.name)
                    }
                    Text(credit.detail).font(.callout).foregroundStyle(ThawInk.supporting)
                }
            }
            Text("Raycast is a trademark of Raycast Technologies Inc. Floe is not affiliated with Raycast.")
                .font(.footnote)
                .foregroundStyle(ThawInk.supporting)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

/// Holds the AppKit view behind the actions button so the menu can be
/// positioned against the button itself. A reference box keeps the
/// representable from writing SwiftUI state during a view update.
private final class MoreMenuAnchor {
    weak var view: NSView?
}

/// An empty view behind the actions button for NSMenu.popUp to position
/// against, including on keyboard activation.
private struct MoreMenuAnchorView: NSViewRepresentable {
    let anchor: MoreMenuAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        anchor.view = nsView
    }
}

// MARK: - From Thaw's SettingsView and LayoutBarItemMenu

/// Behind-window vibrancy so surfaces sample the desktop rather than the
/// system-owned NavigationSplitView backdrop beneath the SwiftUI layer.
struct BehindWindowMaterialBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}

/// The system glass button, unmodified: its own padding and shape, so a
/// Settings button looks like one in System Settings and follows macOS as the
/// style changes. Kept as a name so call sites say what they mean.
extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var settingsGlass: GlassButtonStyle {
        .glass
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}
