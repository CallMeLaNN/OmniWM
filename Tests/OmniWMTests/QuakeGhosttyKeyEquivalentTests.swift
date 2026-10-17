// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class QuakeGhosttyKeyEquivalentTests: XCTestCase {
    func testSpecialKeyEquivalentsPreserveRetryTimestamp() throws {
        let cases: [(
            label: String,
            characters: String,
            modifiers: NSEvent.ModifierFlags,
            eventTimestamp: TimeInterval,
            expected: String?
        )] = [
            ("control return", "\r", .control, 0, "\r"),
            ("modified control return", "\r", [.control, .shift, .command, .option], 0, "\r"),
            ("control slash", "/", .control, 0, "_"),
            ("caps control slash", "/", [.control, .capsLock], 0, "_"),
            ("command return", "\r", .command, 11, nil),
            ("plain slash", "/", [], 11, nil),
            ("command slash", "/", .command, 11, nil),
            ("control shift slash", "/", [.control, .shift], 11, nil),
            ("control command slash", "/", [.control, .command], 11, nil),
            ("control option slash", "/", [.control, .option], 11, nil)
        ]
        for row in cases {
            var timestamp: TimeInterval? = 9
            let event = try keyEvent(
                characters: row.characters, modifiers: row.modifiers, timestamp: row.eventTimestamp
            )
            XCTAssertEqual(characters(for: event, timestamp: &timestamp), row.expected, row.label)
            XCTAssertEqual(timestamp, 9, row.label)
        }
    }

    func testZeroTimestampDoesNotAlterPendingRetry() throws {
        for flags: NSEvent.ModifierFlags in [[], .command, .control] {
            var timestamp: TimeInterval? = 9
            let event = try keyEvent(characters: "a", modifiers: flags, timestamp: 0)

            XCTAssertNil(characters(for: event, timestamp: &timestamp))
            XCTAssertEqual(timestamp, 9)
        }
    }

    func testUnmodifiedKeyClearsPendingRetry() throws {
        for flags: NSEvent.ModifierFlags in [[], .shift, .option] {
            var timestamp: TimeInterval? = 9
            let event = try keyEvent(characters: "a", modifiers: flags)

            XCTAssertNil(characters(for: event, timestamp: &timestamp))
            XCTAssertNil(timestamp)
        }
    }

    func testModifiedKeyIsConsumedOnlyOnItsSecondPass() throws {
        for flags: NSEvent.ModifierFlags in [.command, .control, [.command, .control]] {
            var timestamp: TimeInterval?
            let event = try keyEvent(characters: "a", modifiers: flags, timestamp: 11)

            XCTAssertNil(characters(for: event, timestamp: &timestamp))
            XCTAssertEqual(timestamp, 11)
            XCTAssertEqual(characters(for: event, timestamp: &timestamp), "a")
            XCTAssertNil(timestamp)
            XCTAssertNil(characters(for: event, timestamp: &timestamp))
            XCTAssertEqual(timestamp, 11)
        }
    }

    func testDifferentModifiedKeyReplacesPendingRetry() throws {
        var timestamp: TimeInterval? = 9
        let event = try keyEvent(characters: "b", modifiers: .command, timestamp: 11)

        XCTAssertNil(characters(for: event, timestamp: &timestamp))
        XCTAssertEqual(timestamp, 11)
        XCTAssertEqual(characters(for: event, timestamp: &timestamp), "b")
        XCTAssertNil(timestamp)
    }

    func testEmptyCharactersRemainAnAcceptedSecondPass() throws {
        var timestamp: TimeInterval? = 11
        let event = try keyEvent(characters: "", modifiers: .command, timestamp: 11)

        XCTAssertEqual(characters(for: event, timestamp: &timestamp), "")
        XCTAssertNil(timestamp)
    }

    private func characters(for event: NSEvent, timestamp: inout TimeInterval?) -> String? {
        QuakeGhosttyInputBridge.keyEquivalentCharacters(for: event, lastPerformKeyEvent: &timestamp)
    }

    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        timestamp: TimeInterval = 11
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        ))
    }
}
