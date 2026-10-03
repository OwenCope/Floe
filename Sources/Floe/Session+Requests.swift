//
//  Session+Requests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The half of a session that answers what the extension asks the app for, and what its host starts with.
extension ExtensionSession {
    /// Takes `request` and `cancelRequest`; false for any other message.
    func handleRequest(_ fields: [String: Any]) -> Bool {
        switch fields["type"] as? String {
        case "request":
            answerRequest(fields)
        case "cancelRequest":
            if let id = fields["id"] as? Int {
                pendingRequests.removeValue(forKey: id)?.cancel()
            }
        default:
            return false
        }
        return true
    }

    /// Starts answering one request and replies when the answer is there, after any `replyChunk`s. A request the host
    /// cancelled, or one cut off because the session stopped, gets no reply: nobody is waiting.
    private func answerRequest(_ fields: [String: Any]) {
        guard let id = fields["id"] as? Int else { return }
        let method = fields["method"] as? String ?? ""
        guard let request = HostRequest(method: method, params: fields["params"] as? [String: Any] ?? [:]) else {
            send(["type": "reply", "id": id, "error": "Floe can't answer \"\(method)\" yet, or the request is missing something it needs."])
            return
        }
        let answer = answer
        pendingRequests[id] = Task { @MainActor [weak self] in
            var reply: [String: Any] = ["type": "reply", "id": id]
            do {
                // Text that arrives early is sent on in order, while the request is still wanted.
                reply["result"] = try await answer(request) { [weak self] text in
                    await MainActor.run { [weak self] in
                        guard let self, pendingRequests[id] != nil else { return }
                        send(["type": "replyChunk", "id": id, "chunk": text])
                    }
                }
            } catch {
                reply["error"] = error.localizedDescription
            }
            guard let self, pendingRequests.removeValue(forKey: id) != nil else { return }
            send(reply)
        }
    }

    /// Stops answering, when the host is going away.
    func cancelRequests() {
        for task in pendingRequests.values {
            task.cancel()
        }
        pendingRequests = [:]
    }

    /// What the host starts with: the login shell's environment, the command's preferences, and
    /// whether `AI.ask` has a tool to run on.
    static func hostVariables(_ base: [String: String], preferences: Data?, hasAI: Bool) -> [String: String] {
        var variables = base
        // Preferences go through the environment so the host has them before the command's first line runs.
        if let preferences {
            variables["FLOE_PREFERENCES"] = String(bytes: preferences, encoding: .utf8)
        }
        variables["FLOE_AI"] = hasAI ? "1" : nil
        return variables
    }
}
