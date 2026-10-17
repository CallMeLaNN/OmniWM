// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

final class AppAXWindowRebindOperationTests: XCTestCase {
    private enum Interposition: CaseIterable {
        case none
        case destinationReused
        case elementClaimedElsewhere
    }

    func testPreparedRebindPreservesNewerDestinationAndForeignElementClaims() throws {
        for interposition in Interposition.allCases {
            let pid: pid_t = 991_430
            let oldWindow = AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: 991_431)
            let newWindow = AXWindowRef(element: AXUIElementCreateApplication(pid + 1), windowId: 991_432)
            let interposedElement = AXUIElementCreateApplication(pid + 2)
            let claimantId = 991_433

            try $appThreadToken.withValue(AppThreadToken(pid: pid)) {
                let state = AppAXWindowOperationState(
                    windows: ThreadGuardedValue([oldWindow.windowId: oldWindow.element]),
                    windowBindingEpoch: LockedGenerationEpoch(),
                    axObserver: ThreadGuardedValue(nil),
                    subscribedWindows: ThreadGuardedValue([:]),
                    pendingNotificationRemovals: ThreadGuardedValue([])
                )
                defer {
                    state.windows.destroy()
                    state.axObserver.destroy()
                    state.subscribedWindows.destroy()
                    state.pendingNotificationRemovals.destroy()
                }
                let binding = try XCTUnwrap(AppAXWindowRebindPreparation(
                    oldWindowId: oldWindow.windowId,
                    newWindow: newWindow,
                    timeoutSeconds: 0.5,
                    state: state
                ).perform(job: RunLoopJob()))
                XCTAssertFalse(binding.hasLifecycleObserver)
                XCTAssertNil(binding.destinationWindowElement)
                XCTAssertNil(binding.destinationSubscription)
                XCTAssertNil(state.windows[newWindow.windowId])

                switch interposition {
                case .none:
                    break
                case .destinationReused:
                    state.windows[newWindow.windowId] = interposedElement
                case .elementClaimedElsewhere:
                    state.windows[claimantId] = newWindow.element
                }

                let committed = try AppAXWindowRebindCommitOperation(
                    oldWindow: oldWindow,
                    newWindow: newWindow,
                    binding: binding,
                    retireOldWindowState: true,
                    state: state
                ).perform(job: RunLoopJob())

                XCTAssertTrue(state.subscribedWindows.value.isEmpty)
                XCTAssertTrue(state.pendingNotificationRemovals.value.isEmpty)
                switch interposition {
                case .none:
                    XCTAssertTrue(committed)
                    XCTAssertEqual(Set(state.windows.value.keys), [newWindow.windowId])
                    XCTAssertNil(state.windows[oldWindow.windowId])
                    XCTAssertTrue(state.windows[newWindow.windowId].map { CFEqual($0, newWindow.element) } == true)
                case .destinationReused:
                    XCTAssertFalse(committed)
                    XCTAssertEqual(Set(state.windows.value.keys), [oldWindow.windowId, newWindow.windowId])
                    XCTAssertTrue(state.windows[oldWindow.windowId].map { CFEqual($0, oldWindow.element) } == true)
                    XCTAssertTrue(state.windows[newWindow.windowId].map { CFEqual($0, interposedElement) } == true)
                case .elementClaimedElsewhere:
                    XCTAssertFalse(committed)
                    XCTAssertEqual(Set(state.windows.value.keys), [oldWindow.windowId, claimantId])
                    XCTAssertTrue(state.windows[oldWindow.windowId].map { CFEqual($0, oldWindow.element) } == true)
                    XCTAssertTrue(state.windows[claimantId].map { CFEqual($0, newWindow.element) } == true)
                    XCTAssertNil(state.windows[newWindow.windowId])
                }
            }
        }
    }
}
