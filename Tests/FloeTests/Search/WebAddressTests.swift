//
//  WebAddressTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct WebAddressTests {
    @Test(arguments: [
        // An explicit scheme and a host.
        ("https://github.com/thaw-app", "https://github.com/thaw-app"),
        ("http://example.com", "http://example.com"),
        ("HTTPS://GitHub.com/Thaw-App", "https://GitHub.com/Thaw-App"),
        ("http://intranet/wiki", "http://intranet/wiki"),
        ("https://example.com:8443/a?b=c#d", "https://example.com:8443/a?b=c#d"),
        ("http://[::1]:8080/x", "http://[::1]:8080/x"),
        ("https://münchen.de/ü", "https://xn--mnchen-3ya.de/%C3%BC"),
        ("https://example.com/a|b", "https://example.com/a%7Cb"),
        // A bare host with a known ending.
        ("github.com", "https://github.com"),
        ("github.com/thaw-app", "https://github.com/thaw-app"),
        ("GitHub.com/Thaw-App", "https://github.com/Thaw-App"),
        ("docs.swift.org/swift-book", "https://docs.swift.org/swift-book"),
        ("example.co.uk:8080/x?y=1#z", "https://example.co.uk:8080/x?y=1#z"),
        ("example.com/", "https://example.com/"),
        ("example.com?q=1", "https://example.com?q=1"),
        ("example.com#top", "https://example.com#top"),
        ("medium.com/@someone", "https://medium.com/@someone"),
        ("example.com/{query}", "https://example.com/%7Bquery%7D"),
        ("getdroppycode.app", "https://getdroppycode.app"),
        ("go.dev", "https://go.dev"),
        ("claude.ai", "https://claude.ai"),
        ("youtu.be/abc", "https://youtu.be/abc"),
        ("my-site.example.io", "https://my-site.example.io"),
        ("münchen.de", "https://xn--mnchen-3ya.de"),
        ("  github.com  ", "https://github.com"),
        // A two-letter file type is a domain once more of an address follows.
        ("docs.rs/serde", "https://docs.rs/serde"),
        ("docs.rs/", "https://docs.rs/"),
        ("www.example.md", "https://www.example.md"),
        ("example.sh:8080", "https://example.sh:8080"),
        // So is a number before a country code; before a longer ending it already is.
        ("360.cn/", "https://360.cn/"),
        ("163.com", "https://163.com"),
        ("1.1.1.1", "http://1.1.1.1"),
        // This Mac and IPv4 addresses open without TLS.
        ("localhost", "http://localhost"),
        ("localhost:3000", "http://localhost:3000"),
        ("LOCALHOST:3000/app", "http://localhost:3000/app"),
        ("127.0.0.1", "http://127.0.0.1"),
        ("127.0.0.1:8080/health", "http://127.0.0.1:8080/health"),
        ("192.168.1.1", "http://192.168.1.1"),
    ])
    func anAddressOpensAsTheURLItNames(typed: String, opens: String) {
        let address = WebAddress(typed: typed)
        #expect(address?.url.absoluteString == opens)
        #expect(address?.text == typed.trimmingCharacters(in: .whitespaces))
    }

    @Test(arguments: [
        "", "   ", "safari", "stng", "co",
        // Numbers, calculations and versions.
        "3.14", "1.5*2", "10.5 km in miles", "1.2.3", "v1.2.3", "2+2", "1.5", "10.5km", "256.1.1.1", "1.2.3.4.5",
        "5.km", "10.cm", "2.in", "1.5.kg", "360.cn",
        // File names: an ending that is no domain, or a two-letter file type with nothing after it.
        "notes.txt", "main.swift", "report.pdf", "archive.zip", "clip.mov", "data.json", "index.html", "app.pro",
        "README.md", "main.rs", "docs.rs", "script.sh", "setup.py", "node.js", "main.go", "a.b.md",
        // Email, and anything with a space.
        "a@b.com", "someone@example.com/path", "user:secret@example.com", "https://user:secret@example.com",
        "github.com thaw", "open github.com", "https://github.com/a b", "example.com/a b",
        // Other schemes are not opened.
        "mailto:a@b.com", "ssh://example.com", "file:///Applications", "ftp://example.com", "raycast://extensions",
        "x-apple.systempreferences:com.apple.Displays", "javascript:alert(1)", "tel:5551234",
        // Not hosts.
        "http://", "https:///path", "http:/example.com", "https:example.com", ".com", "example.", "example..com",
        "e.g.", "i.e", "a.m", "-a.com", "a-.com", "exa_mple.com", "example.com:", "example.com:abc", "example.com:0",
        "example.com:70000", "https://example.com:70000", "example.com//other.com", "example.c0m", "localhost.",
        "foo.localhost", "[::1]:8080", "example.notadomain", "://example.com", "*.example.com",
    ])
    func whatIsNotAnAddressIsLeftToTheSearch(typed: String) {
        #expect(WebAddress(typed: typed) == nil)
    }

    @Test func aTextTooLongToBeAnAddressIsRefused() {
        #expect(WebAddress(typed: "example.com/" + String(repeating: "a", count: 2048)) == nil)
        #expect(WebAddress(typed: "example.com/" + String(repeating: "a", count: 200)) != nil)
    }

    @Test func noFileTypeIsAlsoListedAsADomain() {
        #expect(WebAddress.commonDomains.isDisjoint(with: ["zip", "mov", "txt", "pdf", "swift", "json", "html", "pro", "inc", "md"]))
        #expect(WebAddress.commonDomains.allSatisfy { $0.count > 2 && $0 == $0.lowercased() }, "two letters are covered by the country code rule")
        #expect(WebAddress.twoLetterFileTypes.allSatisfy { $0.count == 2 })
    }
}
