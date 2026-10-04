//
//  AskAIView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The answer to one question: the question on top, the answer under it as it arrives, and a line
/// that says who answered and where. Return copies, Escape goes back to the search.
struct AskAIView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var asking: AskAIModel
    @State private var position = ScrollPosition(edge: .top)
    @State private var offset: CGFloat = 0

    /// One arrow press moves the answer by about three lines.
    private static let scrollStep: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        // Something else took the panel: the request stops with the view.
        .onDisappear { model.leaveAskAI(asking) }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: ThawSpacing.row) {
                Image(systemName: AskAI.symbol).font(.system(size: 17)).foregroundStyle(.secondary)
                Text(asking.question).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            ZStack {
                Divider()
                if asking.isWorking {
                    ProgressView().progressViewStyle(.linear).frame(height: 2)
                }
            }
            .frame(height: 2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if asking.answer.isEmpty {
            switch asking.state {
            case let .failed(message):
                ThawEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "No answer",
                    caption: "\(message)",
                    actionTitle: "Ask Again"
                ) { asking.ask() }
            default:
                ThawEmptyState(
                    systemImage: AskAI.symbol,
                    title: "Waiting for the answer…",
                    caption: asking.source.map { "\($0.line)" },
                    isLoading: true
                )
            }
        } else {
            answer
        }
    }

    private var answer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Thaw's reading size and line spacing, for text that is read rather than scanned.
                MarkdownView(text: asking.answer, font: ThawType.body, lineSpacing: 6)
                if case let .failed(message) = asking.state {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
                if let source = asking.source {
                    Label(source.line, systemImage: source.isOnThisMac ? "desktopcomputer" : "network")
                        .font(ThawType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, new in offset = new }
        .onChange(of: asking.scroll) { _, scroll in
            // Home and End ask for more lines than there are; the scroll view stops at its ends.
            let step = CGFloat(max(-10000, min(scroll.lines, 10000))) * Self.scrollStep
            withAnimation(.easeOut(duration: 0.12)) { position.scrollTo(y: max(0, offset + step)) }
        }
    }

    private var bottomBar: some View {
        PanelBottomBar {
            ShortcutHintButton(title: "Back") { model.closeAskAI() } hint: {
                KeyCapView(text: "esc")
            }
            Spacer(minLength: 0)
            ShortcutHintButton(title: "Ask Again") { asking.ask() } hint: {
                KeyCapView(text: "⌘")
                KeyCapView(text: "R")
            }
            ActionsButton(model: model) { $0.askAIActions() }
            if !asking.answer.isEmpty {
                ShortcutHintButton(title: "Paste Answer") { model.pasteAskAIAnswer() } hint: {
                    KeyCapView(text: "⌘")
                    KeyCapView(systemImage: "return")
                }
                if !asking.isWorking, !isFailed {
                    ShortcutHintButton(title: "Copy Answer") { model.copyAskAIAnswer() } hint: {
                        KeyCapView(systemImage: "return")
                    }
                }
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = asking.state {
            return true
        }
        return false
    }
}
