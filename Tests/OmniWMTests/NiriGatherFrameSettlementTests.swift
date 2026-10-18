// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class NiriGatherFrameSettlementTests: XCTestCase {
    private let queuedFrame = CGRect(x: 7, y: 9, width: 111, height: 97)

    private func queueFrameWrite(
        for id: Int,
        in fixture: NiriGatherFixture,
        terminalResults: @escaping AXFrameApplicationTerminalObserver
    ) throws -> AXFrameApplicationRequest {
        let token = fixture.token(id)
        let window = try XCTUnwrap(fixture.manager.entry(for: token)?.axRef)
        let decision = fixture.controller.axManager.frameLedger.prepareFrameApplication(
            AXFrameApplicationTarget(pid: token.pid, window: window, frame: queuedFrame),
            isRetry: false,
            terminalObserver: terminalResults
        )
        XCTAssertTrue(decision.deliveries.isEmpty)
        return try XCTUnwrap(decision.request)
    }

    private func completeSuccessfully(_ request: AXFrameApplicationRequest, in fixture: NiriGatherFixture) {
        fixture.controller.axManager.handleFrameApplyResults(
            [WindowAdmissionTestSupport.successfulFrameResult(request: request)],
            applyParkPosition: { _ in
                XCTFail("A gathered window is not parked")
                return .submitted
            }
        )
    }

    private func makeFixture(displayId: UInt32) throws -> (NiriGatherFixture, WorkspaceDescriptor.ID) {
        let monitor = NiriGatherFixture.monitor(displayId: displayId)
        let fixture = try NiriGatherFixture(
            prefix: "OmniWMNiriGatherFrameSettlement",
            monitors: [monitor],
            workspaces: [.init(name: "1")]
        )
        let workspace = fixture.workspace("1")
        XCTAssertTrue(fixture.manager.setActiveWorkspace(workspace, on: monitor.id))
        fixture.add([1, 2, 3], to: workspace)
        fixture.select(1, in: workspace)
        return (fixture, workspace)
    }

    func testRefusedAndUnchangedGathersLeaveQueuedFrameWritesToSettleOnce() async throws {
        let (fixture, workspace) = try makeFixture(displayId: 74_201)
        XCTAssertTrue(fixture.manager.setWindowMinimized(true, token: fixture.token(3)))
        guard case .gathered = try fixture.gather([1, 2], from: .workspace) else {
            return XCTFail("expected the setup gather to apply")
        }
        await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)
        let ledger = fixture.controller.axManager.frameLedger
        var terminalResults: [AXFrameApplyResult] = []
        let queued = try queueFrameWrite(for: 1, in: fixture) { terminalResults.append($0) }

        let refused = try fixture.gather([1, 3], from: .workspace)
        let unchanged = try fixture.gather([1, 2], from: .workspace)
        await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)

        XCTAssertEqual(refused, .refused(.windows([fixture.token(3): .minimized])))
        XCTAssertEqual(unchanged, .unchanged)
        XCTAssertEqual(ledger.pendingFrameWrite(for: fixture.token(1).windowId), queuedFrame)
        XCTAssertTrue(terminalResults.isEmpty)

        completeSuccessfully(queued, in: fixture)
        completeSuccessfully(queued, in: fixture)

        XCTAssertEqual(terminalResults.map(\.requestId), [queued.requestId])
        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [nil])
        XCTAssertEqual(ledger.lastAppliedFrame(for: fixture.token(1).windowId), queuedFrame)
        XCTAssertFalse(ledger.hasPendingFrameWrite(for: fixture.token(1).windowId))
        XCTAssertEqual(fixture.layout(workspace), [[1, 2], [3]])
    }

    func testGatherCommitCancelsAnOlderQueuedFrameWriteOnceBeforeItsRelayoutWrites() async throws {
        let (fixture, workspace) = try makeFixture(displayId: 74_202)
        await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)
        let ledger = fixture.controller.axManager.frameLedger
        let windowId = fixture.token(1).windowId
        var terminalResults: [AXFrameApplyResult] = []
        let queued = try queueFrameWrite(for: 1, in: fixture) { terminalResults.append($0) }

        guard case .gathered = try fixture.gather([2, 1], from: .workspace) else {
            return XCTFail("expected the gather to apply")
        }

        XCTAssertEqual(terminalResults.map(\.requestId), [queued.requestId])
        XCTAssertEqual(terminalResults.map(\.writeResult.failureReason), [.cancelled])
        XCTAssertFalse(ledger.hasPendingFrameWrite(for: windowId))
        XCTAssertNil(ledger.recentFrameWriteFailure(for: windowId))

        await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)

        XCTAssertEqual(ledger.recentFrameWriteFailure(for: windowId), .contextUnavailable)
        XCTAssertEqual(terminalResults.map(\.requestId), [queued.requestId])

        completeSuccessfully(queued, in: fixture)

        XCTAssertEqual(terminalResults.map(\.requestId), [queued.requestId])
        XCTAssertNil(ledger.lastAppliedFrame(for: windowId))
        XCTAssertFalse(ledger.hasPendingFrameWrite(for: windowId))
        XCTAssertEqual(fixture.layout(workspace), [[2, 1], [3]])
        XCTAssertEqual(fixture.manager.workspace(for: fixture.token(1)), workspace)
    }
}
