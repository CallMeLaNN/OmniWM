// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

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

    func testDominantDeltaPreservesSignsTiesAndNoiseFiltering() {
        let cases: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("verticalNegative", 1, -8, -8), ("verticalPositive", -1, 8, 8),
            ("horizontalPositive", 9, 2, 9), ("horizontalNegative", -9, 2, -9),
            ("positiveTie", 5, 5, 5), ("oppositeSignTie", -5, 5, 5),
            ("horizontalNoise", 0.00005, 0, 0), ("verticalNoise", 0, -0.00005, 0),
            ("aboveEpsilon", 0, 0.0002, 0.0002), ("zero", 0, 0, 0)
        ]
        for (label, x, y, expected) in cases {
            XCTAssertEqual(OverviewScrollInput.dominantDelta(deltaX: x, deltaY: y), expected, label)
        }
    }
}
