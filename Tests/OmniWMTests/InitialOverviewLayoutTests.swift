// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class InitialOverviewLayoutTests: XCTestCase {
    private final class Effects {
        var focusCalls = 0
        var displayLinkStarts = 0
    }

    private struct Fixture {
        let controller: WMController
        let monitor: Monitor
        let activeWorkspaceId: WorkspaceDescriptor.ID
        let inactiveWorkspaceId: WorkspaceDescriptor.ID
        let activeToken: WindowToken
        let inactiveTokens: [WindowToken]
        let effects: Effects
    }

    func testInitialFullRescanRestoresInactiveNiriColumnsBeforeFirstOverview() throws {
        let fixture = try makeFixture(layoutType: .niri)
        defer { cleanUp(fixture) }
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let engine = try XCTUnwrap(controller.niriEngine)
        let column = PersistedNiriColumnState(
            displayMode: .normal,
            activeTileIndex: 0,
            width: .fixed(540),
            presetWidthIndex: nil,
            isFullWidth: false,
            savedWidth: nil,
            hasManualSingleWindowWidthOverride: false
        )
        let window = PersistedNiriWindowState(
            sizingMode: .normal,
            height: .auto(weight: 1),
            savedHeight: nil,
            windowWidth: .auto(weight: 1)
        )
        let placements = Dictionary(uniqueKeysWithValues: fixture.inactiveTokens.enumerated().map { index, token in
            (token, PersistedNiriPlacement(
                columnIndex: index == 2 ? 1 : 0,
                tileIndex: index == 1 ? 1 : 0,
                column: column,
                window: window
            ))
        })
        manager.setNiriRestorePlacements(placements)
        XCTAssertTrue(engine.columns(in: fixture.inactiveWorkspaceId).isEmpty)

        try applyInitialPlan(fixture)

        let columns = engine.columns(in: fixture.inactiveWorkspaceId)
        XCTAssertEqual(columns.map { $0.windowNodes.map(\.token) }, [
            Array(fixture.inactiveTokens.prefix(2)),
            [fixture.inactiveTokens[2]]
        ])
        XCTAssertEqual(columns.map(\.width), [.fixed(540), .fixed(540)])
        for token in fixture.inactiveTokens {
            XCTAssertEqual(manager.restoreIntent(for: token)?.niriPlacement, placements[token])
        }
        let snapshot = try assertOverviewContainsInactiveCards(fixture)
        XCTAssertEqual(snapshot.niriSnapshotsByWorkspace[fixture.inactiveWorkspaceId]?.columns.count, 2)
        assertInactiveWorkspaceStayedInactive(fixture)
    }

    func testInitialFullRescanRestoresInactiveDwindleGroupBeforeFirstOverview() throws {
        let fixture = try makeFixture(layoutType: .dwindle)
        defer { cleanUp(fixture) }
        let controller = fixture.controller
        let manager = controller.workspaceManager
        let engine = try XCTUnwrap(controller.dwindleEngine)
        let placements = Dictionary(uniqueKeysWithValues: fixture.inactiveTokens.enumerated().map { index, token in
            (token, PersistedDwindlePlacement(
                steps: [PersistedDwindleSplitStep(
                    orientation: .horizontal,
                    ratio: 1,
                    childIndex: index == 2 ? 1 : 0
                )],
                memberIndex: index == 1 ? 1 : 0,
                isActiveMember: index != 0
            ))
        })
        manager.setDwindleRestorePlacements(placements)
        XCTAssertTrue(engine.currentFrames(in: fixture.inactiveWorkspaceId).isEmpty)

        try applyInitialPlan(fixture)

        let group = try XCTUnwrap(engine.groupedTileSnapshots(in: fixture.inactiveWorkspaceId).first)
        XCTAssertEqual(group.members.map(\.token), Array(fixture.inactiveTokens.prefix(2)))
        XCTAssertEqual(group.activeToken, fixture.inactiveTokens[1])
        for token in fixture.inactiveTokens {
            XCTAssertEqual(manager.restoreIntent(for: token)?.dwindlePlacement, placements[token])
        }
        let snapshot = try assertOverviewContainsInactiveCards(fixture)
        let overviewGroup = try XCTUnwrap(snapshot.dwindleGroupsByWorkspace[fixture.inactiveWorkspaceId]?.first)
        XCTAssertEqual(overviewGroup.windowHandles.map(\.id), Array(fixture.inactiveTokens.prefix(2)))
        XCTAssertEqual(overviewGroup.activeHandle.id, fixture.inactiveTokens[1])
        assertInactiveWorkspaceStayedInactive(fixture)
    }

    func testLaterFullRescansKeepInactiveWorkspacesOutsideImplicitLayoutScope() throws {
        for layoutType in [LayoutType.niri, .dwindle] {
            let fixture = try makeFixture(layoutType: layoutType)
            defer { cleanUp(fixture) }
            fixture.controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh = true

            let plan = fullRescanPlan(fixture)

            XCTAssertEqual(plan.workspacePlans.map(\.workspaceId), [fixture.activeWorkspaceId])
            XCTAssertTrue(fixture.controller.niriEngine?.columns(in: fixture.inactiveWorkspaceId).isEmpty == true)
            XCTAssertTrue(fixture.controller.dwindleEngine?.currentFrames(in: fixture.inactiveWorkspaceId)
                .isEmpty == true)
        }
    }

    private func makeFixture(layoutType: LayoutType) throws -> Fixture {
        let effects = Effects()
        let controller = WindowAdmissionTestSupport.controller(
            prefix: "InitialOverviewLayoutTests",
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in effects.focusCalls += 1 },
                focusSpecificWindow: { _, _, _ in effects.focusCalls += 1 },
                raiseWindow: { _ in effects.focusCalls += 1 },
                orderWindow: { _ in effects.focusCalls += 1 }
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let monitor = Monitor(
            id: .init(displayId: 493_100),
            displayId: 493_100,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Initial Overview"
        )
        controller.settings.workspaces.configurations = ["1", "2"].map {
            WorkspaceConfiguration(
                name: $0,
                monitorAssignment: .specificDisplay(OutputId(from: monitor)),
                layoutType: layoutType
            )
        }
        let manager = controller.workspaceManager
        manager.applyMonitorConfigurationChange([monitor])
        manager.applySettings()
        let activeWorkspaceId = try XCTUnwrap(manager.workspaceId(named: "1"))
        let inactiveWorkspaceId = try XCTUnwrap(manager.workspaceId(named: "2"))
        XCTAssertTrue(manager.setActiveWorkspace(activeWorkspaceId, on: monitor.id))
        controller.enableNiriLayout()
        controller.enableDwindleLayout()
        controller.layoutRefreshController.resetState()
        controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh = false
        controller.layoutRefreshController.displayLinkActivationForTests = { _ in
            effects.displayLinkStarts += 1
            return true
        }
        let tokens = (0 ..< 4).map { WindowToken(pid: 493_200 + pid_t($0), windowId: 493_300 + $0) }
        for (index, token) in tokens.enumerated() {
            _ = WindowAdmissionTestSupport.track(
                token,
                in: index == 0 ? activeWorkspaceId : inactiveWorkspaceId,
                controller: controller
            )
            manager.setCachedConstraints(.unconstrained, for: token)
        }
        XCTAssertTrue(manager.setManagedFocus(tokens[0], in: activeWorkspaceId))
        return Fixture(
            controller: controller,
            monitor: monitor,
            activeWorkspaceId: activeWorkspaceId,
            inactiveWorkspaceId: inactiveWorkspaceId,
            activeToken: tokens[0],
            inactiveTokens: Array(tokens.dropFirst()),
            effects: effects
        )
    }

    private func fullRescanPlan(_ fixture: Fixture) -> EffectPlan {
        fixture.controller.layoutRefreshController.buildFullRescanLayoutPlan(
            FullRescanLayoutRequest(
                removalPayloads: [],
                relayoutWorkspaceIds: nil,
                postLayoutActions: [],
                postLayoutActionWorkspacesCurrentAtMutation: []
            ),
            context: FullRescanMutationContext(
                controller: fixture.controller,
                enumerationSnapshot: .init(
                    windows: [],
                    successfullyEnumeratedPIDs: [],
                    failedPIDs: [],
                    authoritativeTargetPIDs: [],
                    exactWindowIds: nil,
                    identityAliasesByWindowId: [:],
                    windowServerInfoByWindowId: [:]
                ),
                scope: .all,
                focusedWorkspaceId: fixture.activeWorkspaceId,
                screenFrames: [fixture.monitor.frame]
            ),
            affectedWorkspaceIds: [fixture.inactiveWorkspaceId]
        )
    }

    private func applyInitialPlan(_ fixture: Fixture) throws {
        let plan = fullRescanPlan(fixture)
        XCTAssertEqual(Set(plan.workspacePlans.map(\.workspaceId)), [
            fixture.activeWorkspaceId, fixture.inactiveWorkspaceId
        ])
        let inactivePlan = try XCTUnwrap(plan.workspacePlans.first {
            $0.workspaceId == fixture.inactiveWorkspaceId
        })
        XCTAssertFalse(inactivePlan.isActiveWorkspace)
        XCTAssertFalse(inactivePlan.diff.frameChanges.isEmpty)
        XCTAssertTrue(inactivePlan.diff.restoreChanges.isEmpty)
        fixture.controller.layoutRefreshController.applyEffectPlan(plan, controller: fixture.controller)
        XCTAssertTrue(fixture.controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh)
    }

    @discardableResult
    private func assertOverviewContainsInactiveCards(_ fixture: Fixture) throws -> OverviewSnapshot {
        var environment = OverviewEnvironment()
        environment.windowTitle = { "Window \($0.windowId)" }
        environment.windowFrame = { _ in CGRect(x: 10000, y: 10000, width: 540, height: 400) }
        let snapshot = OverviewSnapshot(
            wmController: fixture.controller,
            facts: OverviewWindowFacts(wmController: fixture.controller, environment: environment)
        )
        snapshot.build()
        let projection = OverviewViewportProjection(wmController: fixture.controller, snapshot: snapshot, scale: 1)
        projection.rebuildProjectedLayouts()
        let layout = try XCTUnwrap(projection.layoutsByMonitor[fixture.monitor.id])
        let section = try XCTUnwrap(layout.workspaceSections.first { $0.workspaceId == fixture.inactiveWorkspaceId })
        let inactiveCards = layout.allWindows.filter { $0.workspaceId == fixture.inactiveWorkspaceId }
        XCTAssertEqual(Set(inactiveCards.map { $0.handle.id }), Set(fixture.inactiveTokens))
        XCTAssertTrue(inactiveCards.allSatisfy { !$0.overviewFrame.isEmpty })
        XCTAssertTrue(inactiveCards.filter(\.isDisplayed)
            .allSatisfy { section.clipFrame(for: $0).intersects($0.overviewFrame) })
        return snapshot
    }

    private func assertInactiveWorkspaceStayedInactive(_ fixture: Fixture) {
        let controller = fixture.controller
        XCTAssertEqual(
            controller.workspaceManager.activeWorkspace(on: fixture.monitor.id)?.id,
            fixture.activeWorkspaceId
        )
        XCTAssertEqual(controller.workspaceManager.selectedManagedToken, fixture.activeToken)
        XCTAssertEqual(controller.workspaceManager.nativeManagedFocusToken, fixture.activeToken)
        XCTAssertEqual(fixture.effects.focusCalls, 0)
        XCTAssertEqual(fixture.effects.displayLinkStarts, 0)
        XCTAssertFalse(controller.niriLayoutHandler.hasScrollAnimation(for: fixture.inactiveWorkspaceId))
        XCTAssertFalse(controller.dwindleLayoutHandler.hasDwindleAnimationRunning(in: fixture.inactiveWorkspaceId))
        for token in fixture.inactiveTokens {
            XCTAssertTrue(controller.axManager.inactiveWorkspaceWindowIds.contains(token.windowId))
            XCTAssertFalse(controller.axManager.frameLedger.hasPendingFrameWrite(for: token.windowId))
        }
    }

    private func cleanUp(_ fixture: Fixture) {
        fixture.controller.layoutRefreshController.resetState()
        fixture.controller.axManager.cleanup()
    }
}
