// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import CoreGraphics
@testable import OmniWM
import XCTest

final class OverviewScrollInputTests: XCTestCase {
    func testOpeningGestureTailIsConsumedUntilANewScrollBegins() {
        var gate = OverviewScrollInput.GestureScrollGate(awaitingNewGesture: true)
        var event = OverviewScrollInput.Event(
            deltaX: 15, deltaY: -60, modifiers: [], isPrecise: true, location: .zero,
            phase: .began
        )
        XCTAssertTrue(gate.consumes(event, state: .opening))
        for phase: NSEvent.Phase in [.changed, .ended] {
            event.phase = phase
            XCTAssertTrue(gate.consumes(event, state: .open))
        }
        event.phase = []
        for phase: NSEvent.Phase in [.began, .changed, .ended] {
            event.momentumPhase = phase
            XCTAssertTrue(gate.consumes(event, state: .open))
        }
        event.momentumPhase = []
        event.phase = .began
        XCTAssertFalse(gate.consumes(event, state: .open))
        event.phase = .changed
        XCTAssertFalse(gate.consumes(event, state: .open))
        gate = OverviewScrollInput.GestureScrollGate()
        XCTAssertFalse(gate.consumes(event, state: .open))
        gate.awaitingNewGesture = true
        let wheel = OverviewScrollInput.Event(
            deltaX: 0, deltaY: -1, modifiers: [], isPrecise: false, location: .zero
        )
        XCTAssertFalse(gate.consumes(wheel, state: .open))
    }

    func testVerticalDominanceKeepsSign() {
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: 1, deltaY: -8), -8)
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: -1, deltaY: 8), 8)
    }

    func testHorizontalDominanceKeepsSign() {
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: 9, deltaY: 2), 9)
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: -9, deltaY: 2), -9)
    }

    func testTiePrefersVertical() {
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: 5, deltaY: 5), 5)
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: -5, deltaY: 5), 5)
    }

    func testEpsilonFiltersNoise() {
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: 0.00005, deltaY: 0), 0)
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: 0, deltaY: -0.00005), 0)
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: 0, deltaY: 0.0002), 0.0002)
    }

    func testZeroInput() {
        XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: 0, deltaY: 0), 0)
    }
}
