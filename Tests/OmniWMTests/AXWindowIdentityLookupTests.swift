// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

final class AXWindowIdentityLookupTests: XCTestCase {
    func testCancelledLookupDoesNotEnumerateApplication() {
        let job = RunLoopJob()
        job.cancel()

        XCTAssertThrowsError(try AXWindowService.uncachedWindowRef(
            windowId: 999_871,
            pid: 999_870,
            deadline: ProcessInfo.processInfo.systemUptime + 1,
            checkCancellation: { try job.checkCancellation() }
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testExpiredLookupDoesNotEnumerateApplication() {
        XCTAssertThrowsError(try AXWindowService.uncachedWindowRef(
            windowId: 999_871,
            pid: 999_870,
            deadline: 0,
            checkCancellation: {}
        )) { error in
            guard case AXWindowEnumerationError.timedOut = error else {
                return XCTFail("Expected the lookup deadline to expire, got \(error)")
            }
        }
    }

    func testStalePinnedValidationPreservesReplacement() {
        let windowId: UInt32 = 999_871
        let oldElement = AXUIElementCreateApplication(999_870)
        let replacement = AXUIElementCreateApplication(999_872)
        defer { AXWindowService.unpinAXElement(for: windowId) }

        AXWindowService.pinAXElement(oldElement, for: windowId)
        AXWindowService.pinAXElement(replacement, for: windowId)
        AXWindowService.unpinAXElement(for: windowId, matching: oldElement)
        XCTAssertTrue(AXWindowService.hasPinnedAXElement(for: windowId))

        AXWindowService.unpinAXElement(for: windowId, matching: replacement)
        XCTAssertFalse(AXWindowService.hasPinnedAXElement(for: windowId))
    }
}
