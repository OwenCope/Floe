//
//  LoginEnvironmentTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct LoginEnvironmentTests {
    private let marker = "__FLOE_ENVIRONMENT__"

    @Test func readsTheVariablesBetweenTheMarkers() {
        let output = "motd from .zshrc\n\(marker)PATH=/opt/homebrew/bin:/usr/bin\0EDITOR=nvim\0\(marker)trailing"
        #expect(LoginEnvironment.variables(in: output) == ["PATH": "/opt/homebrew/bin:/usr/bin", "EDITOR": "nvim"])
    }

    @Test func keepsEqualsSignsAndNewlinesInsideAValue() {
        let output = "\(marker)FLAGS=a=b=c\0MULTILINE=one\ntwo\0\(marker)"
        #expect(LoginEnvironment.variables(in: output) == ["FLAGS": "a=b=c", "MULTILINE": "one\ntwo"])
    }

    @Test func leavesOutWhatDescribesTheShellsOwnSession() {
        let output = "\(marker)SHLVL=2\0TERM=xterm\0CLAUDECODE=1\0PWD=/tmp\0HOME=/Users/ada\0=nameless\0noequals\0\(marker)"
        #expect(LoginEnvironment.variables(in: output) == ["HOME": "/Users/ada"])
    }

    @Test(arguments: ["", "command not found", "__FLOE_ENVIRONMENT__PATH=/bin"])
    func aShellThatDidNotAnswerGivesNothing(output: String) {
        #expect(LoginEnvironment.variables(in: output).isEmpty)
    }

    @Test func thePathGainsTheCommonFoldersAfterItsOwn() {
        let path = LoginEnvironment.augmentedPath("/custom/bin:/usr/bin", home: "/Users/ada")
        let entries = path.split(separator: ":").map(String.init)
        #expect(Array(entries.prefix(2)) == ["/custom/bin", "/usr/bin"])
        #expect(entries.contains("/opt/homebrew/bin"))
        #expect(entries.contains("/Users/ada/.local/bin"))
        #expect(entries.count(where: { $0 == "/usr/bin" }) == 1)
    }

    @Test func aMissingPathStillFindsTheSystemTools() {
        let entries = LoginEnvironment.augmentedPath(nil, home: "/Users/ada").split(separator: ":").map(String.init)
        #expect(entries.first == "/opt/homebrew/bin")
        #expect(entries.contains("/bin"))
    }

    @Test func theFallbackDropsSessionKeysAndSetsALanguage() {
        let fallback = LoginEnvironment.fallback(["TERM": "xterm", "CLAUDECODE": "1", "PATH": "/custom/bin", "EDITOR": "nvim"])
        #expect(fallback["TERM"] == nil)
        #expect(fallback["CLAUDECODE"] == nil)
        #expect(fallback["EDITOR"] == "nvim")
        #expect(fallback["LANG"] == "en_US.UTF-8")
        #expect(fallback["PATH"]?.hasPrefix("/custom/bin:") == true)
        #expect(LoginEnvironment.fallback(["LANG": "es_MX.UTF-8"])["LANG"] == "es_MX.UTF-8")
    }

    @Test func findsAToolOnThePathItIsGiven() {
        #expect(LoginEnvironment.which("sh", in: ["PATH": "/nonexistent:/bin"])?.path == "/bin/sh")
        #expect(LoginEnvironment.which("sh", in: ["PATH": "/nonexistent"]) == nil)
        #expect(LoginEnvironment.which("floe-no-such-tool", in: ["PATH": "/bin:/usr/bin"]) == nil)
    }

    @Test func aNameWithASlashIsAPathAndNotLookedUp() {
        #expect(LoginEnvironment.which("/bin/sh", in: ["PATH": ""])?.path == "/bin/sh")
        #expect(LoginEnvironment.which("/bin/floe-no-such-tool", in: ["PATH": "/bin"]) == nil)
    }

    @Test func theUsersShellIsAnExecutable() {
        #expect(FileManager.default.isExecutableFile(atPath: LoginEnvironment.userShell()))
    }

    @Test func loadingReadsTheLoginShellOnce() async {
        await LoginEnvironment.load()
        await LoginEnvironment.load()
        #expect(LoginEnvironment.isLoaded)
        #expect(LoginEnvironment.current["PATH"]?.contains("/usr/bin") == true)
        #expect(LoginEnvironment.current["SHLVL"] == nil)
    }
}
