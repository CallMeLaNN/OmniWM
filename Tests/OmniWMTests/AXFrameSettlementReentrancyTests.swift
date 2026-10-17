// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class AXFrameSettlementReentrancyTests: XCTestCase {
    func testAcceptedCallbackRekeyPrecedesTerminalObserverSettlement() throws {
        for (windowId, converged) in [(467_506, false), (467_509, true)] {
            let ledger = AXFrameApplicationLedger()
            let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: windowId)
            let target = AXFrameApplicationTarget(
                pid: getpid(),
                window: window,
                frame: CGRect(x: 20, y: 30, width: 640, height: 480)
            )
            let observed = CGRect(x: 20, y: 22, width: 648, height: 488)
            let acceptedFrame = converged ? observed : target.frame
            let newWindowId = window.windowId + 1
            var terminalResults: [AXFrameApplyResult] = []
            let request: AXFrameApplicationRequest
            if converged {
                request = try primeRetry(ledger, target: target, observedFrame: observed) { terminalResults.append($0) }
            } else {
                request = try XCTUnwrap(prepare(ledger, target: target) { terminalResults.append($0) }.request)
            }
            let acceptedResult = converged
                ? WindowAdmissionTestSupport.verificationMismatchFrameResult(request: request, observed: observed)
                : WindowAdmissionTestSupport.successfulFrameResult(request: request)
            var acceptedWindowIds: [Int] = []

            let outcome = ledger
                .handleFrameApplyResults([acceptedResult]) {
                    acceptedWindowIds.append($0.windowId)
                    XCTAssertNil($0.writeResult.failureReason)
                    XCTAssertEqual($0.confirmedFrame, acceptedFrame)
                    if converged {
                        XCTAssertEqual(ledger.trustedVerifiedSize(for: window.windowId), observed.size)
                        XCTAssertNil(ledger.recentFrameWriteFailure(for: window.windowId))
                    }
                    XCTAssertEqual(ledger.lastAppliedFrame(for: window.windowId), acceptedFrame)
                    XCTAssertFalse(ledger.hasPendingFrameWrite(for: window.windowId))
                    ledger.rekeyWindowState(oldWindowId: window.windowId, newWindowId: newWindowId)
                }

            XCTAssertEqual(acceptedWindowIds, [window.windowId])
            XCTAssertNil(ledger.lastAppliedFrame(for: window.windowId))
            XCTAssertEqual(ledger.lastAppliedFrame(for: newWindowId), acceptedFrame)
            XCTAssertEqual(outcome.deliveries.map(\.result.windowId), [newWindowId])
            XCTAssertEqual(outcome.stableSizeClamps.map(\.windowId), converged ? [window.windowId] : [])
            XCTAssertEqual(
                outcome.stableSizeClamps.map(\.writeResult.failureReason),
                converged ? [.verificationMismatch] : []
            )
            XCTAssertTrue(outcome.terminalRefusals.isEmpty)
            XCTAssertTrue(outcome.terminalFailures.isEmpty)
            XCTAssertTrue(terminalResults.isEmpty)
            for delivery in outcome.deliveries { delivery.deliver() }
            XCTAssertEqual(terminalResults.map(\.requestId), [request.requestId])
            XCTAssertEqual(terminalResults.map(\.windowId), [newWindowId])
            XCTAssertEqual(terminalResults.map(\.confirmedFrame), [acceptedFrame])
            XCTAssertTrue(sameAXWindowIdentity(
                try XCTUnwrap(terminalResults.first).expectedWindow,
                AXWindowRef(element: window.element, windowId: newWindowId)
            ))
        }
    }

    func testAcceptedCallbackReplacementKeepsItsPendingWriteAndRetryBudget() throws {
        for (windowId, converged) in [(467_508, false), (467_511, true)] {
            let ledger = AXFrameApplicationLedger()
            let window = AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: windowId)
            let target = AXFrameApplicationTarget(
                pid: getpid(),
                window: window,
                frame: CGRect(x: 20, y: 30, width: 640, height: 480)
            )
            let observed = CGRect(x: 20, y: 22, width: 648, height: 488)
            let acceptedFrame = converged ? observed : target.frame
            let nextTarget = AXFrameApplicationTarget(
                pid: getpid(),
                window: window,
                frame: target.frame.offsetBy(dx: 80, dy: 0)
            )
            var terminalResults: [AXFrameApplyResult] = []
            let first: AXFrameApplicationRequest
            if converged {
                first = try primeRetry(ledger, target: target, observedFrame: observed) { terminalResults.append($0) }
            } else {
                first = try XCTUnwrap(prepare(ledger, target: target) { terminalResults.append($0) }.request)
            }
            let acceptedResult = converged
                ? WindowAdmissionTestSupport.verificationMismatchFrameResult(request: first, observed: observed)
                : WindowAdmissionTestSupport.successfulFrameResult(request: first)
            var replacement: AXFrameEnqueueDecision?

            let outcome = ledger
                .handleFrameApplyResults([acceptedResult]) { result in
                    XCTAssertNil(result.writeResult.failureReason)
                    replacement = prepare(ledger, target: nextTarget) { terminalResults.append($0) }
                }

            let replacementDecision = try XCTUnwrap(replacement)
            let replacementRequest = try XCTUnwrap(replacementDecision.request)
            XCTAssertTrue(outcome.deliveries.isEmpty)
            XCTAssertEqual(outcome.stableSizeClamps.map(\.requestId), converged ? [first.requestId] : [])
            XCTAssertEqual(ledger.lastAppliedFrame(for: window.windowId), acceptedFrame)
            XCTAssertEqual(ledger.pendingFrameWrite(for: window.windowId), nextTarget.frame)
            XCTAssertEqual(replacementDecision.deliveries.count, 1)
            for delivery in replacementDecision.deliveries { delivery.deliver() }
            XCTAssertEqual(terminalResults.map(\.requestId), [first.requestId])
            XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])
            let failedReplacement = ledger.handleFrameApplyResults([
                WindowAdmissionTestSupport.frameResult(
                    request: replacementRequest,
                    observed: acceptedFrame,
                    failure: .readbackFailed
                )
            ])
            XCTAssertEqual(failedReplacement.retries.map(\.requestId), [replacementRequest.requestId])
            XCTAssertTrue(failedReplacement.deliveries.isEmpty)
            XCTAssertTrue(failedReplacement.terminalFailures.isEmpty)
        }
    }

    private func primeRetry(
        _ ledger: AXFrameApplicationLedger,
        target: AXFrameApplicationTarget,
        observedFrame: CGRect,
        observer: @escaping AXFrameApplicationTerminalObserver
    ) throws -> AXFrameApplicationRequest {
        let first = try XCTUnwrap(prepare(ledger, target: target, observer: observer).request)
        let firstOutcome = ledger.handleFrameApplyResults([
            WindowAdmissionTestSupport.verificationMismatchFrameResult(request: first, observed: observedFrame)
        ])
        XCTAssertEqual(firstOutcome.retries.map(\.requestId), [first.requestId])
        XCTAssertTrue(firstOutcome.deliveries.isEmpty)
        return try XCTUnwrap(WindowAdmissionTestSupport.frameRequest(
            ledger, pid: target.pid, window: target.expectedWindow, frame: target.frame, isRetry: true
        ))
    }

    private func prepare(
        _ ledger: AXFrameApplicationLedger,
        target: AXFrameApplicationTarget,
        observer: @escaping AXFrameApplicationTerminalObserver
    ) -> AXFrameEnqueueDecision {
        ledger.prepareFrameApplication(
            target,
            isRetry: false,
            terminalObserver: observer
        )
    }
}
