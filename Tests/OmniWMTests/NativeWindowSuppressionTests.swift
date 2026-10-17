// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class NativeWindowSuppressionTests: XCTestCase {
    func testOverlappingWithdrawalAndMinimizationKeepFenceUntilBothClear() throws {
        for reopenFirst in [true, false] {
            let controller = WindowAdmissionTestSupport.controller(prefix: "NativeWindowSuppression")
            defer { controller.serviceLifecycleManager.stop() }
            let token = WindowToken(pid: 776_101, windowId: 776_201)
            let workspace = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
            _ = WindowAdmissionTestSupport.track(token, in: workspace, controller: controller)
            let handler = controller.axEventHandler

            XCTAssertTrue(handler.updateWindowNativeWithdrawalState(true, token: token, requestRefresh: false))
            XCTAssertTrue(handler.updateWindowMinimizedState(true, token: token, requestRefresh: false))
            if reopenFirst {
                XCTAssertTrue(handler.updateWindowNativeWithdrawalState(false, token: token, requestRefresh: false))
            } else {
                XCTAssertTrue(handler.updateWindowMinimizedState(false, token: token, requestRefresh: false))
            }

            XCTAssertTrue(controller.axManager.isWindowNativeSuppressed(token))
            XCTAssertTrue(try XCTUnwrap(controller.workspaceManager.entry(for: token)).observedState.isNativeSuppressed)

            if reopenFirst {
                XCTAssertTrue(handler.updateWindowMinimizedState(false, token: token, requestRefresh: false))
            } else {
                XCTAssertTrue(handler.updateWindowNativeWithdrawalState(false, token: token, requestRefresh: false))
            }

            XCTAssertFalse(controller.axManager.isWindowNativeSuppressed(token))
            XCTAssertFalse(try XCTUnwrap(controller.workspaceManager.entry(for: token)).observedState
                .isNativeSuppressed)
        }
    }

    func testWithdrawalIgnoresMinimizedHiddenAndFullscreenWindows() throws {
        for state in 0 ..< 3 {
            let controller = WindowAdmissionTestSupport.controller(prefix: "NativeWindowSuppressionGuard")
            defer { controller.serviceLifecycleManager.stop() }
            let token = WindowToken(pid: 776_102, windowId: 776_202)
            let workspace = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
            _ = WindowAdmissionTestSupport.track(token, in: workspace, controller: controller)
            switch state {
            case 0:
                controller.axEventHandler.updateWindowMinimizedState(true, token: token, requestRefresh: false)
            case 1:
                controller.workspaceManager.setAppHidden(true, pid: token.pid, source: .ax)
            default:
                controller.workspaceManager.setLayoutReason(.nativeFullscreen, for: token)
            }

            XCTAssertFalse(controller.axEventHandler.updateWindowNativeWithdrawalState(
                true, token: token, requestRefresh: false
            ))
            XCTAssertFalse(try XCTUnwrap(controller.workspaceManager.entry(for: token)).observedState.isNativeWithdrawn)
        }
    }

    func testWithdrawnWindowIsNotVisibleInIPCWithoutChangingAppHiddenState() throws {
        let controller = WindowAdmissionTestSupport.controller(prefix: "NativeWindowSuppressionIPC")
        defer { controller.serviceLifecycleManager.stop() }
        let token = WindowToken(pid: 776_103, windowId: 776_203)
        let workspace = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        _ = WindowAdmissionTestSupport.track(token, in: workspace, controller: controller)
        XCTAssertTrue(controller.axEventHandler.updateWindowNativeWithdrawalState(
            true, token: token, requestRefresh: false
        ))
        let router = IPCQueryRouter(controller: controller, appVersion: nil, sessionToken: "native-withdrawal-tests")
        router.windowOrderedInProvider = { _ in true }

        let window = try XCTUnwrap(router.windowsResult(IPCQueryRequest(name: .windows)).windows.first)

        XCTAssertEqual(window.isVisible, false)
        XCTAssertEqual(window.isAppHidden, false)
    }
}
