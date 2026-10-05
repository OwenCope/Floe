//
//  SSHHostsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

/// Counts the files read, from any thread.
private final nonisolated class ReadCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

struct SSHHostsTests {
    private static let home = "/home/tester"
    private static let config = home + "/.ssh/config"

    /// A home folder that holds exactly these files, by path. No test reads a real one.
    private func files(_ contents: [String: String], reads: ReadCount = ReadCount()) -> SSHConfigFiles {
        SSHConfigFiles(
            home: Self.home,
            read: { path in
                reads.increment()
                return contents[path]
            },
            list: { folder in
                let names = contents.keys.compactMap { path -> String? in
                    guard path.hasPrefix(folder + "/") else { return nil }
                    return path.dropFirst(folder.count + 1).split(separator: "/").first.map(String.init)
                }
                return Array(Set(names))
            }
        )
    }

    private func hosts(_ config: String, _ others: [String: String] = [:]) -> [SSHHost] {
        SSHConfig.hosts(files: files(others.merging([Self.config: config]) { _, new in new }))
    }

    // MARK: Names

    @Test func everyPlainNameOnAHostLineIsAHostOfItsOwn() {
        let found = hosts("""
        Host web db cache
            HostName 10.0.0.5
            User deploy
        """)
        #expect(found.map(\.alias) == ["web", "db", "cache"])
        #expect(found.allSatisfy { $0.hostName == "10.0.0.5" && $0.user == "deploy" }, "what follows the line is for each name on it")
    }

    @Test func wildcardsNegationsAndTheCatchAllNameNoHost() {
        let found = hosts("""
        Host *.example.com !bastion staging-? web
        Host *
            User everyone
        Host !other
        """)
        #expect(found.map(\.alias) == ["web"])
    }

    @Test func aMatchBlockNamesNoHostAndSetsNothing() {
        let found = hosts("""
        Host web
        Match host web user root
            HostName wrong.example.com
            User wrong
        Host db
            User dba
        """)
        #expect(found == [SSHHost(alias: "web"), SSHHost(alias: "db", user: "dba")])
    }

    @Test func aNameListedTwiceIsOneHost() {
        #expect(hosts("Host web\nHost db web\n").map(\.alias) == ["web", "db"])
    }

    // MARK: Lines

    @Test func commentsAndEmptyLinesAreSkipped() {
        let found = hosts("""
        # Host hidden

        Host web   # the front door
            # User nobody
            User deploy
        """)
        #expect(found == [SSHHost(alias: "web", user: "deploy")])
    }

