// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class RestorePlacementPreservationTests: XCTestCase {
    func testPlacementPreservationAcrossWorkspaceModeAndDetachedSizing() {
        let workspaceId = WorkspaceDescriptor.ID()
        let otherWorkspaceId = WorkspaceDescriptor.ID()
        let niri = PersistedNiriPlacement(
            columnIndex: 3,
            tileIndex: 2,
            column: PersistedNiriColumnState(
                displayMode: .normal,
                activeTileIndex: 2,
                width: .fixed(540),
                presetWidthIndex: nil,
                isFullWidth: false,
                savedWidth: nil,
                hasManualSingleWindowWidthOverride: false
            ),
            window: PersistedNiriWindowState(
                sizingMode: .normal,
                height: .auto(weight: 1),
                savedHeight: nil,
                windowWidth: .auto(weight: 1)
            )
        )
        let dwindle = PersistedDwindlePlacement(
            steps: [
                PersistedDwindleSplitStep(orientation: .horizontal, ratio: 1, childIndex: 0),
                PersistedDwindleSplitStep(orientation: .vertical, ratio: 0.8, childIndex: 1)
            ],
            memberIndex: 1,
            isActiveMember: false
        )
        let detached = NiriContainerSizingState(
            width: .fixed(540),
            presetWidthIndex: nil,
            isFullWidth: false,
            savedWidth: nil,
            hasManualSingleWindowWidthOverride: false
        )

        for mode in [TrackedWindowMode.tiling, .floating] {
            for sameWorkspace in [false, true] {
                for hasDetachedSizing in [false, true] {
                    var entry = makeEntry(workspaceId: workspaceId, mode: mode)
                    entry.restoreIntent = RestoreIntent(
                        topologyProfile: TopologyProfile(sortedMonitors: []),
                        workspaceId: sameWorkspace ? workspaceId : otherWorkspaceId,
                        preferredMonitor: nil,
                        floatingFrame: nil,
                        normalizedFloatingOrigin: nil,
                        restoreToFloating: mode == .floating,
                        rescueEligible: false,
                        niriPlacement: niri,
                        detachedNiriContainerSizingState: hasDetachedSizing ? detached : nil,
                        dwindlePlacement: dwindle
                    )
                    let expectedNiri: PersistedNiriPlacement? = if hasDetachedSizing {
                        sameWorkspace ? niri : niri.withoutColumnPosition
                    } else if mode == .tiling && sameWorkspace {
                        niri
                    } else {
                        nil
                    }
                    let expectedDwindle = mode == .tiling && sameWorkspace ? dwindle : nil
                    let full = StateReducer.restoreIntent(for: entry, monitors: [])

                    XCTAssertEqual(StateReducer.niriRestorePlacement(for: entry), expectedNiri)
                    XCTAssertEqual(StateReducer.dwindleRestorePlacement(for: entry), expectedDwindle)
                    XCTAssertEqual(full.niriPlacement, expectedNiri)
                    XCTAssertEqual(full.dwindlePlacement, expectedDwindle)
                    XCTAssertEqual(full.detachedNiriContainerSizingState, hasDetachedSizing ? detached : nil)
                }
            }
        }
    }

    func testMissingRestoreIntentHasNoPreservedPlacement() {
        for mode in [TrackedWindowMode.tiling, .floating] {
            let entry = makeEntry(workspaceId: WorkspaceDescriptor.ID(), mode: mode)
            XCTAssertNil(StateReducer.niriRestorePlacement(for: entry))
            XCTAssertNil(StateReducer.dwindleRestorePlacement(for: entry))
        }
    }

    private func makeEntry(workspaceId: WorkspaceDescriptor.ID, mode: TrackedWindowMode) -> WindowState {
        let token = WindowToken(pid: 42, windowId: 43)
        return WindowState(
            token: token,
            axRef: AXWindowRef(element: AXUIElementCreateApplication(token.pid), windowId: token.windowId),
            workspaceId: workspaceId,
            mode: mode,
            managedReplacementMetadata: nil,
            ruleEffects: .none,
            admissionHints: .none
        )
    }
}
