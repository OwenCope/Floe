//
//  LoginEnvironment.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Core/Support/Shell.swift, and modified: it has a file of its
//  own, reading the shell's answer is a function a test can call, and the lookup of the developer
//  tools' git is left out, because Floe runs no git.

import Foundation
import Synchronization

/// The user's login shell environment. Apps launched from Finder inherit a minimal PATH that
/// cannot find what extensions run (brew, git, gh, node), so this is captured once at launch.
enum LoginEnvironment {
    private static let cached = Mutex<[String: String]?>(nil)
    /// The one read of the login shell. Launch starts it; anything that waits for the
    /// environment waits on the same task.
    private static let loading = Mutex<Task<Void, Never>?>(nil)

    private static let marker = "__FLOE_ENVIRONMENT__"

    static let excludedKeys: Set<String> = [
        "_", "SHLVL", "PWD", "OLDPWD", "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION",
        "TERM_SESSION_ID", "COLORTERM", "ITERM_SESSION_ID", "XPC_SERVICE_NAME",
        "__CFBundleIdentifier", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT",
    ]

    static var current: [String: String] {
        cached.withLock { $0 } ?? fallbackEnvironment
    }

    /// The process's own environment, for the moments before the login shell has answered:
    /// built once, since every reader in that window asked for a fresh copy.
    private static let fallbackEnvironment = fallback(ProcessInfo.processInfo.environment)

    static var isLoaded: Bool {
        cached.withLock { $0 != nil }
    }

    static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    static func load() async {
        let task = loading.withLock { current -> Task<Void, Never> in
            if let current {
                return current
            }
            let started = Task { await read() }
            current = started
            return started
        }
        await task.value
    }

    @concurrent
    private static func read() async {
        let script = "printf '\(marker)'; /usr/bin/env -0; printf '\(marker)'"
        var environment = fallbackEnvironment
        let shell = URL(fileURLWithPath: userShell())
        if let result = try? await Shell.run(shell, ["-l", "-i", "-c", script], environment: environment, timeout: 8) {
            environment.merge(variables(in: result.output)) { _, fromShell in fromShell }
        }
        environment["PATH"] = augmentedPath(environment["PATH"])
        let resolved = environment
        cached.withLock { $0 = resolved }
    }

    /// The variables the shell printed between the two markers, without its own session's.
    /// Empty when the markers are missing, as after a shell that failed.
    static func variables(in output: String) -> [String: String] {
        guard let start = output.range(of: marker),
              let end = output.range(of: marker, options: .backwards),
              start.upperBound < end.lowerBound
        else { return [:] }
        var variables: [String: String] = [:]
        for entry in output[start.upperBound ..< end.lowerBound].split(separator: "\0") {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equals])
            guard !key.isEmpty, !excludedKeys.contains(key) else { continue }
            variables[key] = String(entry[entry.index(after: equals)...])
        }
        return variables
    }

    static func which(_ name: String, in environment: [String: String]? = nil) -> URL? {
        let fileManager = FileManager.default
        if name.contains("/") {
            let path = (name as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let path = (environment ?? current)["PATH"] ?? augmentedPath(nil)
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func userShell() -> String {
        let fileManager = FileManager.default
        if let shell = ProcessInfo.processInfo.environment["SHELL"], fileManager.isExecutableFile(atPath: shell) {
            return shell
        }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/bin/zsh"
    }

    static func augmentedPath(_ path: String?, home: String = homeDirectory) -> String {
        var entries = (path ?? "").split(separator: ":").map(String.init)
        let common = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "\(home)/.local/bin",
            "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        for directory in common where !entries.contains(directory) {
            entries.append(directory)
        }
        return entries.joined(separator: ":")
    }

    static func fallback(_ processEnvironment: [String: String]) -> [String: String] {
        var environment = processEnvironment
        for key in excludedKeys {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = augmentedPath(environment["PATH"])
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment
    }
}
