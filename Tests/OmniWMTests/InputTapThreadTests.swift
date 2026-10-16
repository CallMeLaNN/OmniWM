// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

final class InputTapThreadTests: XCTestCase {
    func testInputTapThreadStartsAndStops() {
        let thread = InputTapThread()
        let runLoop = thread.startAndGetRunLoop()
        XCTAssertNotNil(runLoop)
        thread.stop()
    }

    func testTapSuppressionStateThreadSafety() {
        let state = TapSuppressionState()
        let iterations = 1000
        let group = DispatchGroup()

        for i in 0 ..< 4 {
            group.enter()
            DispatchQueue.global().async {
                for j in 0 ..< iterations {
                    if (i + j) % 2 == 0 {
                        state.update {
                            $0.capturedInteractionButton = .left
                            $0.isTrackpadSwipeActive = true
                        }
                    } else {
                        state.update {
                            $0.capturedInteractionButton = nil
                            $0.isTrackpadSwipeActive = false
                        }
                    }
                    _ = state.snapshot
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
    }

    @MainActor
    func testProcessTapCallbackOnDedicatedThreadSuppressesCapturedInteraction() throws {
        let controller = makeController()
        let handler = controller.mouseEventHandler
        handler.setup()
        defer { handler.cleanup() }

        let source = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: CGPoint(x: 100, y: 100),
            mouseButton: .left
        ))

        // When uncaptured: background thread tap callback must NOT suppress
        XCTAssertFalse(MouseEventHandler.processTapCallback(type: .leftMouseDragged, event: event, isMainThread: false))

        // When captured: background thread tap callback MUST suppress
        handler.state.capturedInteractionButton = MouseEventHandler.MouseButton.left
        XCTAssertTrue(MouseEventHandler.processTapCallback(type: .leftMouseDragged, event: event, isMainThread: false))

        // On release: background thread tap callback suppresses and clears captured interaction
        let upEvent = try XCTUnwrap(CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: CGPoint(x: 100, y: 100),
            mouseButton: .left
        ))
        XCTAssertTrue(MouseEventHandler.processTapCallback(type: .leftMouseUp, event: upEvent, isMainThread: false))
        XCTAssertNil(handler.tapSuppressionState.snapshot.capturedInteractionButton)
    }

    @MainActor
    func testProcessTapCallbackOnDedicatedThreadLeavesNormalScrollingUnsuppressed() throws {
        let controller = makeController()
        let handler = controller.mouseEventHandler
        handler.setup()
        defer { handler.cleanup() }

        let source = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))
        let scrollEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 1,
            wheel1: -10,
            wheel2: 0,
            wheel3: 0
        ))

        // Normal scroll with no gesture or modifiers: MUST NOT suppress on background tap thread
        XCTAssertFalse(MouseEventHandler.processTapCallback(
            type: .scrollWheel,
            event: scrollEvent,
            isMainThread: false
        ))

        // When trackpad swipe is active: MUST suppress on background tap thread
        handler.tapSuppressionState.update { $0.isTrackpadSwipeActive = true }
        scrollEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.changed.rawValue))
        XCTAssertTrue(MouseEventHandler.processTapCallback(type: .scrollWheel, event: scrollEvent, isMainThread: false))
    }

    @MainActor
    private func makeController() -> WMController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(directory: directory, startWatching: false, deferSaves: false),
            runtimeState: RuntimeStateStore(directory: directory.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
        settings.animationsEnabled = false
        return WMController(settings: settings)
    }
}
