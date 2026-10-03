//
//  MarkdownParser.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    case code(String)
    case image(URL)
    case rule
}

/// Block-level Markdown for detail views: headings, bullets, fenced code, rules, images and paragraphs.
/// Inline styling is left to AttributedString when a block is drawn.
enum MarkdownParser {
    static func blocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                flush()
            } else if let match = trimmed.wholeMatch(of: #/(\#{1,6})\s+(.*)/#) {
                flush()
                blocks.append(.heading(match.1.count, String(match.2)))
            } else if let match = trimmed.wholeMatch(of: #/(?:[-*+]|\d+\.)\s+(.*)/#) {
                flush()
                blocks.append(.bullet(String(match.1)))
            } else if trimmed.wholeMatch(of: #/(-{3,}|\*{3,}|_{3,})/#) != nil {
                flush()
                blocks.append(.rule)
            } else if let match = trimmed.wholeMatch(of: #/!\[[^\]]*\]\(([^)\s]+)[^)]*\)/#), let url = URL(string: String(match.1)) {
                flush()
                blocks.append(.image(url))
            } else {
                paragraph.append(trimmed)
            }
        }
        // An unclosed fence still shows what was written.
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
