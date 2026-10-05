//
//  OAuthBrokerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

/// A sign-in waiting on the shared broker, registered without opening the browser.
private final nonisolated class Waiter: Sendable {
    private let answers = Mutex<[Result<String, any Error>]>([])

    init(_ extensionName: String, state: String) {
        OAuthBroker.shared.register(extensionName: extensionName, state: state) { [self] answer in
            answers.withLock { $0.append(answer) }
        }
    }

    /// Every answer so far: the callback address, or the name of the `OAuthError` case.
    var outcomes: [String] {
        answers.withLock { answers in
            answers.map { answer in
                switch answer {
                case let .success(callback): callback
                case let .failure(error): (error as? OAuthError).map { String(describing: $0) } ?? "\(error)"
                }
            }
        }
    }
}

/// The broker is shared, so every test signs in as an extension of its own and leaves nothing waiting.
nonisolated struct OAuthBrokerTests {
    private let broker = OAuthBroker.shared
    private let name = "floe-oauth-tests-\(UUID().uuidString)"

    private func redirect(_ query: String, to address: String = "floe://oauth") throws -> URL {
        try #require(URL(string: "\(address)?\(query)"))
    }

    private func failure(of request: HostRequest) async -> String? {
        do {
            _ = try await broker.perform(request, extensionName: name)
            return nil
        } catch {
            return (error as? OAuthError).map { String(describing: $0) }
        }
    }

    @Test func aRedirectWithTheMatchingStateAnswersTheSignInWithTheWholeAddress() throws {
        let waiter = Waiter(name, state: "s1")
        let callback = try redirect("code=abc&state=s1&package_name=\(name)")
        broker.complete(url: callback)
        #expect(waiter.outcomes == [callback.absoluteString])

        broker.complete(url: callback)
        #expect(waiter.outcomes.count == 1, "a sign-in is answered once")
    }

    @Test func aRedirectCarryingAnErrorIsHandedOnForTheHostToRead() throws {
        let waiter = Waiter(name, state: "s1")
        let callback = try redirect("error=access_denied&state=s1&package_name=\(name)")
        broker.complete(url: callback)
        #expect(waiter.outcomes == [callback.absoluteString])
    }

    @Test(arguments: [
        ("https://oauth", "code=abc&state=s1&package_name=NAME"),
        ("floe://open", "code=abc&state=s1&package_name=NAME"),
        ("floe://oauth", "code=abc&package_name=NAME"),
        ("floe://oauth", "code=abc&state=s1"),
        ("floe://oauth", "code=abc&state=other&package_name=NAME"),
        ("floe://oauth", "code=abc&state=s1&package_name=someone-else"),
    ])
    func aRedirectThatIsNotThisSignInsLeavesItWaiting(address: String, query: String) throws {
        let waiter = Waiter(name, state: "s1")
        try broker.complete(url: redirect(query.replacingOccurrences(of: "NAME", with: name), to: address))
        #expect(waiter.outcomes.isEmpty)

        broker.cancel(extensionName: name, state: "s1")
        #expect(waiter.outcomes == ["cancelled"], "it was still waiting")
    }

    @Test func aRedirectWithNoQueryLeavesTheSignInWaiting() throws {
        let waiter = Waiter(name, state: "s1")
        try broker.complete(url: #require(URL(string: "floe://oauth")))
        #expect(waiter.outcomes.isEmpty)
        broker.cancelAll(for: name)
    }

    @Test(arguments: ["s1", "s2"])
    func aNewerSignInFromTheSameExtensionReplacesTheOneWaiting(newerState: String) throws {
        let older = Waiter(name, state: "s1")
        let newer = Waiter(name, state: newerState)
        #expect(older.outcomes == ["replaced"])
        #expect(newer.outcomes.isEmpty)

        let callback = try redirect("code=abc&state=\(newerState)&package_name=\(name)")
        broker.complete(url: callback)
        #expect(older.outcomes == ["replaced"])
        #expect(newer.outcomes == [callback.absoluteString])
    }

    @Test func cancellingASignInFailsThatOneOnly() {
        let waiter = Waiter(name, state: "s1")
        broker.cancel(extensionName: name, state: "unknown")
        #expect(waiter.outcomes.isEmpty)

        broker.cancel(extensionName: name, state: "s1")
        broker.cancel(extensionName: name, state: "s1")
        #expect(waiter.outcomes == ["cancelled"])
    }

    @Test func aStoppingSessionFailsItsOwnSignInsAndNoOneElses() throws {
        let other = name + "-other"
        let mine = Waiter(name, state: "s1")
        let theirs = Waiter(other, state: "s1")
        broker.cancelAll(for: name)
        #expect(mine.outcomes == ["cancelled"])
        #expect(theirs.outcomes.isEmpty)

        let callback = try redirect("code=abc&state=s1&package_name=\(other)")
        broker.complete(url: callback)
        #expect(theirs.outcomes == [callback.absoluteString])
        #expect(mine.outcomes == ["cancelled"])
    }

    @Test(arguments: zip(
        [OAuthError.timedOut, .cancelled, .replaced, .unknownRequest, .invalidRedirect("The provider said no.")],
        [
            "Sign-in timed out.", "Sign-in was cancelled.", "Sign-in was replaced by a newer request.",
            "Floe can't answer that request.", "The provider said no.",
        ]
    ))
    func everySignInFailureSaysWhatHappened(error: OAuthError, message: String) {
        #expect(error.errorDescription == message)
        #expect(error.localizedDescription == message)
    }

    @Test(arguments: [HostRequest.askAI(prompt: "hello", model: nil), .selectedText, .selectedFinderItems, .clipboardRead])
    func aRequestThatIsNotASignInIsRefused(request: HostRequest) async {
        #expect(await failure(of: request) == "unknownRequest")
    }

    @Test func aSignInWithNoUsableAddressFailsBeforeTheBrowserOpens() async {
        let request = HostRequest.oauthAuthorize(url: "", state: "s1", providerName: "Provider")
        #expect(await failure(of: request) == #"invalidRedirect("Missing or invalid param: url")"#)
    }

    @Test func anExtensionThatNeverSignedInHasNoTokens() async throws {
        let answer = try await broker.perform(.oauthGetTokens(providerId: "none"), extensionName: name)
        #expect(answer is NSNull)
        #expect(broker.tokens(extensionName: name, providerId: "none") == nil)
    }
}
