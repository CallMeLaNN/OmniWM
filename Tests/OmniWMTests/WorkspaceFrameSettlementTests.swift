// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceFrameSettlementTests: XCTestCase {
    func testScopeFiltersUnrelatedWindowAndProcessTokens() {
        let target = makeTarget(windowId: 764_911)
        let settlement = makeSettlement(for: target)
        let otherWindow = makeTarget(windowId: target.windowId + 1)
        let otherProcess = makeTarget(pid: target.pid + 1, windowId: target.windowId)
        var changes = 0
        settlement.onChange = { changes += 1 }

        XCTAssertNil(settlement.observe(otherWindow))
        XCTAssertNil(settlement.observe(otherProcess))
        settlement.reject(otherWindow)
        settlement.reject(otherProcess)

        XCTAssertFalse(settlement.failed)
        XCTAssertEqual(changes, 0)
        settlement.seal()
        XCTAssertTrue(settlement.isSettled)
    }

    func testCompletedWritesWaitForSealBeforeSettling() throws {
        let target = makeTarget(windowId: 764_912)
        let settlement = makeSettlement(for: target)
        let observer = try XCTUnwrap(settlement.observe(target))
        var settledAtChange: [Bool] = []
        settlement.onChange = { settledAtChange.append(settlement.isSettled) }

        observer(result(for: target))

        XCTAssertFalse(settlement.isSettled)
        XCTAssertFalse(settlement.sealed)
        XCTAssertEqual(settledAtChange, [false])
        settlement.seal()
        XCTAssertTrue(settlement.isSettled)
        XCTAssertEqual(settledAtChange, [false, true])
    }

    func testMultipleSubmissionsForSameWindowRequireEveryResult() throws {
        let target = makeTarget(windowId: 764_913)
        let settlement = makeSettlement(for: target)
        let first = try XCTUnwrap(settlement.observe(target))
        let second = try XCTUnwrap(settlement.observe(target))
        settlement.seal()

        second(result(for: target, requestId: 2))

        XCTAssertFalse(settlement.isSettled)
        XCTAssertFalse(settlement.failed)
        first(result(for: target, requestId: 1))
        XCTAssertTrue(settlement.isSettled)
        XCTAssertFalse(settlement.failed)
    }

    func testTerminalFailureResolvesSubmissionAndReportsFailure() throws {
        let target = makeTarget(windowId: 764_914)
        let settlement = makeSettlement(for: target)
        let observer = try XCTUnwrap(settlement.observe(target))
        settlement.seal()

        observer(result(for: target, failure: .readbackFailed))

        XCTAssertTrue(settlement.isSettled)
        XCTAssertTrue(settlement.failed)
    }

    func testRejectedTargetReportsFailureAndStillWaitsForSubmittedWork() throws {
        let target = makeTarget(windowId: 764_915)
        let settlement = makeSettlement(for: target)
        let observer = try XCTUnwrap(settlement.observe(target))
        settlement.seal()

        settlement.reject(target)

        XCTAssertTrue(settlement.failed)
        XCTAssertFalse(settlement.isSettled)
        observer(result(for: target))
        XCTAssertTrue(settlement.isSettled)
        XCTAssertTrue(settlement.failed)
    }

    func testRejectedTargetWithoutSubmissionResolvesAtSeal() {
        let target = makeTarget(windowId: 764_916)
        let settlement = makeSettlement(for: target)

        settlement.reject(target)

        XCTAssertFalse(settlement.isSettled)
        XCTAssertTrue(settlement.failed)
        settlement.seal()
        XCTAssertTrue(settlement.isSettled)
    }

    func testTerminalCallbackCanSubmitFollowupBeforeOriginalSettles() throws {
        let target = makeTarget(windowId: 764_917)
        let settlement = makeSettlement(for: target)
        let original = try XCTUnwrap(settlement.observe(target))
        var followup: AXFrameApplicationTerminalObserver?
        var settledAtChange: [Bool] = []
        settlement.onChange = { settledAtChange.append(settlement.isSettled) }
        settlement.seal()
        let terminal: AXFrameApplicationTerminalObserver = { outcome in
            followup = settlement.observe(target)
            original(outcome)
        }

        terminal(result(for: target, requestId: 1))

        XCTAssertFalse(settlement.isSettled)
        XCTAssertEqual(settledAtChange, [false, false])
        try XCTUnwrap(followup)(result(for: target, requestId: 2))
        XCTAssertTrue(settlement.isSettled)
        XCTAssertFalse(settlement.failed)
        XCTAssertEqual(settledAtChange, [false, false, true])
    }

    func testDuplicateCallbackCannotFailOrSettleAnotherSubmission() throws {
        let target = makeTarget(windowId: 764_918)
        let settlement = makeSettlement(for: target)
        let first = try XCTUnwrap(settlement.observe(target))
        let second = try XCTUnwrap(settlement.observe(target))
        var changes = 0
        settlement.onChange = { changes += 1 }
        settlement.seal()
        first(result(for: target, requestId: 1))

        first(result(for: target, requestId: 1, failure: .cancelled))

        XCTAssertEqual(changes, 2)
        XCTAssertFalse(settlement.isSettled)
        XCTAssertFalse(settlement.failed)
        second(result(for: target, requestId: 2))
        XCTAssertTrue(settlement.isSettled)
        XCTAssertEqual(changes, 3)
        second(result(for: target, requestId: 2))
        XCTAssertEqual(changes, 3)
    }

    private func makeSettlement(for target: AXFrameApplicationTarget) -> AXFrameSettlement {
        AXFrameSettlement(tokens: [WindowToken(pid: target.pid, windowId: target.windowId)])
    }

    private func makeTarget(pid: pid_t = getpid(), windowId: Int) -> AXFrameApplicationTarget {
        AXFrameApplicationTarget(
            pid: pid,
            window: AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            frame: CGRect(x: 20, y: 30, width: 640, height: 480)
        )
    }

    private func result(
        for target: AXFrameApplicationTarget,
        requestId: AXFrameRequestId = 1,
        failure: AXFrameWriteFailureReason? = nil
    ) -> AXFrameApplyResult {
        AXFrameApplyResult(
            requestId: requestId,
            pid: target.pid,
            windowId: target.windowId,
            expectedWindow: target.expectedWindow,
            targetFrame: target.frame,
            currentFrameHint: nil,
            writeResult: AXFrameWriteResult(
                observedFrame: target.frame,
                writeOrder: .sizeThenPosition,
                sizeError: .success,
                positionError: .success,
                failureReason: failure
            )
        )
    }
}
