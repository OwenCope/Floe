//
//  AcknowledgementsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3. The three pages and their layout are Thaw's; what they say is
//  Floe's and comes from Credits, which scripts/generate-credits.py writes, so the page and
//  CREDITS.md stay the same. Floe is not translated, so there is no translators link. The
//  window is opened by ReadingWindow, since Floe has no window scenes.

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
            case .credits: ReadingPathItem(id: rawValue, label: String(localized: "Credits"))
            case .origins: ReadingPathItem(id: rawValue, label: String(localized: "Origins"))
            case .licenses: ReadingPathItem(id: rawValue, label: String(localized: "Licenses"))
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
        }
    }

    private var title: Text {
        switch page {
        case .credits: Text("Credits")
        case .origins: Text("Origins")
        case .licenses: Text("Licenses")
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 22) {
            ReadingParagraph("Thank you to everyone who contributes code and documentation to \(AppInfo.displayName).")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Credits.contributors) { contributor in
                    if let url = contributor.profile {
                        Link(destination: url) {
                            Text(verbatim: contributor.label).underline()
                        }
                    } else {
                        Text(verbatim: contributor.label)
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
            ReadingParagraph("\(AppInfo.displayName) is a sibling of Thaw, built by the same people in the same organization. It shares Thaw’s design system and much of its design.")

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

extension Contributor {
    /// The name with the GitHub account after it.
    var label: String {
        "\(name) (@\(handle))"
    }
}
