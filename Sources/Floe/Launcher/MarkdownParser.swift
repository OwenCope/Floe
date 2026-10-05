//
//  MarkdownParser.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Markdown

nonisolated enum MarkdownBlock: Equatable, Sendable {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    /// An item of a numbered list, with the number it is shown under.
    case numbered(Int, String)
    /// A quoted passage, with the blocks inside it.
    case quote([MarkdownBlock])
    case code(String)
    case image(URL)
    case rule
}

/// Block-level Markdown for detail views and AI answers: headings, bullets, numbered items, quotes,
/// code, rules, images and paragraphs.
/// swift-markdown finds the blocks; inline styling is left to AttributedString (see `MarkdownContent`),
/// so each block carries its inline content as Markdown source.
nonisolated enum MarkdownParser {
    static func blocks(_ text: String) -> [MarkdownBlock] {
        Document(parsing: text).children.flatMap(blocks(of:))
    }

    private static func blocks(of markup: any Markup) -> [MarkdownBlock] {
        switch markup {
        case let heading as Heading:
            return [.heading(heading.level, inline(heading))]
        case let paragraph as Paragraph:
            // An image alone in its paragraph is drawn as a block.
            if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Image, let url = image.source.flatMap(URL.init(string:)) {
                return [.image(url)]
            }
            return [.paragraph(inline(paragraph))]
        case let code as CodeBlock:
            return [.code(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)]
        case is ThematicBreak:
            return [.rule]
        case let item as ListItem:
            return blocks(of: item, number: nil)
        case let list as OrderedList:
            // A list that starts at 4 keeps counting from 4.
            return list.listItems.enumerated().flatMap { index, item in
                blocks(of: item, number: Int(list.startIndex) + index)
            }
        default:
            return otherBlocks(of: markup)
        }
    }

    private static func otherBlocks(of markup: any Markup) -> [MarkdownBlock] {
        switch markup {
        case is UnorderedList:
            return markup.children.flatMap(blocks(of:))
        case is BlockQuote:
            return [.quote(markup.children.flatMap(blocks(of:)))]
        case let table as Table:
            // Monospaced, so the columns the formatter aligned stay aligned.
            return [.code(table.format())]
        default:
            return [.paragraph(markup.format())]
        }
    }

    /// Nested lists are flattened: every item is one row, numbered when its list is.
    private static func blocks(of item: ListItem, number: Int?) -> [MarkdownBlock] {
        item.children.flatMap { child -> [MarkdownBlock] in
            guard let paragraph = child as? Paragraph else { return blocks(of: child) }
            return [number.map { .numbered($0, inline(paragraph)) } ?? .bullet(inline(paragraph))]
        }
    }

    /// A block's inline content as one line of Markdown. Each piece is detached first, or the formatter
    /// adds the indentation and quote marks of the list or quote it sits in.
    private static func inline(_ markup: any Markup) -> String {
        markup.children.map { $0 is SoftBreak || $0 is LineBreak ? " " : $0.detachedFromParent.format() }.joined()
    }
}
