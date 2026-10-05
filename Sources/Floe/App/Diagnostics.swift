//
//  Diagnostics.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import Foundation

/// The loggers, one per area. They write to the system log, and to a file while detailed logging is on.
/// What the user typed or asked is never logged, only its length.
enum Log {
    static let app = DiagLog(category: "App")
    static let catalog = DiagLog(category: "Catalog")
    static let search = DiagLog(category: "Search")
    static let extensions = DiagLog(category: "Extensions")
    static let ai = DiagLog(category: "AI")

    /// A search slower than this is worth a line: it is about three dropped frames.
    static let slowSearch: TimeInterval = 0.05

    /// Opens and closes the log file as the setting changes, starting with its stored value.
    static func follow(_ settings: AppSettings) -> AnyCancellable {
        settings.$diagnosticLogging.removeDuplicates().sink { DiagnosticLogger.shared.isEnabled = $0 }
    }

    static func milliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

extension AIAnswer.Choice {
    /// The source's name in a log line. An API is named by its host alone, never its key.
    var logName: String {
        switch self {
        case .tools: "The command line tool"
        case .appleIntelligence: "Apple Intelligence"
        case let .api(endpoint): "The API at \(endpoint?.chatURL.host ?? "an address not set")"
        }
    }
}
