//
//  PrivacySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3's Privacy pane: the notice, the permissions and the network list.
//  The network rows are Floe's own, since what it contacts is not what Thaw does, and Thaw's
//  capture inspector and connection status sections have nothing to describe here.
//  The search sources' switches and the switch that keeps AI on this Mac are Floe's too.

import SwiftUI
import ThawUI

/// What the app may see and where anything goes: the permissions it holds and the network calls it makes.
struct PrivacySettingsPane: View {
    @ObservedObject var settings: AppSettings
    var permissions: AppPermissions = .shared

    var body: some View {
        Form {
            // Footer-only section: the one placement where a pill renders without the form's card around it.
            ThawSection {
                EmptyView()
            } footer: {
                SettingsWarningPill(
                    title: "No analytics",
                    message: "Floe collects no analytics or usage data. What you open, and how often, stays in a file on this Mac. The network calls it makes are listed below.",
                    systemImage: "hand.raised.fill",
                    tint: .green
                )
            }
            ThawSection("Permissions") {
                ForEach(permissions.allPermissions) { permission in
                    LabeledContent {
                        PermissionStatusControl(permission: permission)
                    } label: {
                        PermissionLabel(permission: permission)
                        Text(verbatim: permission.details.joined(separator: " "))
                    }
                }
            }
            ThawSection("Search Sources") {
                ForEach(SearchSourceInfo.switches) { source in
                    Toggle(isOn: isOn(source)) {
                        Text(source.title)
                        Text(source.detail)
                    }
                }
                row("SSH Hosts", "Floe reads the host names in your SSH configuration to find them in the search, and connects by handing the name to your terminal.")
            }
            ThawSection("Network Access") {
                if let host = PrivacyNetwork.updateHost {
                    AutomaticUpdateCheckToggle()
                    row("Updates", "Checking asks \(host) whether a newer version exists. Floe asked before it started doing this.")
                }
                row("Extension Store", "Opening the Extension Store lists extensions from GitHub. Installing or updating one downloads it from GitHub and its packages from the npm registry.")
                row("AI", PrivacyNetwork.aiLine(source: settings.aiSource, baseURL: settings.aiBaseURL, tool: AskAI.configuredTool(settings), onThisMacOnly: settings.aiOnThisMacOnly))
                Toggle(isOn: $settings.aiOnThisMacOnly) {
                    Text("Only use AI that runs on this Mac")
                    Text("A source that sends questions elsewhere is refused, for Ask AI and for extensions. Nothing else is asked in its place.")
                }
                row("Release notes", "Opening What’s New from About reads Floe’s changelog from GitHub and keeps the last copy.")
                row("Extensions", "Each extension makes its own requests, and the images it shows are loaded from wherever it points.")
            }
        }
        .formStyle(.grouped)
        // The grant happens in System Settings; look again whenever this page comes back.
        .onAppear { permissions.refreshPermissionsState() }
    }

    /// A source's switch: on while its id is among the settings' search sources.
    private func isOn(_ source: SearchSourceInfo) -> Binding<Bool> {
        Binding {
            settings.searchSources.contains(source.id)
        } set: { isOn in
            if isOn {
                settings.searchSources.insert(source.id)
            } else {
                settings.searchSources.remove(source.id)
            }
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.callout).foregroundStyle(ThawInk.supporting)
        }
    }
}

/// What the Privacy pane says about the network, kept out of the view so it can be checked.
enum PrivacyNetwork {
    /// Where update checks go; nil in a build that has no updates, which then says nothing about them.
    static var updateHost: String? {
        let configuration = UpdateConfiguration(info: Bundle.main.infoDictionary)
        guard configuration.hasUsableFeed else { return nil }
        return URL(string: configuration.feedURL)?.host
    }

    /// Where a question goes, for the source chosen in General; `tool` is the command line tool that would answer, if any.
    /// With `onThisMacOnly`, a source that is not on this Mac is said to be refused.
    static func aiLine(source: AISource, baseURL: String, tool: String? = nil, onThisMacOnly: Bool = false) -> String {
        let refused = "While the switch below is on, Floe refuses to ask it, so no question is sent."
        switch source {
        case .tools where onThisMacOnly:
            let chosen = tool.map { "The \($0) tool" } ?? "A command line tool"
            return "\(chosen) is chosen, which sends questions to the service it is signed in to. \(refused)"
        case .tools:
            guard let tool else { return "The command line tool set in General is not installed, so no question is sent." }
            return "Questions go to the \(tool) tool, which sends them to the service it is signed in to, on your account there."
        case .appleIntelligence:
            return "Questions are answered by Apple Intelligence on this Mac. Nothing is sent anywhere."
        case .api:
            let url = AIEndpoint.chatURL(baseURL: baseURL)
            guard let host = url?.host else { return "Questions go to the address set in General, once it is filled in." }
            let isOnThisMac = AIEndpoint.isOnThisMac(url)
            if onThisMacOnly, !isOnThisMac {
                return "\(host) is chosen, which is not on this Mac. \(refused)"
            }
            return isOnThisMac
                ? "Questions go to the server on this Mac at \(host). Nothing leaves the machine."
                : "Questions go to \(host), with your key, and nowhere else."
        }
    }
}
