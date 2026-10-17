// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class InvalidActivationPIDTests: XCTestCase {
    func testInvalidActivationObservationsPreserveManagedFocusAndPendingRequest() throws {
        let fixture = try makeFixture()
        let controller = fixture.controller
        let manager = controller.workspaceManager
        var requestedPIDs: [pid_t] = []
        controller.factResolver.factProvider = { pid in
            requestedPIDs.append(pid)
            return nil
        }
        let sources: [ActivationEventSource] = [
            .workspaceDidActivateApplication,
            .workspaceDidUnhideApplication,
            .cgsFrontAppChanged,
            .focusedWindowChanged
        ]

        for pid: pid_t in [-1, 0] {
            for source in sources {
                XCTAssertFalse(controller.axEventHandler.handleAppActivation(pid: pid, source: source))
                XCTAssertEqual(controller.axEventHandler.latestNativeActivationPID, fixture.token.pid)
                XCTAssertEqual(manager.nativeFocusOwner, .managed(fixture.token))
                XCTAssertEqual(manager.selectedManagedToken, fixture.token)
                XCTAssertEqual(manager.renderableFocusToken, fixture.token)
                XCTAssertEqual(manager.pendingFocusedToken, fixture.token)
                XCTAssertEqual(controller.intentLedger.activeManagedRequest, fixture.request)
            }
        }
        XCTAssertTrue(requestedPIDs.isEmpty)

        let externalPID = fixture.token.pid + 1
        controller.axEventHandler.handleAppActivation(pid: externalPID, source: .cgsFrontAppChanged)

        XCTAssertEqual(requestedPIDs, [externalPID])
        XCTAssertEqual(controller.axEventHandler.latestNativeActivationPID, externalPID)
        XCTAssertEqual(manager.nativeFocusOwner, .external(pid: externalPID, windowId: nil))
        XCTAssertEqual(manager.selectedManagedToken, fixture.token)
        XCTAssertNil(manager.renderableFocusToken)
        XCTAssertNil(manager.pendingFocusedToken)
        XCTAssertNil(controller.intentLedger.activeManagedRequest)
    }

    func testInvalidResolvedActivationFactsPreserveManagedFocusAndPendingRequest() throws {
        let fixture = try makeFixture()
        let controller = fixture.controller
        let manager = controller.workspaceManager

        for pid: pid_t in [-1, 0] {
            let facts = ActivationFacts(
                pid: pid,
                source: .focusedWindowChanged,
                origin: .external,
                observationGeneration: 0,
                requestedAtSeq: EventIntake.currentSeq(),
                focusedWindow: nil
            )
            XCTAssertTrue(controller.axEventHandler.isCurrentActivationFacts(facts, controller: controller))

            controller.axEventHandler.handleActivationFactsResolved(facts)

            XCTAssertEqual(controller.axEventHandler.latestNativeActivationPID, fixture.token.pid)
            XCTAssertEqual(manager.nativeFocusOwner, .managed(fixture.token))
            XCTAssertEqual(manager.selectedManagedToken, fixture.token)
            XCTAssertEqual(manager.renderableFocusToken, fixture.token)
            XCTAssertEqual(manager.pendingFocusedToken, fixture.token)
            XCTAssertEqual(controller.intentLedger.activeManagedRequest, fixture.request)
        }
    }

    private func makeFixture() throws -> (
        controller: WMController,
        token: WindowToken,
        request: ManagedFocusRequest
    ) {
        let controller = WindowAdmissionTestSupport.controller()
        let manager = controller.workspaceManager
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let token = WindowToken(pid: 468_270, windowId: 468_271)
        _ = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        XCTAssertTrue(manager.confirmManagedFocus(token, in: workspaceId, activateWorkspaceOnMonitor: false))
        let request = controller.intentLedger.beginManagedRequest(token: token, workspaceId: workspaceId)
        XCTAssertTrue(manager.beginManagedFocusRequest(token, in: workspaceId, requestId: request.requestId))
        controller.axEventHandler.latestNativeActivationPID = token.pid
        controller.factResolver.factProvider = { _ in nil }
        controller.hasStartedServices = true
        return (controller, token, request)
    }
}
