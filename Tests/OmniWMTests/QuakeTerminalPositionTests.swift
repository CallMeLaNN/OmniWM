// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class QuakeTerminalPositionTests: XCTestCase {
    private let offsetVisibleFrame = CGRect(x: 200, y: 1000, width: 1000, height: 900)
    private let windowSize = CGSize(width: 500, height: 300)
    private let builtInVisibleFrame = CGRect(x: 0, y: 0, width: 1728, height: 1084)

    func testCenterOriginsOnOffsetMonitor() {
        XCTAssertEqual(
            QuakeTerminalPosition.center.initialOrigin(visibleFrame: offsetVisibleFrame, windowSize: windowSize),
            CGPoint(x: 450, y: 1300)
        )
        XCTAssertEqual(
            QuakeTerminalPosition.center.finalOrigin(visibleFrame: offsetVisibleFrame, windowSize: windowSize),
            CGPoint(x: 450, y: 1300)
        )
    }

    func testOffsetMonitorOrigins() {
        let cases: [(QuakeTerminalPosition, CGPoint, CGPoint)] = [
            (.top, CGPoint(x: 450, y: 1900), CGPoint(x: 450, y: 1600)),
            (.bottom, CGPoint(x: 450, y: 700), CGPoint(x: 450, y: 1000)),
            (.left, CGPoint(x: -300, y: 1300), CGPoint(x: 200, y: 1300)),
            (.right, CGPoint(x: 1200, y: 1300), CGPoint(x: 700, y: 1300))
        ]
        for (position, initial, final) in cases {
            XCTAssertEqual(position.initialOrigin(visibleFrame: offsetVisibleFrame, windowSize: windowSize), initial)
            XCTAssertEqual(position.finalOrigin(visibleFrame: offsetVisibleFrame, windowSize: windowSize), final)
        }
    }

    func testBuiltInDisplayHalfSizeConfigurationMatchesRegressionFixture() {
        let size = QuakeTerminalGeometryPolicy.configuredFrameSize(
            visibleFrame: builtInVisibleFrame,
            widthPercent: 50,
            heightPercent: 50
        )
        XCTAssertEqual(size, CGSize(width: 864, height: 542))
    }

    func testCenterFinalOriginUsesTargetSizeOnBuiltInDisplay() {
        let targetSize = CGSize(width: 864, height: 542)
        let staleSize = CGSize(width: 1280, height: 705)
        let targetOrigin = QuakeTerminalPosition.center.finalOrigin(
            visibleFrame: builtInVisibleFrame,
            windowSize: targetSize
        )
        let staleOrigin = QuakeTerminalPosition.center.finalOrigin(
            visibleFrame: builtInVisibleFrame,
            windowSize: staleSize
        )
        XCTAssertEqual(targetOrigin.x, 432)
        XCTAssertEqual(staleOrigin.x, 224)
    }
}
