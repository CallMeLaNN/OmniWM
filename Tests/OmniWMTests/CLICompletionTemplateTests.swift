// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWMCtl
import XCTest

final class CLICompletionTemplateTests: XCTestCase {
    func testZshTemplateAndRenderedScriptHaveValidNativeSyntax() throws {
        try assertValidTemplate(PackageResources.completion_zsh, shell: .zsh, executable: "/bin/zsh")
    }

    func testZshMarkCompletionSuggestsActionsAndListFlags() throws {
        let script = CLICompletionGenerator.script(for: .zsh)
        for (words, position, expected) in [
            ("omniwmctl window mark ''", 4, "set"),
            ("omniwmctl window mark list ''", 5, "--json")
        ] {
            let setup = "words=(\(words)); CURRENT=\(position); compadd() { print -r -- \"$@\" }; compdef() { :; }; "
            let input = setup + script + "\n_omniwmctl; :"
            XCTAssertTrue(try suggestions(from: "/bin/zsh", ["-fc", input]).contains(expected), words)
        }
    }

    func testZshAndBashGatherCompletionSuggestTheReachFlagAndItsValues() throws {
        let zsh = CLICompletionGenerator.script(for: .zsh)
        let bash = CLICompletionGenerator.script(for: .bash)
        for (words, expected) in [
            ("omniwmctl window ''", CLICompletionCatalog.windowActionNames),
            ("omniwmctl window gather ''", ["--from"]),
            ("omniwmctl window gather ow_a ''", ["--from"]),
            ("omniwmctl window gather --from ''", ["all", "monitor", "workspace"]),
            ("omniwmctl window gather --from all ow_a ''", [])
        ] {
            let count = words.split(separator: " ").count
            let zshInput = "words=(\(words)); CURRENT=\(count); compadd() { shift; print -r -- \"$@\" }; "
                + "compdef() { :; }; \(zsh)\n_omniwmctl; :"
            let bashInput = "\(bash)\nCOMP_WORDS=(\(words)); COMP_CWORD=\(count - 1); _omniwmctl\n"
                + #"printf '%s\n' "${COMPREPLY[@]}""#
            XCTAssertEqual(Set(try suggestions(from: "/bin/zsh", ["-fc", zshInput])), Set(expected), words)
            XCTAssertEqual(Set(try suggestions(from: "/bin/bash", ["-c", bashInput])), Set(expected), words)
        }
    }

    func testZshScriptRegistersWhenEvaluatedAndCompletesWhenAutoloaded() throws {
        let script = CLICompletionGenerator.script(for: .zsh)
        let stubs = "compadd() { shift; print -r -- \"$@\" }; compdef() { print -r -- \"compdef $*\" }; "

        let evaluated = try suggestions(from: "/bin/zsh", ["-fc", stubs + script])
        XCTAssertEqual(evaluated, ["compdef", "_omniwmctl", "omniwmctl"])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try script.write(to: directory.appendingPathComponent("_omniwmctl"), atomically: true, encoding: .utf8)
        let autoload = stubs + "fpath=(\(directory.path) $fpath); autoload -Uz _omniwmctl; "
            + "words=(omniwmctl window gather ''); CURRENT=4; _omniwmctl; :"
        XCTAssertEqual(try suggestions(from: "/bin/zsh", ["-fc", autoload]), ["--from"])
    }

    func testFishGatherCompletionsOfferTheReachFlagOnceAndItsValuesAfterIt() {
        let script = CLICompletionGenerator.script(for: .fish)
        let gather = "__fish_seen_subcommand_from window; and __fish_seen_subcommand_from gather"
        for reach in CLICompletionCatalog.windowGatherReaches {
            XCTAssertTrue(script.contains("-n '\(gather); and __omniwmctl_prev_arg_is --from' -a '\(reach)'"), reach)
        }
        XCTAssertTrue(script.contains(
            "-n '\(gather); and not __omniwmctl_prev_arg_is --from; and not __omniwmctl_has_arg --from' -a '--from'"
        ))
    }

    private func suggestions(from executable: String, _ arguments: [String]) throws -> [String] {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, errorText)
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    func testBashTemplateAndRenderedScriptHaveValidNativeSyntax() throws {
        try assertValidTemplate(PackageResources.completion_bash, shell: .bash, executable: "/bin/bash")
    }

    func testFishTemplateVariablesAreAllRendered() {
        let template = String(decoding: PackageResources.completion_fish, as: UTF8.self)
        XCTAssertTrue(template.contains("#{{"))
        XCTAssertFalse(CLICompletionGenerator.script(for: .fish).contains("#{{"))
    }

    private func assertValidTemplate(_ bytes: [UInt8], shell: CLIShell, executable: String) throws {
        let template = String(decoding: bytes, as: UTF8.self)
        let script = CLICompletionGenerator.script(for: shell)
        XCTAssertTrue(template.contains("#{{"))
        XCTAssertFalse(script.contains("#{{"))
        try assertValidSyntax(template, executable: executable)
        try assertValidSyntax(script, executable: executable)
    }

    private func assertValidSyntax(_ script: String, executable: String) throws {
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-n", scriptURL.path]
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
