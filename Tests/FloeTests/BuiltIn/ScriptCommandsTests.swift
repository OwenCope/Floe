//
//  ScriptCommandsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct ScriptCommandsTests {
    private static let required = "# @raycast.schemaVersion 1\n# @raycast.title Say Hello\n"

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Parses a file holding this text. The folder is gone by the time this returns.
    private func parse(_ text: String, name: String = "script.sh") throws -> Result<ScriptCommand, ScriptParseError> {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return ScriptCommand.parse(file: file)
    }

    @Test func everyFieldOfAHeaderIsRead() throws {
        let command = try parse("""
        #!/bin/bash

        # @raycast.schemaVersion 1
        # @raycast.title Say Hello
        # @raycast.mode compact
        # @raycast.packageName Greetings
        # @raycast.icon 👋
        # @raycast.needsConfirmation true
        # @raycast.argument1 {"type": "text", "placeholder": "Name"}
        # @raycast.argument2 {"type": "text", "placeholder": "Greeting", "optional": true}

        echo "Hello $1"
        """, name: "hello.sh").get()
        #expect(command.title == "Say Hello")
        #expect(command.mode == .compact)
        #expect(command.packageName == "Greetings")
        #expect(command.displayPackage == "Greetings")
        #expect(command.icon == "👋")
        #expect(command.needsConfirmation)
        #expect(command.arguments == [
            ScriptArgument(placeholder: "Name", optional: false),
            ScriptArgument(placeholder: "Greeting", optional: true),
        ])
        #expect(command.file.lastPathComponent == "hello.sh")
        #expect(command.id == "script/hello.sh")
    }

    @Test func aHeaderWithOnlyAVersionAndATitleTakesTheDefaults() throws {
        let command = try parse(Self.required).get()
        #expect(command.title == "Say Hello")
        #expect(command.mode == .fullOutput)
        #expect(command.packageName == nil)
        #expect(command.displayPackage == "Script Command")
        #expect(command.icon == nil)
        #expect(!command.needsConfirmation)
        #expect(command.arguments.isEmpty)
    }

    @Test func aFieldNamedWithNoValueIsAsIfItWereNotThere() throws {
        let command = try parse(Self.required + "# @raycast.mode\n# @raycast.packageName\n# @raycast.icon   \n# @raycast.argument1\n").get()
        #expect(command.mode == .fullOutput)
        #expect(command.packageName == nil)
        #expect(command.icon == nil)
        #expect(command.arguments.isEmpty)
    }

    @Test(arguments: [
        ("fullOutput", ScriptMode.fullOutput),
        ("compact", .compact),
        ("silent", .silent),
        ("inline", .inline),
    ])
    func everyModeIsReadByItsName(name: String, mode: ScriptMode) throws {
        #expect(try parse(Self.required + "# @raycast.mode \(name)\n").get().mode == mode)
    }

    @Test(arguments: ["loud", "fulloutput", "Compact", "silent mode"])
    func aModeThatIsNotOneOfTheFourSpelledExactlyFailsWithItsName(name: String) throws {
        #expect(try parse(Self.required + "# @raycast.mode \(name)\n") == .failure(.unsupportedMode(name)))
    }

    @Test(arguments: [
        ("true", true), ("TRUE", true), ("1", true), ("yes", true), ("Yes", true),
        ("false", false), ("0", false), ("no", false), ("on", false), ("", false),
    ])
    func confirmationIsAskedForOnlyByTrueOneOrYes(value: String, expected: Bool) throws {
        #expect(try parse(Self.required + "# @raycast.needsConfirmation \(value)\n").get().needsConfirmation == expected)
    }

    @Test func fieldNamesAreReadInAnyCaseBehindAnyCommentMarkerAndTheFirstOneWins() throws {
        let command = try parse("""
        // @raycast.SCHEMAVersion    1
        -- @raycast.TITLE   First Title  \u{20}
        # @raycast.title Second Title
        #@raycast.packagename Tools
        """).get()
        #expect(command.title == "First Title")
        #expect(command.packageName == "Tools")
    }

    @Test func aHeaderWithWindowsLineEndingsIsRead() throws {
        let command = try parse("#!/bin/sh\r\n# @raycast.schemaVersion 1\r\n# @raycast.title Say Hello\r\n# @raycast.mode silent\r\n").get()
        #expect(command.title == "Say Hello")
        #expect(command.mode == .silent)
    }

    @Test func upToThreeArgumentsAreKeptInOrderOfTheirNumbers() throws {
        let command = try parse(Self.required + """
        # @raycast.argument4 {"placeholder": "Fourth"}
        # @raycast.argument3{"placeholder": "Third", "optional": true}
        # @raycast.argument1 {"placeholder": "First", "optional": false}
        # @raycast.argument2 {"placeholder": "Second", "optional": "yes"}
        """).get()
        #expect(command.arguments == [
            ScriptArgument(placeholder: "First", optional: false),
            ScriptArgument(placeholder: "Second", optional: false),
            ScriptArgument(placeholder: "Third", optional: true),
        ])
    }

    @Test func anArgumentNumberThatIsSkippedLeavesNoGap() throws {
        let command = try parse(Self.required + "# @raycast.argument3 {\"placeholder\": \"Only\"}\n").get()
        #expect(command.arguments == [ScriptArgument(placeholder: "Only", optional: false)])
    }

    @Test(arguments: [
        (1, "Name"),
        (2, #"{"type": "text"}"#),
        (3, #"{"placeholder": ""}"#),
        (1, #"{"placeholder": 5}"#),
        (2, #"["Name"]"#),
        (3, #"{"placeholder": "Name""#),
    ])
    func anArgumentThatIsNotJSONWithAPlaceholderFailsWithItsNumber(index: Int, value: String) throws {
        #expect(try parse(Self.required + "# @raycast.argument\(index) \(value)\n") == .failure(.invalidArgument(index)))
    }

    @Test(arguments: [
        ("#!/bin/sh\necho hello\n", ScriptParseError.missingSchemaVersion),
        ("Shopping list: milk, eggs.\n", .missingSchemaVersion),
        ("", .missingSchemaVersion),
        ("# @raycast.title Say Hello\n", .missingSchemaVersion),
        ("# @raycast.schemaVersion\n# @raycast.title Say Hello\n", .missingSchemaVersion),
        ("# @raycast.schemaVersion 2\n# @raycast.title Say Hello\n", .unsupportedSchemaVersion("2")),
        ("# @raycast.schemaVersion 1.0\n# @raycast.title Say Hello\n", .unsupportedSchemaVersion("1.0")),
        ("# @raycast.schemaVersion 1\n", .missingTitle),
        ("# @raycast.schemaVersion 1\n# @raycast.title   \n", .missingTitle),
    ])
    func aFileWithoutAUsableVersionAndTitleIsNotACommand(text: String, error: ScriptParseError) throws {
        #expect(try parse(text) == .failure(error))
    }

    @Test func theVersionIsCheckedBeforeTheTitleAndTheTitleBeforeTheRest() throws {
        #expect(try parse("# @raycast.schemaVersion 3\n# @raycast.mode loud\n") == .failure(.unsupportedSchemaVersion("3")))
        #expect(try parse("# @raycast.schemaVersion 1\n# @raycast.mode loud\n# @raycast.argument1 x\n") == .failure(.missingTitle))
        #expect(try parse(Self.required + "# @raycast.mode loud\n# @raycast.argument1 x\n") == .failure(.unsupportedMode("loud")))
    }

    @Test func aFileThatIsMissingOrNotTextIsUnreadable() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(ScriptCommand.parse(file: folder.appendingPathComponent("absent.sh")) == .failure(.unreadable))

        let binary = folder.appendingPathComponent("binary")
        try Data([0xFF, 0xFE, 0x00, 0xC3]).write(to: binary)
        #expect(ScriptCommand.parse(file: binary) == .failure(.unreadable))
    }

    @Test func theFailuresTheOtherSuiteLeavesOutSayWhatToDo() {
        #expect(ScriptParseError.unreadable.errorDescription == "The file couldn't be read as text.")
        #expect(ScriptParseError.missingTitle.errorDescription == "Missing @raycast.title. Add `# @raycast.title My Script`.")
    }

    @Test func aScanSortsCommandsByTitleAndFailuresByFileAndSkipsHiddenFilesAndFolders() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ name: String, _ text: String) throws {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func header(_ title: String) -> String {
            "# @raycast.schemaVersion 1\n# @raycast.title \(title)\n"
        }
        try write("1.sh", header("charlie"))
        try write("2.sh", header("Alpha"))
        try write("3.py", header("beta"))
        try write("untitled.sh", "# @raycast.schemaVersion 1\n")
        try write("notes.txt", "Shopping list: milk, eggs.\n")
        try write(".hidden.sh", header("Hidden"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try write("nested/inner.sh", header("Inner"))

        let scan = ScriptCommand.scan(in: folder)
        #expect(scan.commands.map(\.title) == ["Alpha", "beta", "charlie"])
        #expect(scan.commands.map(\.id) == ["script/2.sh", "script/3.py", "script/1.sh"])
        #expect(scan.failures.map(\.file) == ["notes.txt", "untitled.sh"])
        #expect(scan.failures.map(\.error) == [.missingSchemaVersion, .missingTitle])
        #expect(scan.failures.map(\.id) == ["notes.txt", "untitled.sh"])
    }

    @Test func aScanOfAFolderThatIsEmptyOrMissingFindsNothing() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for target in [folder, folder.appendingPathComponent("absent")] {
            let scan = ScriptCommand.scan(in: target)
            #expect(scan.commands.isEmpty)
            #expect(scan.failures.isEmpty)
        }
    }

    @Test(arguments: [
        ("Say Hello world", "world"),
        ("say hello  two words  ", "two words"),
        ("  SAY HELLO\t\"a b\" c\n", "\"a b\" c"),
        ("Say Hello", nil),
        ("Say Hello   ", nil),
        ("Say HelloWorld", nil),
        ("Say Hell", nil),
        ("Wave Hello world", nil),
        ("", nil),
    ] as [(String, String?)])
    func theArgumentsAreWhatIsTypedAfterTheTitleAndASpace(query: String, expected: String?) {
        let command = ScriptCommand(
            file: URL(fileURLWithPath: "/scripts/hello.sh"),
            title: "Say Hello",
            packageName: nil,
            mode: .fullOutput,
            needsConfirmation: false,
            icon: nil,
            arguments: []
        )
        #expect(command.argumentsText(in: query) == expected)
    }
}
