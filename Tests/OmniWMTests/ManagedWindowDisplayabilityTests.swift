// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
final class ManagedWindowDisplayabilityTests: XCTestCase {
    func testBorrowedPredicatesTrackVisibilityAndSuppression() throws {
        let controller = WindowAdmissionTestSupport.controller(prefix: "BorrowedDisplayability")
        let manager = controller.workspaceManager
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let token = WindowToken(pid: 687_001, windowId: 687_101)
        _ = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        try assertDisplayable(true, token: token, controller: controller)
        manager.setHiddenState(
            HiddenState(proportionalPosition: .zero, referenceMonitorId: nil, reason: .layoutTransient(.left)),
            for: token
        )
        try assertDisplayable(false, token: token, controller: controller)
        manager.setHiddenState(nil, for: token)
        manager.setWindowMinimized(true, token: token)
        try assertDisplayable(false, token: token, controller: controller)
        manager.setWindowMinimized(false, token: token)
        manager.setAppHidden(true, pid: token.pid, source: .ax)
        try assertDisplayable(false, token: token, controller: controller)
        manager.setAppHidden(false, pid: token.pid, source: .ax)
        manager.setLayoutReason(.nativeFullscreen, for: token)
        try assertDisplayable(false, token: token, controller: controller)
        manager.setLayoutReason(.standard, for: token)
        try assertDisplayable(true, token: token, controller: controller)
        XCTAssertFalse(controller.isManagedWindowDisplayable(WindowToken(pid: 687_001, windowId: 687_999)))
    }

    private func assertDisplayable(_ expected: Bool, token: WindowToken, controller: WMController) throws {
        let entry = try XCTUnwrap(controller.workspaceManager.entry(for: token))
        let world = WorldView(controller: controller)
        XCTAssertEqual(controller.isManagedWindowDisplayable(token), expected)
        XCTAssertEqual(controller.isManagedWindowDisplayable(entry), expected)
        XCTAssertEqual(world.isManagedWindowDisplayable(entry), expected)
        XCTAssertEqual(world.isWindowFullscreenInLayout(entry), world.isWindowFullscreenInLayout(token))
    }
}
