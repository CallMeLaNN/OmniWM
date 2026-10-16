// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class ResizeOverlayControllerTests: XCTestCase {
    func testGlassResizeDoesNotAttemptScreenCapture() throws {
        var captureCalled = false
        let controller = ResizeOverlayController(
            captureAccessAllowed: { true },
            captureImage: { _, _ in
                captureCalled = true
                return nil
            }
        )

        let initialFrame = CGRect(x: 100, y: 100, width: 600, height: 400)
        let token = WindowToken(pid: 1001, windowId: 101)

        controller.beginResize(
            token: token,
            initialFrame: initialFrame,
            appIcon: nil,
            style: .glass
        )

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.token, token)
        XCTAssertFalse(captureCalled)
        XCTAssertNotNil(controller.overlayWindow)

        let updatedFrame = CGRect(x: 100, y: 100, width: 750, height: 400)
        controller.updateFrame(updatedFrame)
        XCTAssertEqual(controller.overlayWindow?.frame, updatedFrame)

        controller.endResize()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.token)
        controller.destroy()
    }

    func testSnapshotFallsBackToGlassWhenPermissionDenied() throws {
        var captureCalled = false
        let controller = ResizeOverlayController(
            captureAccessAllowed: { false },
            captureImage: { _, _ in
                captureCalled = true
                return nil
            }
        )

        let initialFrame = CGRect(x: 200, y: 200, width: 500, height: 350)
        let token = WindowToken(pid: 1002, windowId: 102)

        controller.beginResize(
            token: token,
            initialFrame: initialFrame,
            appIcon: nil,
            style: .snapshot
        )

        XCTAssertTrue(controller.isActive)
        XCTAssertFalse(captureCalled)
        XCTAssertNotNil(controller.overlayWindow)

        controller.destroy()
    }

    func testSnapshotShowsCapturedImageWhenPermissionGranted() async throws {
        let controller = ResizeOverlayController(
            captureAccessAllowed: { true },
            captureImage: { _, _ in CGImage.blank() }
        )

        controller.beginResize(
            token: WindowToken(pid: 1003, windowId: 103),
            initialFrame: CGRect(x: 50, y: 50, width: 400, height: 300),
            appIcon: nil,
            style: .snapshot
        )
        XCTAssertTrue(controller.isActive)
        await controller.captureTask?.value

        XCTAssertEqual(controller.overlayWindow?.showsSnapshot, true)
        controller.destroy()
    }

    func testLiveResizeStyleDoesNotActivateOverlay() throws {
        let controller = ResizeOverlayController()
        let initialFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let token = WindowToken(pid: 1004, windowId: 104)

        controller.beginResize(
            token: token,
            initialFrame: initialFrame,
            appIcon: nil,
            style: .live
        )

        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.overlayWindow)
        controller.destroy()
    }

    func testInteractiveResizeOverlayIntegration() throws {
        let fixtureController = WindowAdmissionTestSupport.controller(prefix: "ResizeOverlayIntegrationTests")
        let monitor = Monitor(
            id: .init(displayId: 92),
            displayId: 92,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050),
            hasNotch: false,
            name: "Main"
        )
        fixtureController.workspaceManager.applyMonitorConfigurationChange([monitor])
        let workspaceId = try XCTUnwrap(fixtureController.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = fixtureController.workspaceManager.focusWorkspace(named: "1")
        fixtureController.niriLayoutHandler.enableNiriLayout()
        let engine = try XCTUnwrap(fixtureController.niriEngine)

        let pid: pid_t = 962_001
        let token = fixtureController.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: 962_101),
            pid: pid, windowId: 962_101, to: workspaceId
        )
        _ = engine.addWindow(token: token, to: workspaceId, afterSelection: nil)

        fixtureController.layoutRefreshController.renderInteractiveResize(for: workspaceId)

        let resized = try XCTUnwrap(engine.findNode(for: token, in: workspaceId))
        let frame = try XCTUnwrap(resized.renderedFrame ?? resized.frame)
        let start = CGPoint(x: frame.maxX - 2, y: frame.midY)
        let mouse = fixtureController.mouseEventHandler

        fixtureController.settings.gestures.resizePreviewStyle = .glass
        XCTAssertTrue(mouse.beginNiriResize(
            window: resized, engine: engine, wsId: workspaceId, at: start, source: .mouse(.right)
        ))
        let overlay = try XCTUnwrap(mouse.state.resizeOverlayController)
        XCTAssertTrue(overlay.isActive)

        mouse.updateManagedResize(at: CGPoint(x: start.x - 120, y: start.y))
        XCTAssertLessThan(try XCTUnwrap(overlay.overlayWindow?.frame.width), frame.width)

        mouse.completeActiveResize()
        XCTAssertFalse(mouse.state.isResizing)
        XCTAssertFalse(overlay.isActive)

        fixtureController.settings.gestures.resizePreviewStyle = .live
        XCTAssertTrue(mouse.beginNiriResize(
            window: resized, engine: engine, wsId: workspaceId, at: start, source: .mouse(.right)
        ))
        XCTAssertFalse(overlay.isActive)
        mouse.completeActiveResize()
    }
}

extension CGImage {
    fileprivate static func blank() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 40,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
