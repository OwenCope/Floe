//
//  WebAddress.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A web address typed into the search in full, and the URL it opens.
nonisolated struct WebAddress: Equatable, Sendable {
    /// What was typed, trimmed. The row reads Open and this.
    let text: String
    let url: URL

    /// The endings a bare host may have besides a two-letter country code. Endings that are
    /// also common file types (zip, mov, pro, inc) are left out on purpose.
    static let commonDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz", "name", "mobi", "app", "dev", "page", "xyz",
        "online", "site", "website", "tech", "store", "shop", "blog", "cloud", "wiki", "news", "design", "studio",
        "tools", "software", "systems", "network", "digital", "media", "live", "world", "today", "space", "email",
        "link", "club", "art", "codes", "academy", "agency", "company", "solutions", "services", "social", "team",
        "work", "works", "zone", "run", "build", "community", "foundation", "global", "group", "guide", "health",
        "help", "host", "land", "life", "one", "plus", "press", "rocks", "science", "support", "top", "video", "fun",
        "games", "chat", "earth", "travel", "museum", "aero", "coop", "jobs", "asia", "africa", "london", "berlin",
        "paris", "nyc", "tokyo", "swiss",
    ]

    /// Two-letter file types: `main.rs` and `README.md` are files until a port or a path follows.
    static let twoLetterFileTypes: Set<String> = [
        "md", "py", "rs", "sh", "pl", "cc", "js", "ts", "go", "rb", "cs", "kt", "hs", "ml", "mm", "mk", "ps", "pm",
        "tf", "db", "gz", "xz",
    ]

    /// Nil unless the whole text is an address: a miss costs an arrow key, a false hit takes Return from a search.
    init?(typed input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 2048, !text.contains(where: \.isWhitespace) else { return nil }
        let lowered = text.lowercased()
        let hasScheme = lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        guard let url = hasScheme ? Self.url(withScheme: text) : Self.url(bare: text) else { return nil }
        self.text = text
        self.url = url
    }

    /// `https://host/…` as typed. Credentials in an address are refused: they hide where it leads.
    private static func url(withScheme text: String) -> URL? {
        guard var components = URLComponents(string: text), let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, isPort(components.port)
        else { return nil }
        components.scheme = components.scheme?.lowercased()
        return components.url
    }

    /// `host`, `host:port` and whatever follows the first `/`, `?` or `#`.
    private static func url(bare text: String) -> URL? {
        let end = text.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? text.endIndex
        let authority = text[..<end].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let host = authority[0].lowercased()
        var port: Int?
        if authority.count == 2 {
            guard isNumber(authority[1]), let typed = Int(authority[1]), isPort(typed) else { return nil }
            port = typed
        }
        let isAlone = port == nil && end == text.endIndex
        // The rest is parsed as a relative reference; `//x` would name a second host, so it is refused.
        guard let scheme = scheme(forHost: host, isAlone: isAlone),
              var components = URLComponents(string: String(text[end...])), components.host == nil
        else { return nil }
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }

    /// The scheme a bare host opens with, or nil when it is not a host: `http` for this Mac and
    /// for IPv4 addresses, which seldom have a certificate, and `https` for a domain.
    private static func scheme(forHost host: String, isAlone: Bool) -> String? {
        if host == "localhost" {
            return "http"
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isLabel), let ending = labels.last.map(String.init) else { return nil }
        if labels.allSatisfy(isNumber) {
            // Four numbers are an address; three are a version and two a decimal.
            return labels.count == 4 && labels.allSatisfy { Int($0).map { $0 <= 255 } ?? false } ? "http" : nil
        }
        guard ending.count >= 2, ending.allSatisfy({ ("a" ... "z").contains($0) }) else { return nil }
        if ending.count == 2 {
            // `main.rs` is a file and `10.cm` a length, until a port or a path says otherwise.
            let isDoubtful = twoLetterFileTypes.contains(ending) || labels.dropLast().allSatisfy(isNumber)
            return isAlone && isDoubtful && labels.first != "www" ? nil : "https"
        }
        return commonDomains.contains(ending) ? "https" : nil
    }

    /// Letters, digits and hyphens, with no hyphen at either end.
    private static func isLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty, label.count <= 63, label.first != "-", label.last != "-" else { return false }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static func isNumber(_ label: Substring) -> Bool {
        label.allSatisfy { ("0" ... "9").contains($0) }
    }

    private static func isPort(_ port: Int?) -> Bool {
        port.map { (1 ... 65535).contains($0) } ?? true
    }
}
