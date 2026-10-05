//
//  AcknowledgementsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3. The three pages and their layout are Thaw's. Credits links to the
//  repository's contributors and to the translators in CREDITS.md, naming nobody in the app, as
//  Thaw's does. Origins and Licenses come from Credits, which scripts/generate-credits.py writes.
//  The window is opened by ReadingWindow, since Floe has no window scenes.

import SwiftUI
import ThawUI

// MARK: - AcknowledgementsView

/// Credits and origins, followed by the libraries Floe is built from.
struct AcknowledgementsView: View {
    @Environment(\.openURL) private var openURL

    /// Looks up a web link by its FloeLinks name; a snapshot or a test passes its own.
    var link: (String) -> URL? = AppInfo.link

    private enum Page: String, CaseIterable {
        case credits
        case origins
        case licenses

        var item: ReadingPathItem {
            switch self {
            case .credits: ReadingPathItem(id: rawValue, label: String(localized: "Credits", bundle: .floe))
            case .origins: ReadingPathItem(id: rawValue, label: String(localized: "Origins", bundle: .floe, comment: "The heading over the projects this app grew out of."))
            case .licenses: ReadingPathItem(id: rawValue, label: String(localized: "Licenses", bundle: .floe))
            }
        }
    }

    @State private var selection: String? = Page.credits.rawValue

    private var page: Page {
        Page(rawValue: selection ?? "") ?? .credits
    }

    var body: some View {
        ReadingPage(
            path: Page.allCases.map(\.item),
            selection: $selection,
            title: title
        ) {
            switch page {
            case .credits:
                credits
            case .origins:
                origins
            case .licenses:
                licenses
            }
        } links: {
            if let url = link("repository") {
                Button("Contribute") {
                    openURL(url)
                }
                .buttonStyle(.settingsGlass)
            }
            if let url = link("translate") {
                if link("repository") != nil {
                    Text(verbatim: "/")
                        .foregroundStyle(ThawInk.supporting)
                }
                Button("Help translate") {
                    openURL(url)
                }
                .buttonStyle(.settingsGlass)
            }
        }
    }

    private var title: Text {
        switch page {
        case .credits: Text("Credits")
        case .origins: Text("Origins")
        case .licenses: Text("Licenses")
        }
    }

    /// Thaw's page: a thank-you and two links, with no names in the app. The lists live on GitHub.
    private var credits: some View {
        VStack(alignment: .leading, spacing: 22) {
            ReadingParagraph(String(
                localized: "Thank you to everyone who contributes code, documentation, and translations to \(AppInfo.displayName).",
                bundle: .floe,
                comment: "The placeholder is the name of this app."
            ))

            VStack(alignment: .leading, spacing: 12) {
                if let url = AcknowledgementLinks.contributors(repository: link("repository")) {
                    Link(destination: url) {
                        Text("Contributors").underline()
                    }
                }
                if let url = AcknowledgementLinks.translators(repository: link("repository")) {
                    Link(destination: url) {
                        Text("Translators").underline()
                    }
                }
            }
            .font(ReadingPageType.body)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .id(Page.credits)
        .transition(.opacity)
    }

    private var origins: some View {
        VStack(alignment: .leading, spacing: 22) {
            ReadingParagraph(String(
                localized: "\(AppInfo.displayName) is a sibling of Thaw, built by the same people in the same organization. It shares Thaw’s design system and much of its design.",
                bundle: .floe,
                comment: "The placeholder is the name of this app."
            ))

            ForEach(Credits.origins) { credit in
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: credit.name)
                        .font(ReadingPageType.heading)
                        .accessibilityAddTraits(.isHeader)
                    ReadingParagraph(credit.detail)
                    if let url = link(credit.link) {
                        Button {
                            openURL(url)
                        } label: {
                            Text(verbatim: Self.displayText(for: url))
                                .font(ReadingPageType.body)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .id(Page.origins)
        .transition(.opacity)
    }

    private var licenses: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Credits.libraries) { credit in
                VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                    if let url = link(credit.link) {
                        Link(destination: url) {
                            Text(verbatim: credit.name).underline()
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(verbatim: credit.name)
                    }
                    Text(verbatim: credit.detail)
                        .foregroundStyle(.secondary)
                }
                .font(ReadingPageType.body)
            }

            Text(verbatim: Credits.trademark)
                .font(ReadingPageType.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(Page.licenses)
        .transition(.opacity)
    }

    /// A link as the page prints it: the host and path, without the scheme.
    static func displayText(for url: URL) -> String {
        (url.host() ?? "") + url.path()
    }
}

/// Where the credits page's two links go, as Thaw's do: the repository's contributors, and the translators in CREDITS.md.
nonisolated enum AcknowledgementLinks {
    static func contributors(repository: URL?) -> URL? {
        repository?.appending(path: "graphs/contributors")
    }

    static func translators(repository: URL?) -> URL? {
        repository?.appending(path: "blob/main/CREDITS.md")
    }
}
