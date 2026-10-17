// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class NiriFullscreenOuterGapsTests: XCTestCase {
    func testFullscreenKeepsInnerGapEdgeMarginOfTiledColumns() throws {
        let controller = WindowAdmissionTestSupport.controller(prefix: "OmniWMNiriFullscreenOuterGapsTests")
        controller.settings.gaps.outerGapLeft = 12
        controller.settings.gaps.outerGapRight = 12
        controller.settings.gaps.outerGapTop = 12
        controller.settings.gaps.outerGapBottom = 12
        controller.settings.gaps.fullscreenUsesOuterGaps = true
        let monitor = Monitor(
            id: .init(displayId: 92), displayId: 92,
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            hasNotch: false, name: "Main"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.niriLayoutHandler.enableNiriLayout()
        let engine = try XCTUnwrap(controller.niriEngine)
        let pid: pid_t = 962_001
        let nodes = (0 ..< 2).map { index in
            let windowId = 962_101 + index
            let token = controller.workspaceManager.addWindow(
                AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
                pid: pid, windowId: windowId, to: workspaceId
            )
            return engine.addWindow(token: token, to: workspaceId, afterSelection: nil)
        }
        nodes[1].sizingMode = .fullscreen

        let handler = controller.layoutRefreshController.niriHandler
        let snapshot = try XCTUnwrap(handler.makeWorkspaceSnapshot(
            workspaceId: workspaceId,
            monitor: monitor,
            options: .init(
                viewportState: controller.workspaceManager.niriViewportState(for: workspaceId),
                useScrollAnimationPath: false,
                removalSeed: nil,
                isActiveWorkspace: true
            )
        ))
        let plan = handler.buildOnDemandLayoutPlan(
            snapshot: snapshot, engine: engine, monitor: monitor, animationTime: nil, settlesAnimation: true
        )
        let frames = Dictionary(plan.diff.frameChanges.map { ($0.token, $0.frame) }, uniquingKeysWith: { $1 })
        let tiled = try XCTUnwrap(frames[nodes[0].token])
        let fullscreen = try XCTUnwrap(frames[nodes[1].token])
        let gap = controller.innerGap(for: monitor)

        XCTAssertEqual(fullscreen, controller.insetWorkingFrame(for: monitor).insetBy(dx: gap, dy: gap))
        XCTAssertEqual(fullscreen.minY, tiled.minY)
        XCTAssertEqual(fullscreen.height, tiled.height)
    }
}
