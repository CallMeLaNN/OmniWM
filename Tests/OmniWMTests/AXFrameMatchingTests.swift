// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class AXFrameMatchingTests: XCTestCase {
    func testFrameMatchingPreservesComponentBoundaries() {
        let fractional = CGRect(x: 10, y: 10, width: 1_265, height: 692.5)
        let topEdge = CGRect(x: 40, y: 50, width: 500, height: 400)
        let size = CGRect(x: 10, y: 20, width: 300, height: 200)
        let cases: [(String, CGRect, CGRect, AXFrameComponents, Bool)] = [
            ("fractional", fractional, CGRect(x: 10, y: 9, width: 1_265, height: 693), .all, true),
            ("differentTop", fractional, CGRect(x: 10, y: 8.5, width: 1_265, height: 693), .all, false),
            ("differentLeft", fractional, CGRect(x: 11, y: 9, width: 1_265, height: 693), .all, false),
            ("refusedSizePosition", fractional, CGRect(x: 10, y: 9, width: 1_265, height: 693.5), .position, true),
            ("refusedSize", fractional, CGRect(x: 10, y: 9, width: 1_265, height: 693.5), .size, false),
            ("refusedSizeAll", fractional, CGRect(x: 10, y: 9, width: 1_265, height: 693.5), .all, false),
            ("sameTop", topEdge, CGRect(x: 40, y: 210, width: 320, height: 240), .position, true),
            ("sameBottom", topEdge, CGRect(x: 40, y: 50, width: 320, height: 240), .position, false),
            ("sameTopAll", topEdge, CGRect(x: 40, y: 210, width: 320, height: 240), .all, false),
            ("sizeOnly", size, CGRect(x: 100, y: 400, width: 300, height: 200), .size, true),
            ("sizeAll", size, CGRect(x: 100, y: 400, width: 300, height: 200), .all, false)
        ]
        for (label, target, observed, components, expected) in cases {
            XCTAssertEqual(axFrameMatches(observed, target: target, components: components), expected, label)
        }
    }

    func testFractionalResizeReplacesOldGeometryWithoutRetryAndDeduplicatesTarget() throws {
        let ledger = AXFrameApplicationLedger()
        let pid = getpid()
        let window = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: 467_601)
        let target = CGRect(x: 10, y: 10, width: 1_265, height: 692.5)
        let observed = CGRect(x: 10, y: 9, width: 1_265, height: 693)
        ledger.confirmFrameWrite(
            for: window.windowId,
            frame: CGRect(x: 10, y: 10, width: 1_265, height: 1_395)
        )
        let request = try XCTUnwrap(WindowAdmissionTestSupport.frameRequest(
            ledger, pid: pid, window: window, frame: target
        ))
        var accepted: [AXFrameApplyResult] = []

        let outcome = ledger.handleFrameApplyResults([
            WindowAdmissionTestSupport.verificationMismatchFrameResult(request: request, observed: observed)
        ]) { accepted.append($0) }

        XCTAssertEqual(accepted.map(\.confirmedFrame), [observed])
        XCTAssertEqual(ledger.lastAppliedFrame(for: window.windowId), observed)
        XCTAssertEqual(ledger.trustedVerifiedSize(for: window.windowId), observed.size)
        XCTAssertFalse(ledger.hasPendingFrameWrite(for: window.windowId))
        XCTAssertNil(ledger.recentFrameWriteFailure(for: window.windowId))
        XCTAssertTrue(outcome.retries.isEmpty)
        XCTAssertTrue(outcome.terminalRefusals.isEmpty)
        XCTAssertTrue(outcome.terminalFailures.isEmpty)
        XCTAssertNil(WindowAdmissionTestSupport.frameRequest(
            ledger, pid: pid, window: window, frame: target
        ))
    }

    func testVerifiedPositionCacheDeduplicatesOnlyTheSameTopLeft() {
        let ledger = AXFrameApplicationLedger()
        let pid = getpid()
        let window = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: 467_602)
        let observed = CGRect(x: 40, y: 210, width: 320, height: 240)
        ledger.confirmFrameWrite(for: window.windowId, frame: observed)

        let sameTop = ledger.prepareFrameApplication(
            .init(
                pid: pid, window: window,
                frame: CGRect(x: 40, y: 50, width: 500, height: 400), components: .position
            ),
            isRetry: false,
            terminalObserver: nil
        )
        XCTAssertNil(sameTop.request)

        let sameBottom = ledger.prepareFrameApplication(
            .init(
                pid: pid, window: window,
                frame: CGRect(x: 40, y: 210, width: 500, height: 400), components: .position
            ),
            isRetry: false,
            terminalObserver: nil
        )
        XCTAssertNotNil(sameBottom.request)
    }
}