    @Test func keywordsAreReadInAnyCaseWithAnEqualsSignOrQuotes() {
        let found = hosts("""
        HOST=edge
            hostname = "edge.example.com"
            UsEr="ops"
        host "quoted"
        \tHostName\tquoted.example.com
        """)
        #expect(found == [
            SSHHost(alias: "edge", hostName: "edge.example.com", user: "ops"),
            SSHHost(alias: "quoted", hostName: "quoted.example.com"),
        ])
    }

    @Test func aLineIsItsKeywordInLowerCaseAndItsValues() {
        #expect(SSHConfig.directive("  Host  a   \"b c\"  d ")?.values == ["a", "b c", "d"])
        #expect(SSHConfig.directive("IdentityFile=~/.ssh/id")?.keyword == "identityfile")
        #expect(SSHConfig.directive("Compression")?.keyword == "compression")
        #expect(SSHConfig.directive("Compression")?.values == [])
        #expect(SSHConfig.directive("   ") == nil)
        #expect(SSHConfig.directive("# Host a") == nil)
        #expect(SSHConfig.values(in: "a#b # rest") == ["a#b"], "a number sign inside a value is part of it")
    }

    // MARK: What a host is given

    @Test func theFirstValueWinsAsItDoesInSSH() {
        let found = hosts("""
        User early
        Host box
            HostName first.example.com
            HostName second.example.com
            User later
        Host box
            HostName third.example.com
        """)
        #expect(found == [SSHHost(alias: "box", hostName: "first.example.com", user: "early")])
    }

    @Test func aWildcardBlockGivesItsValuesToTheHostsItCovers() {
        let found = hosts("""
        Host api.corp
            HostName 10.1.1.1
        Host *.corp !db.corp
            User staff
        Host db.corp
        Host *
            User everyone
        """)
        #expect(found == [
            SSHHost(alias: "api.corp", hostName: "10.1.1.1", user: "staff"),
            SSHHost(alias: "db.corp", user: "everyone"),
        ])
    }

    @Test func aPatternMatchesWithStarsAndQuestionMarks() {
        #expect(SSHConfig.matches("*", "anything"))
        #expect(SSHConfig.matches("web-?", "web-1"))
        #expect(!SSHConfig.matches("web-?", "web-10"))
        #expect(SSHConfig.matches("*.example.*", "a.b.example.com"))
        #expect(SSHConfig.matches("*a", "*ba"))
        #expect(!SSHConfig.matches("web", "webs"))
        #expect(!SSHConfig.matches("web*x", "website"))
    }

    @Test func theHostNameMayBeBuiltFromTheAlias() {
        #expect(hosts("Host node1 node2\n HostName %h.cluster.local\n").map(\.hostName) == ["node1.cluster.local", "node2.cluster.local"])
    }

    @Test func nothingButTheNameTheAddressAndTheUserIsKept() {
        let found = hosts("""
        Host web
            IdentityFile ~/.ssh/secret_key
            Port 2222
            ProxyJump bastion
            HostName web.example.com
        """)
        #expect(found == [SSHHost(alias: "web", hostName: "web.example.com")])
    }

    // MARK: Include

    @Test func aRelativeIncludeIsReadFromTheSSHFolderInPlace() {
        let found = hosts("Include work\nHost last\n", [
            Self.home + "/.ssh/work": "Host first\n    User me\n",
        ])
        #expect(found == [SSHHost(alias: "first", user: "me"), SSHHost(alias: "last")])
    }

    @Test func aConfigurationThatOnlyIncludesStillHasItsHosts() {
        let found = hosts("Include hosts.d/*\n", [
            Self.home + "/.ssh/hosts.d/one": "Host one\n",
            Self.home + "/.ssh/hosts.d/two": "Host two\n",
        ])
        #expect(found.map(\.alias) == ["one", "two"])
    }

    @Test func aWildcardIncludesEveryFileThatMatchesInOrderButNoHiddenOne() {
        let found = hosts("Include conf.d/*.conf\n", [
            Self.home + "/.ssh/conf.d/b.conf": "Host b\n",
            Self.home + "/.ssh/conf.d/a.conf": "Host a\n",
            Self.home + "/.ssh/conf.d/.hidden.conf": "Host hidden\n",
            Self.home + "/.ssh/conf.d/notes.txt": "Host notes\n",
        ])
        #expect(found.map(\.alias) == ["a", "b"])
    }

    @Test func anIncludeMayNameTheHomeFolderAnAbsolutePathAndSeveralFiles() {
        let found = hosts("Include ~/elsewhere/hosts \"/etc/ssh extra/hosts\"\n", [
            Self.home + "/elsewhere/hosts": "Host from-home\n",
            "/etc/ssh extra/hosts": "Host from-etc\n",
        ])
        #expect(found.map(\.alias) == ["from-home", "from-etc"])
    }

    @Test func anIncludedFileThatIsMissingIsSkipped() {
        #expect(hosts("Include nowhere gone.d/*\nHost web\n").map(\.alias) == ["web"])
    }

    @Test func whatAnIncludedFileSetsFirstBelongsToTheBlockThatIncludedIt() {
        let found = hosts("Host web\n    Include shared\nHost db\n", [
            Self.home + "/.ssh/shared": "User shared\n",
        ])
        #expect(found == [SSHHost(alias: "web", user: "shared"), SSHHost(alias: "db")])
    }

    @Test func aFileThatIncludesItselfIsReadOnce() {
        let reads = ReadCount()
        let contents = [
            Self.config: "Include config loop\nHost top\n",
            Self.home + "/.ssh/loop": "Include ../.ssh/config loop ./loop\nHost inner\n",
        ]
        let found = SSHConfig.hosts(files: files(contents, reads: reads))
        #expect(found.map(\.alias) == ["inner", "top"])
        #expect(reads.value == 2, "a file already being read is not opened again")
    }

    @Test func includesStopNestingAtTheDepthSSHAllows() {
        var contents = [Self.config: "Include chain1\nHost host0\n"]
        for index in 1 ... 30 {
            contents[Self.home + "/.ssh/chain\(index)"] = "Include chain\(index + 1)\nHost host\(index)\n"
        }
        #expect(SSHConfig.hosts(files: files(contents)).count == SSHConfig.maxDepth)
    }

    // MARK: Nothing to read

    @Test func withoutAConfigurationThereAreNoHosts() {
        let reads = ReadCount()
        #expect(SSHConfig.hosts(files: files([:], reads: reads)).isEmpty)
        #expect(reads.value == 1, "one look for the file, and nothing after it")
        #expect(hosts("").isEmpty)
        #expect(hosts("Host *\n    User me\n").isEmpty, "a configuration without a name has no host")
    }

    // MARK: A host

    @Test func theSubtitleIsTheUserAndTheAddressOrThePartThereIs() {
        #expect(SSHHost(alias: "web", hostName: "10.0.0.5", user: "deploy").subtitle == "deploy@10.0.0.5")
        #expect(SSHHost(alias: "web", hostName: "10.0.0.5").subtitle == "10.0.0.5")
        #expect(SSHHost(alias: "web", user: "deploy").subtitle == "deploy")
        #expect(SSHHost(alias: "web").subtitle == nil)
    }

    @Test func theIdentifierComesFromTheAliasAlone() {
        let before = SSHHost(alias: "web", hostName: "10.0.0.5", user: "deploy")
        let after = SSHHost(alias: "web", hostName: "web.example.com")
        #expect(before.id == after.id)
        #expect(before.id == "ssh-host:web")
        #expect(SSHHost(alias: "Web").id != before.id, "ssh tells the two apart, so Floe does")
    }

    @Test func theNameToCopyIsTheAddressWhenThereIsOne() {
        #expect(SSHHost(alias: "web", hostName: "10.0.0.5").copyableName == "10.0.0.5")
        #expect(SSHHost(alias: "web", user: "deploy").copyableName == "web")
    }
}
