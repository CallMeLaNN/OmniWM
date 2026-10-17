// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import CoreText
@testable import OmniWM
import XCTest

@MainActor
final class NativeFullscreenPlaceholderTitleTests: XCTestCase {
    func testWindowForwardsTitleOnlyUpdateToExistingView() throws {
        let token = WindowToken(pid: 1, windowId: 1)
        var descriptor = NativeFullscreenPlaceholderUpdate(
            originalToken: token,
            currentToken: token,
            workspaceId: UUID(),
            windowTitle: "Before",
            frame: .zero,
            displayContext: nil,
            selected: false,
            visible: false
        )
        let window = NativeFullscreenPlaceholderWindow(placeholder: descriptor, appName: "Editor", icon: nil)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView as? NativeFullscreenPlaceholderView)
        XCTAssertEqual(view.titleText, "Before")
        descriptor.windowTitle = "After"
        window.update(descriptor, forceOrdering: false)
        XCTAssertTrue(window.contentView === view)
        XCTAssertEqual(view.titleText, "After")
    }

    func testTitleFallsBackToAppNameAndChangesWithoutLosingActivation() {
        let view = NativeFullscreenPlaceholderView(windowTitle: "  ", appName: "Editor", icon: nil)
        view.setFrameSize(CGSize(width: 600, height: 400))
        XCTAssertEqual(view.titleText, "Editor")
        XCTAssertEqual(view.accessibilityLabel(), "Editor, in macOS Full Screen")
        var activations = 0
        view.onActivate = { activations += 1 }
        view.setWindowTitle("Document One")
        XCTAssertEqual(view.titleText, "Document One")
        XCTAssertEqual(view.accessibilityLabel(), "Document One, in macOS Full Screen")
        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertEqual(activations, 1)
        view.setWindowTitle("")
        XCTAssertEqual(view.titleText, "Editor")
    }

    func testLongTitleTruncatesAndRetainsStatusAtNarrowWidth() throws {
        let title = String(repeating: "Long document title ", count: 20)
        let view = NativeFullscreenPlaceholderView(windowTitle: title, appName: "Editor", icon: nil)
        view.setFrameSize(CGSize(width: 220, height: 180))
        let line = try XCTUnwrap(view.displayedTitleLine)
        XCTAssertLessThanOrEqual(CTLineGetTypographicBounds(line, nil, nil, nil), 172)
        XCTAssertNotNil(view.displayedStatusLine)
        XCTAssertEqual(view.titleText, title.trimmingCharacters(in: .whitespacesAndNewlines))
        view.setSelected(true)
        view.setFrameOrigin(CGPoint(x: 100, y: 100))
        XCTAssertTrue(view.displayedTitleLine === line)
        view.setWindowTitle(title)
        XCTAssertTrue(view.displayedTitleLine === line)
        view.setFrameSize(CGSize(width: 600, height: 180))
        let wider = try XCTUnwrap(view.displayedTitleLine)
        XCTAssertGreaterThan(CTLineGetTypographicBounds(wider, nil, nil, nil), 172)
        XCTAssertLessThanOrEqual(CTLineGetTypographicBounds(wider, nil, nil, nil), 552)
    }

    func testRetainedAndHiddenProjectionsKeepFreshTitle() {
        let token = WindowToken(pid: 1, windowId: 1)
        var descriptor = NativeFullscreenPlaceholderUpdate(
            originalToken: token,
            currentToken: token,
            workspaceId: UUID(),
            windowTitle: "Before",
            frame: CGRect(x: 0, y: 0, width: 600, height: 400),
            displayContext: nil,
            selected: false,
            visible: true
        )
        let previous = descriptor
        descriptor.windowTitle = "After"
        let retained = NativeFullscreenPlaceholderResolver.retained(
            descriptor, currentToken: token, selected: false, previous: previous
        )
        XCTAssertEqual(retained.windowTitle, "After")
        XCTAssertEqual(retained.frame, previous.frame)
        let hidden = NativeFullscreenPlaceholderResolver.hidden(
            descriptor, currentToken: token, selected: false, previous: previous
        )
        XCTAssertEqual(hidden.windowTitle, "After")
        XCTAssertFalse(hidden.visible)
    }
}
