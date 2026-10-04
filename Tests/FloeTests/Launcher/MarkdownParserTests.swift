//
//  MarkdownParserTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct MarkdownParserTests {
    @Test(arguments: [("# Title", 1, "Title"), ("## Sub", 2, "Sub"), ("###### Deep", 6, "Deep"), ("#   Spaced", 1, "Spaced")])
    func headings(line: String, level: Int, text: String) {
        #expect(MarkdownParser.blocks(line) == [.heading(level, text)])
    }

    @Test(arguments: ["#NoSpace", "####### Seven hashes"])
    func textThatOnlyLooksLikeAHeadingIsAParagraph(line: String) {
        #expect(MarkdownParser.blocks(line) == [.paragraph(line)])
    }

    @Test(arguments: ["- item", "* item", "+ item"])
    func bullets(line: String) {
        #expect(MarkdownParser.blocks(line) == [.bullet("item")])
    }

    @Test(arguments: [("1. item", 1), ("12. item", 12), ("3) item", 3)])
    func aNumberedItemKeepsItsNumber(line: String, number: Int) {
        #expect(MarkdownParser.blocks(line) == [.numbered(number, "item")])
    }

    @Test func aNumberedListCountsOnFromItsFirstNumber() {
        #expect(MarkdownParser.blocks("4. four\n5. five\n1. six") == [.numbered(4, "four"), .numbered(5, "five"), .numbered(6, "six")])
    }

    @Test func bulletsUnderANumberedItemStayBullets() {
        let blocks = MarkdownParser.blocks("1. first\n   - inside\n2. second")
        #expect(blocks == [.numbered(1, "first"), .bullet("inside"), .numbered(2, "second")])
    }

    @Test func aQuoteKeepsTheBlocksInsideIt() {
        let blocks = MarkdownParser.blocks("> quoted **text**\n>\n> - a point\n\nafter")
        #expect(blocks == [.quote([.paragraph("quoted **text**"), .bullet("a point")]), .paragraph("after")])
    }

    @Test(arguments: ["---", "***", "___", "-----"])
    func rules(line: String) {
        #expect(MarkdownParser.blocks(line) == [.rule])
    }

    @Test func consecutiveLinesJoinIntoOneParagraphAndBlankLinesSplitThem() {
        let blocks = MarkdownParser.blocks("First line\nsecond line\n\n  Indented third  \n")
        #expect(blocks == [.paragraph("First line second line"), .paragraph("Indented third")])
    }

    @Test func fencedCodeKeepsItsLinesAndIndentationVerbatim() {
        let blocks = MarkdownParser.blocks("Before\n```swift\nlet x = 1\n  # not a heading\n\n- not a bullet\n```\nAfter")
        #expect(blocks == [.paragraph("Before"), .code("let x = 1\n  # not a heading\n\n- not a bullet"), .paragraph("After")])
    }

    @Test func anUnclosedFenceStillShowsItsCode() {
        #expect(MarkdownParser.blocks("```\nunfinished") == [.code("unfinished")])
    }

    @Test func anImageOnItsOwnLineIsAnImageBlock() throws {
        let url = try #require(URL(string: "https://example.com/a.png"))
        #expect(MarkdownParser.blocks("![Alt text](https://example.com/a.png)") == [.image(url)])
        #expect(MarkdownParser.blocks("![](https://example.com/a.png \"Title\")") == [.image(url)])
    }

    @Test func anImageInsideASentenceStaysInTheParagraph() {
        let line = "See ![icon](https://example.com/a.png) here"
        #expect(MarkdownParser.blocks(line) == [.paragraph(line)])
    }

    @Test func aBlockEndsTheParagraphBeforeIt() {
        let blocks = MarkdownParser.blocks("Intro\n# Title\ntext\n- one\n- two\n---\nend")
        #expect(blocks == [.paragraph("Intro"), .heading(1, "Title"), .paragraph("text"), .bullet("one"), .bullet("two"), .rule, .paragraph("end")])
    }

    @Test(arguments: ["", "\n\n", "   "])
    func emptyTextHasNoBlocks(text: String) {
        #expect(MarkdownParser.blocks(text).isEmpty)
    }
}
