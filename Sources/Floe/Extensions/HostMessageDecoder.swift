//
//  HostMessageDecoder.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One host message with its decoding work already done: a render whose tree is built, or any other
/// message with its fields as the host sent them.
///
/// The unchecked Sendable is sound because `decode` is the only way to make one: it derives every
/// stored value from bytes run through `JSONSerialization` with the default options, so they are
/// fresh, immutable, JSON-only objects owned solely by this value and never mutated afterwards.
/// It must never be extended to carry caller-supplied objects.
nonisolated enum DecodedHostMessage: @unchecked Sendable {
    case render(tree: Node?)
    case fields([String: Any])

    /// Decodes one complete NDJSON line. Nil for anything JSON cannot read into an object, which the
    /// host's output has always skipped.
    static func decode(_ line: Data) -> DecodedHostMessage? {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        if message["type"] as? String == "render" {
            return .render(tree: Node(json: message["tree"]))
        }
        return .fields(message)
    }
}

/// Frames the host's NDJSON stdout and decodes each complete line, away from the main actor.
/// One decoder per running host: it owns the partial bytes between chunks.
actor HostMessageDecoder {
    private var buffer = Data()
    /// Bytes already searched for a newline, counted from buffer.startIndex, so an incomplete long
    /// line is not rescanned on every chunk.
    private var scanned = 0

    /// Hands back the messages this chunk completed, in arrival order.
    func append(_ data: Data) -> [DecodedHostMessage] {
        buffer.append(data)
        var messages: [DecodedHostMessage] = []
        var search = buffer.index(buffer.startIndex, offsetBy: scanned)
        // range(of:in:) reports positions in the buffer's own index space, which a sliced subscript
        // would not: Data slices restart their indices at zero.
        var lineStart = buffer.startIndex
        while let newline = buffer.range(of: Data([0x0A]), in: search ..< buffer.endIndex)?.lowerBound {
            if let message = DecodedHostMessage.decode(buffer.subdata(in: lineStart ..< newline)) {
                messages.append(message)
            }
            search = buffer.index(after: newline)
            lineStart = search
        }
        // [start, lineStart) holds finished lines, [lineStart, end) a partial line that has been
        // searched already. Compaction may only drop the finished part — dropping searched bytes of
        // the partial line would lose them — and scanned is counted from lineStart after that.
        scanned = buffer.distance(from: lineStart, to: buffer.endIndex)
        if lineStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex ..< lineStart)
        }
        return messages
    }
}

extension HostMessageDecoder {
    /// Feeds one stdout chunk and applies whatever it completes, in order, before returning. Awaiting
    /// each application keeps the next chunk from overtaking the one being applied.
    func deliver(_ data: Data, applying: @Sendable (DecodedHostMessage) async -> Void) async {
        for message in append(data) {
            await applying(message)
        }
    }
}
