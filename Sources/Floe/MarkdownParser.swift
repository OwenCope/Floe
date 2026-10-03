//
//  MarkdownParser.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Markdown

enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    case code(String)
    case image(URL)
    case rule
}

/// Block-level Markdown for detail views: headings, bullets, code, rules, images and paragraphs.
/// swift-markdown finds the blocks; inline styling is left to AttributedString when a block is drawn,
/// so each block carries its inline content as Markdown source.
enum MarkdownParser {
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
            // Nested lists are flattened: every item is one bullet.
            return item.children.flatMap { child in
                (child as? Paragraph).map { [.bullet(inline($0))] } ?? blocks(of: child)
            }
        case is UnorderedList, is OrderedList, is BlockQuote:
            return markup.children.flatMap(blocks(of:))
        case let table as Table:
            // Monospaced, so the columns the formatter aligned stay aligned.
            return [.code(table.format())]
        default:
            return [.paragraph(markup.format())]
        }
    }

    /// A block's inline content as one line of Markdown. Each piece is detached first, or the formatter
    /// adds the indentation and quote marks of the list or quote it sits in.
    private static func inline(_ markup: any Markup) -> String {
        markup.children.map { $0 is SoftBreak || $0 is LineBreak ? " " : $0.detachedFromParent.format() }.joined()
    }
}
