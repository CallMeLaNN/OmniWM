// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

final class StatusItemClickRoutingTests: XCTestCase {
    func testHiddenMenuBarIconReturnsWhileRecordingOrSecureInputIsShown() {
        XCTAssertEqual(StatusBarController.labeledImagePosition(showIcon: true, hasStateIcon: false), .imageLeft)
        XCTAssertEqual(StatusBarController.labeledImagePosition(showIcon: false, hasStateIcon: false), .noImage)
        XCTAssertEqual(StatusBarController.labeledImagePosition(showIcon: false, hasStateIcon: true), .imageLeft)
    }

    func testClickRoutesForButtonAndOption() {
        let cases: [(right: Bool, option: Bool, expected: StatusBarController.StatusItemClickRoute)] = [
            (false, false, .menu),
            (true, false, .hiddenIconsBar),
            (false, true, .hiddenIconsBar),
            (true, true, .hiddenIconsBar)
        ]
        for row in cases {
            XCTAssertEqual(
                StatusBarController.clickRoute(isRightClick: row.right, optionHeld: row.option),
                row.expected,
                "right=\(row.right) option=\(row.option)"
            )
        }
    }

    func testAccessibilityValueIncludesWorkspaceAppAndRecordingState() {
        XCTAssertEqual(
            StatusBarController.statusButtonAccessibilityValue(
                workspaceLabel: "Code",
                focusedAppName: "Xcode",
                isRecording: true,
                isSecureInputActive: false
            ),
            "Recording diagnostics, Workspace Code, Focused app Xcode"
        )
        XCTAssertEqual(
            StatusBarController.statusButtonAccessibilityValue(
                workspaceLabel: "Code",
                focusedAppName: nil,
                isRecording: false,
                isSecureInputActive: true
            ),
            "Secure Input is on, Workspace Code"
        )
    }

    func testAccessibilityValueHasStableFallback() {
        XCTAssertEqual(
            StatusBarController.statusButtonAccessibilityValue(
                workspaceLabel: nil,
                focusedAppName: nil,
                isRecording: false,
                isSecureInputActive: false
            ),
            "Window manager controls"
        )
    }
}
