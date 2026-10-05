//
//  ErrorView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

/// Shows the command's view, or the error screen once it has failed.
struct SessionContainer: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var session: ExtensionSession

    var body: some View {
        if let failure = session.failure {
            ErrorView(model: model, session: session, failure: failure).modifier(PanelOnePiece())
        } else {
            ExtensionView(model: model, session: session)
        }
    }
}

struct ErrorView: View {
    @ObservedObject var model: LauncherModel
    let session: ExtensionSession
    let failure: SessionFailure

    private var title: String {
        switch failure.kind {
        case .error: "\(session.command.title) ran into an error"
        case .crashed: "\(session.command.title) stopped"
        case .unresponsive: "\(session.command.title) isn't responding"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: session.command.extensionTitle, icon: session.command.icon, assetsPath: session.command.assetsPath)
            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                    Label {
                        Text(title).font(ThawType.heading)
                    } icon: {
                        Image(systemName: failure.kind == .unresponsive ? "hourglass" : "exclamationmark.triangle.fill")
                            .foregroundStyle(failure.kind == .unresponsive ? Color.orange : Color.red)
                    }
                    Text(failure.message).textSelection(.enabled)
                    if !failure.details.isEmpty {
                        Text(failure.details.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(ThawSpacing.row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: ThawRadius.control))
                    }
                    HStack(spacing: ThawSpacing.base) {
                        Button("Copy Details") { model.copyFailure() }
                        Button("Show Extension in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([session.command.extensionDir])
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Footer(primary: failure.kind == .unresponsive ? "Restart" : "Try Again") {
                Text("⌘⇧C copies details · Esc goes back").foregroundStyle(.secondary)
            }
        }
    }
}
