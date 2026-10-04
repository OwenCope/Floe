//
//  MarkdownView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI

/// Draws the blocks MarkdownParser finds, with inline styling from AttributedString.
struct MarkdownView: View {
    let text: String
    /// Detail views keep the compact size; an answer that is read at length passes a larger one.
    var font = Font.system(size: 13)
    var lineSpacing: CGFloat = 0
    /// Selectable text does not draw off screen, so `--panel-snapshot` turns this off.
    static var isSelectable = true

    var body: some View {
        MarkdownBlocks(blocks: MarkdownParser.blocks(text), lineSpacing: lineSpacing)
            .font(font)
            .modifier(Selectable(isOn: Self.isSelectable))
    }
}

private struct Selectable: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

/// A run of blocks, drawn again inside a quote for the blocks it holds.
private struct MarkdownBlocks: View {
    let blocks: [MarkdownBlock]
    let lineSpacing: CGFloat

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(string)
    }

    private func paragraph(_ string: String) -> some View {
        Text(inline(string)).lineSpacing(lineSpacing).fixedSize(horizontal: false, vertical: true)
    }

    private func listRow(_ marker: String, _ string: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).foregroundStyle(.secondary).monospacedDigit()
            paragraph(string)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(inline(text)).font(.system(size: [22, 18, 15][min(level, 3) - 1], weight: .semibold))
                case let .paragraph(text):
                    paragraph(text)
                case let .bullet(text):
                    listRow("•", text)
                case let .numbered(number, text):
                    listRow("\(number).", text)
                case let .quote(quoted):
                    // Type-erased: a view cannot hold itself in its own body's type.
                    AnyView(MarkdownBlocks(blocks: quoted, lineSpacing: lineSpacing))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                        }
                case let .code(text):
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 8))
                case let .image(url):
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.primary.opacity(0.05)
                    }
                    .frame(maxHeight: 260)
                case .rule:
                    Divider()
                }
            }
        }
    }
}
