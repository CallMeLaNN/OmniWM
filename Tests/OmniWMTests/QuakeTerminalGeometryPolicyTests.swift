// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class QuakeTerminalGeometryPolicyTests: XCTestCase {
    private let staleFrame = CGRect(x: 640, y: 353, width: 1280, height: 705)
    private let builtInFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let builtInVisibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    private let externalFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testCustomFrameContainmentAcrossDisplayBoundaries() {
        let cases: [(label: String, frame: CGRect, screen: CGRect, expected: Bool)] = [
            ("stale built-in full", staleFrame, builtInFrame, false),
            ("stale built-in visible", staleFrame, builtInVisibleFrame, false),
            ("stale original external", staleFrame, externalFrame, true),
            ("screen equality", builtInFrame, builtInFrame, true),
            ("edge touching minimum", CGRect(x: 1528, y: 1017, width: 200, height: 100), builtInFrame, true),
            ("subpoint overhang", CGRect(x: -0.5, y: 0, width: 200, height: 100), builtInFrame, true),
            ("right overhang", CGRect(x: 1529.5, y: 0, width: 200, height: 100), builtInFrame, false),
            ("left overhang", CGRect(x: -1.5, y: 0, width: 200, height: 100), builtInFrame, false),
            ("zero screen", CGRect(x: 0, y: 0, width: 200, height: 100), .zero, false),
            ("non-target display", CGRect(x: 1728, y: 0, width: 200, height: 100), builtInFrame, false)
        ]
        for row in cases {
            XCTAssertEqual(
                QuakeTerminalGeometryPolicy.customFrameFits(row.frame, in: row.screen),
                row.expected,
                row.label
            )
        }
    }

    func testChangedFrameReturnsExactOptionalFrame() {
        let moved = staleFrame.offsetBy(dx: 10, dy: -5)
        let resized = CGRect(x: 640, y: 353, width: 1200, height: 700)
        let cases: [(label: String, target: CGRect, expected: CGRect?)] = [
            ("identical", staleFrame, nil),
            ("moved", moved, moved),
            ("resized", resized, resized)
        ]
        for row in cases {
            XCTAssertEqual(
                QuakeTerminalGeometryPolicy.changedFrame(from: staleFrame, to: row.target),
                row.expected,
                row.label
            )
        }
    }
}
