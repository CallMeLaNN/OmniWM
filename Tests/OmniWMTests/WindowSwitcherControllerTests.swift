// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class WindowSwitcherControllerTests: XCTestCase {
    func testHiddenSwitcherRefreshDoesNotPinRetainedPreviews() async throws {
        let controller = WindowAdmissionTestSupport.controller(
            prefix: "OmniWMWindowSwitcherControllerTests",
            ownedWindowRegistry: OwnedWindowRegistry()
        )
        controller.settings.windowSwitcher.enabled = true
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(81_001), windowId: 81_002),
            pid: 81_001,
            windowId: 81_002,
            to: workspaceId
        )
        let handle = try XCTUnwrap(controller.workspaceManager.handle(for: token))
        let driver = OverviewPreviewTestDriver()
        let capture = driver.makeCapture(consumer: .windowSwitcher)
        let switcher = WindowSwitcherController(controller: controller, previewCapture: capture)
        defer {
            capture.clear()
            driver.finish()
        }

        capture.reconcile(represented: [handle], visible: [
            OverviewPreviewRequest(handle: handle, pixelWidth: 80, pixelHeight: 60)
        ])
        try await driver.waitForStarts(1)
        driver.completeAllStarts()
        let frame = try makeOverviewPreviewFrame()
        let published = expectation(description: "frame published")
        capture.onPreview = { _, preview in if preview === frame { published.fulfill() } }
        driver.streams[0].output.offer(frame)
        guard await XCTWaiter.fulfillment(of: [published], timeout: 1) == .completed else {
            XCTFail("Expected preview publication")
            throw OverviewPreviewTestWaitError.publication
        }
        switcher.dismiss()
        XCTAssertFalse(capture.isPresenting)
        XCTAssertTrue(capture.preview(for: handle) === frame)

        switcher.refreshWindows()
        XCTAssertFalse(capture.isPresenting)
        driver.coordinator.releaseCaches(reason: .memoryPressure)
        XCTAssertEqual(capture.cachedByteCount, 0)
        XCTAssertNil(capture.preview(for: handle))
    }

    func testDisablingSwitcherReleasesItsController() {
        let controller = WindowAdmissionTestSupport.controller(
            prefix: "OmniWMWindowSwitcherControllerTests",
            ownedWindowRegistry: OwnedWindowRegistry()
        )
        controller.settings.windowSwitcher.enabled = true
        _ = controller.windowSwitcherController
        XCTAssertNotNil(controller.windowSwitcherControllerStorage)
        controller.settings.windowSwitcher.enabled = false
        controller.updateWindowSwitcherSettings()
        XCTAssertNil(controller.windowSwitcherControllerStorage)
    }

    func testQueuedBeginAfterDisableDoesNotRecreateController() async {
        let controller = WindowAdmissionTestSupport.controller(
            prefix: "OmniWMWindowSwitcherControllerTests",
            ownedWindowRegistry: OwnedWindowRegistry()
        )
        controller.settings.windowSwitcher.enabled = true
        controller.hotkeys.onWindowSwitcherAction?(.begin(reverse: false), 1)
        controller.settings.windowSwitcher.enabled = false
        controller.updateWindowSwitcherSettings()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertNil(controller.windowSwitcherControllerStorage)
    }
}
