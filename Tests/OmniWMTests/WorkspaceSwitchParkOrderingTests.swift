// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceSwitchParkOrderingTests: XCTestCase {
    func testOutgoingParkWaitsForIncomingFrameWrite() throws {
        let controller = WindowAdmissionTestSupport.controller(prefix: "OmniWMWorkspaceSwitchParkOrderingTests")
        let monitor = Monitor(
            id: .init(displayId: 818),
            displayId: 818,
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1410),
            hasNotch: false,
            name: "ParkOrdering"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        let outgoingWorkspace = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let incomingWorkspace = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "2", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")

        let outgoingRef = AXWindowRef(element: AXUIElementCreateApplication(818_001), windowId: 818_101)
        let outgoing = controller.workspaceManager.addWindow(
            outgoingRef, pid: 818_001, windowId: 818_101, to: outgoingWorkspace
        )
        let incomingRef = AXWindowRef(element: AXUIElementCreateApplication(818_002), windowId: 818_102)
        _ = controller.workspaceManager.addWindow(incomingRef, pid: 818_002, windowId: 818_102, to: incomingWorkspace)
        let onscreenFrame = CGRect(x: 100, y: 16, width: 1200, height: 900)
        controller.layoutRefreshController.fastFrameProvider = { _, _ in onscreenFrame }

        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(incomingWorkspace, on: monitor.id))
        let incomingWrite = try XCTUnwrap(controller.axManager.stageFrameWrite(
            for: AXFrameApplicationTarget(pid: 818_002, window: incomingRef, frame: onscreenFrame)
        ))
        controller.layoutRefreshController.hideInactiveWorkspacesSync()

        XCTAssertEqual(controller.workspaceManager.hiddenState(for: outgoing)?.workspaceInactive, true)
        XCTAssertNotNil(controller.axManager.pendingParkFrameRequest(for: outgoing.windowId))

        controller.axManager.handleFrameApplyResults([
            WindowAdmissionTestSupport.successfulFrameResult(request: incomingWrite)
        ])

        XCTAssertNil(controller.axManager.pendingParkFrameRequest(for: outgoing.windowId))
    }
}
