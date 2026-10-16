// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
@testable import OmniWM
import QuartzCore
import XCTest

@MainActor
final class ResizeOverlayControllerTests: XCTestCase {
    private let screenFrame = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testPanelsAppearOnlyForWindowsThatMove() {
        let moving = WindowToken(pid: 1001, windowId: 101)
        let still = WindowToken(pid: 1001, windowId: 102)
        let overlay = makeOverlay(currentFrames: [moving: frame(x: 0, width: 400), still: frame(x: 420, width: 400)])

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .glass, followsAnimation: false)
        let grown = frame(x: 0, width: 480)
        overlay.update([moving: grown, still: frame(x: 420, width: 400)])

        XCTAssertEqual(Set(overlay.panels.keys), [moving])
        XCTAssertEqual(overlay.panels[moving]?.frame, grown)
        overlay.reset()
    }

    func testGlassNeverCaptures() {
        var captured = false
        let token = WindowToken(pid: 1002, windowId: 103)
        let overlay = makeOverlay(currentFrames: [token: frame(x: 0, width: 400)]) { _, _ in
            captured = true
            return nil
        }

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .glass, followsAnimation: false)
        overlay.update([token: frame(x: 0, width: 300)])

        XCTAssertNotNil(overlay.panels[token])
        XCTAssertTrue(overlay.captureTasks.isEmpty)
        XCTAssertFalse(captured)
        overlay.reset()
    }

    func testSnapshotFallsBackToGlassWithoutPermission() {
        let token = WindowToken(pid: 1003, windowId: 104)
        let overlay = makeOverlay(currentFrames: [token: frame(x: 0, width: 400)], captureAllowed: false)

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .snapshot, followsAnimation: false)
        overlay.update([token: frame(x: 0, width: 300)])

        XCTAssertEqual(overlay.panels[token]?.isVisible, true)
        XCTAssertTrue(overlay.captureTasks.isEmpty)
        overlay.reset()
    }

    func testSnapshotShowsCapturedImage() async {
        let token = WindowToken(pid: 1004, windowId: 105)
        let overlay = makeOverlay(currentFrames: [token: frame(x: 0, width: 400)]) { _, _ in CGImage.blank() }

        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .snapshot, followsAnimation: false)
        overlay.update([token: frame(x: 0, width: 300)])
        let capture = overlay.captureTasks[token]
        await capture?.value

        XCTAssertEqual(overlay.panels[token]?.showsSnapshot, true)
        overlay.reset()
    }

    func testLiveStyleNeverStarts() {
        let overlay = makeOverlay(currentFrames: [:])
        overlay.begin(workspaceId: WorkspaceDescriptor.ID(), style: .live, followsAnimation: false)
        XCTAssertFalse(overlay.isActive)
    }

    func testFinishKeepsPanelsUntilTheirWriteLands() {
        let written = WindowToken(pid: 1005, windowId: 106)
        let pending = WindowToken(pid: 1005, windowId: 107)
        let overlay = makeOverlay(currentFrames: [written: frame(x: 0, width: 400), pending: frame(x: 420, width: 400)])
        let workspaceId = WorkspaceDescriptor.ID()
        overlay.begin(workspaceId: workspaceId, style: .glass, followsAnimation: true)
        let writtenTarget = frame(x: 0, width: 480)
        overlay.update([written: writtenTarget, pending: frame(x: 500, width: 400)])

        overlay.finish { $0 == written ? writtenTarget : nil }
        XCTAssertEqual(Set(overlay.panels.keys), [pending])
        XCTAssertFalse(overlay.isTracking(workspaceId))

        overlay.frameApplied(windowId: pending.windowId)
        XCTAssertTrue(overlay.panels.isEmpty)
        XCTAssertFalse(overlay.isActive)
    }

    func testMouseResizeMovesPanelsWithoutFrameWrites() throws {
        let fixture = try makeLayoutFixture()
        let mouse = fixture.controller.mouseEventHandler
        let resized = try XCTUnwrap(fixture.engine.findNode(for: fixture.left, in: fixture.workspaceId))
        let frame = try XCTUnwrap(resized.renderedFrame ?? resized.frame)
        let start = CGPoint(x: frame.maxX - 2, y: frame.midY)
        fixture.controller.settings.gestures.resizePreviewStyle = .glass

        XCTAssertTrue(mouse.beginNiriResize(
            window: resized, engine: fixture.engine, wsId: fixture.workspaceId, at: start, source: .mouse(.right)
        ))
        let overlay = fixture.controller.resizeOverlay
        FrameApplyTrace.shared.beginCapture()
        defer { FrameApplyTrace.shared.endCapture() }
        mouse.updateManagedResize(at: CGPoint(x: start.x - 120, y: start.y))

        XCTAssertLessThan(try XCTUnwrap(overlay.panels[fixture.left]?.frame.width), frame.width)
        XCTAssertNotNil(overlay.panels[fixture.right])
        XCTAssertEqual(frameApplications(fixture), 0)

        mouse.completeActiveResize()
        XCTAssertFalse(mouse.state.isResizing)
        XCTAssertTrue(overlay.isFollowingAnimation(in: fixture.workspaceId))
        fixture.controller.layoutRefreshController.niriHandler.tickScrollAnimation(
            targetTime: CACurrentMediaTime() + 5,
            displayId: fixture.monitor.displayId
        )
        XCTAssertGreaterThan(frameApplications(fixture), 0)
        XCTAssertFalse(overlay.isTracking(fixture.workspaceId))
        overlay.reset()
    }

    func testKeyboardResizeAnimatesPanelsAndWritesOnceSettled() throws {
        let fixture = try makeLayoutFixture()
        fixture.controller.settings.gestures.resizePreviewStyle = .glass
        let handler = fixture.controller.layoutRefreshController.niriHandler
        let handle = try XCTUnwrap(fixture.controller.workspaceManager.handle(for: fixture.left))

        XCTAssertTrue(fixture.controller.niriLayoutHandler.setContainerPrimarySpan(
            .adjustProportion(10),
            target: .window(handle)
        ))
        let overlay = fixture.controller.resizeOverlay
        XCTAssertTrue(overlay.isFollowingAnimation(in: fixture.workspaceId))

        FrameApplyTrace.shared.beginCapture()
        defer { FrameApplyTrace.shared.endCapture() }
        handler.tickScrollAnimation(targetTime: CACurrentMediaTime() + 0.03, displayId: fixture.monitor.displayId)
        XCTAssertFalse(overlay.panels.isEmpty)
        XCTAssertEqual(frameApplications(fixture), 0)

        handler.tickScrollAnimation(targetTime: CACurrentMediaTime() + 5, displayId: fixture.monitor.displayId)
        XCTAssertGreaterThan(frameApplications(fixture), 0)
        XCTAssertFalse(overlay.isTracking(fixture.workspaceId))
        overlay.reset()
    }

    private struct LayoutFixture {
        let controller: WMController
        let engine: NiriLayoutEngine
        let monitor: Monitor
        let workspaceId: WorkspaceDescriptor.ID
        let left: WindowToken
        let right: WindowToken
    }

    private func makeLayoutFixture() throws -> LayoutFixture {
        let controller = WindowAdmissionTestSupport.controller(prefix: "ResizeOverlayControllerTests")
        let monitor = Monitor(
            id: .init(displayId: 92),
            displayId: 92,
            frame: screenFrame,
            visibleFrame: screenFrame,
            hasNotch: false,
            name: "Main"
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        controller.niriLayoutHandler.enableNiriLayout()
        controller.layoutRefreshController.displayLinkActivationForTests = { _ in true }
        let engine = try XCTUnwrap(controller.niriEngine)

        let pid: pid_t = 962_001
        let tokens = [962_101, 962_102].map { windowId in
            controller.workspaceManager.addWindow(
                AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
                pid: pid, windowId: windowId, to: workspaceId
            )
        }
        for token in tokens {
            _ = engine.addWindow(token: token, to: workspaceId, afterSelection: nil)
        }
        controller.layoutRefreshController.renderInteractiveResize(for: workspaceId)
        for (token, frame) in engine.captureWindowFrames(in: workspaceId) {
            controller.axManager.confirmFrameWrite(for: token.windowId, frame: frame)
        }
        return LayoutFixture(
            controller: controller,
            engine: engine,
            monitor: monitor,
            workspaceId: workspaceId,
            left: tokens[0],
            right: tokens[1]
        )
    }

    private func frameApplications(_ fixture: LayoutFixture) -> Int {
        FrameApplyTrace.shared.dump().split(separator: "\n").count { line in
            [fixture.left, fixture.right].contains { line.contains("win=\($0.windowId) ") }
        }
    }

    private func frame(x: CGFloat, width: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX + x, y: screenFrame.minY, width: width, height: 300)
    }

    private func makeOverlay(
        currentFrames: [WindowToken: CGRect],
        captureAllowed: Bool = true,
        capture: ResizeOverlayController.ImageCapture? = nil
    ) -> ResizeOverlayController {
        ResizeOverlayController(
            captureAccessAllowed: { captureAllowed },
            captureImage: capture ?? { _, _ in nil },
            currentFrame: { currentFrames[$0] }
        )
    }
}

extension CGImage {
    fileprivate static func blank() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
