// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class NiriCommandNavigationTests: XCTestCase {
    private final class FocusRecorder {
        var tokens: [WindowToken] = []
    }

    private struct Fixture {
        let controller: WMController
        let monitor: Monitor
        let workspace: WorkspaceDescriptor.ID
        let nextWorkspace: WorkspaceDescriptor.ID
        let nodes: [NiriWindow]
        let recorder: FocusRecorder
    }

    func testIndexedWindowCommandUsesRememberedColumnBeforeViewportSelectionIsInitialized() throws {
        for row in [(source: 0, target: 1), (source: 2, target: 2)] {
            let fixture = try makeFixture(commitInitialViewport: false)
            let manager = fixture.controller.workspaceManager
            XCTAssertTrue(manager.setManagedFocus(
                fixture.nodes[row.source].token,
                in: fixture.workspace,
                onMonitor: fixture.monitor.id
            ))
            XCTAssertEqual(manager.lastFocusedToken(in: fixture.workspace), fixture.nodes[row.source].token)
            XCTAssertNil(manager.niriViewportState(for: fixture.workspace).selectedNodeId)
            fixture.controller.layoutRefreshController.resetState()

            try LayoutRefreshTestSupport
                .withBlocked(fixture.controller, in: fixture.workspace, reason: .layoutCommand) {
                    XCTAssertEqual(
                        fixture.controller.commandHandler.performCommand(.focusNavigation(.windowInColumn(1))),
                        .executed
                    )

                    let target = fixture.nodes[row.target]
                    XCTAssertEqual(fixture.recorder.tokens, [target.token])
                    XCTAssertEqual(fixture.controller.intentLedger.activeManagedRequest?.token, target.token)
                    XCTAssertEqual(manager.niriViewportState(for: fixture.workspace).selectedNodeId, target.id)
                    XCTAssertEqual(manager.lastFocusedToken(in: fixture.workspace), target.token)
                    XCTAssertEqual(fixture.controller.activeWorkspace()?.id, fixture.workspace)
                    let refresh = try XCTUnwrap(fixture.controller.layoutRefreshController.layoutState.pendingRefresh)
                    XCTAssertEqual(refresh.reason, .layoutCommand)
                    XCTAssertEqual(refresh.affectedWorkspaceIds, [fixture.workspace])
                }
        }
    }

    func testWindowOrWorkspaceCommandUsesLocalTargetThenAdjacentWorkspaceWithoutWrapping() throws {
        let rows = [
            (source: 1, down: true, target: Optional(0), switchesWorkspace: false),
            (source: 0, down: true, target: Optional(3), switchesWorkspace: true),
            (source: 1, down: false, target: Optional<Int>.none, switchesWorkspace: false)
        ]
        for row in rows {
            let fixture = try makeFixture()
            select(row.source, in: fixture)
            fixture.controller.layoutRefreshController.resetState()
            let manager = fixture.controller.workspaceManager
            let selected = manager.niriViewportState(for: fixture.workspace).selectedNodeId

            try LayoutRefreshTestSupport
                .withBlocked(fixture.controller, in: fixture.workspace, reason: .layoutCommand) {
                    XCTAssertEqual(fixture.controller.commandHandler.performCommand(
                        .focusNavigation(row.down ? .windowOrWorkspaceDown : .windowOrWorkspaceUp)
                    ), .executed)

                    guard let targetIndex = row.target else {
                        XCTAssertEqual(fixture.controller.activeWorkspace()?.id, fixture.workspace)
                        XCTAssertEqual(manager.niriViewportState(for: fixture.workspace).selectedNodeId, selected)
                        XCTAssertTrue(fixture.recorder.tokens.isEmpty)
                        XCTAssertNil(fixture.controller.intentLedger.activeManagedRequest)
                        XCTAssertNil(fixture.controller.layoutRefreshController.layoutState.pendingRefresh)
                        return
                    }
                    let target = fixture.nodes[targetIndex]
                    let refresh = try XCTUnwrap(fixture.controller.layoutRefreshController.layoutState.pendingRefresh)
                    if row.switchesWorkspace {
                        XCTAssertEqual(fixture.controller.activeWorkspace()?.id, fixture.nextWorkspace)
                        XCTAssertEqual(refresh.reason, .workspaceTransition)
                        XCTAssertTrue(fixture.recorder.tokens.isEmpty)
                        XCTAssertEqual(manager.niriViewportState(for: fixture.workspace).selectedNodeId, selected)
                        XCTAssertFalse(refresh.postLayoutActions.isEmpty)
                        for action in refresh.postLayoutActions {
                            XCTAssertTrue(action.isCurrent(using: manager))
                            action.runIfCurrent(using: manager)
                        }
                    } else {
                        XCTAssertEqual(fixture.controller.activeWorkspace()?.id, fixture.workspace)
                        XCTAssertEqual(refresh.reason, .layoutCommand)
                        XCTAssertEqual(refresh.affectedWorkspaceIds, [fixture.workspace])
                        XCTAssertEqual(manager.niriViewportState(for: fixture.workspace).selectedNodeId, target.id)
                    }
                    XCTAssertEqual(fixture.recorder.tokens, [target.token])
                    XCTAssertEqual(fixture.controller.intentLedger.activeManagedRequest?.token, target.token)
                }
        }
    }

    private func select(_ index: Int, in fixture: Fixture) {
        let target = fixture.nodes[index]
        let manager = fixture.controller.workspaceManager
        XCTAssertTrue(manager.setManagedFocus(target.token, in: fixture.workspace, onMonitor: fixture.monitor.id))
        _ = manager.commitWorkspaceSelection(
            nodeId: target.id,
            focusedToken: target.token,
            in: fixture.workspace,
            onMonitor: fixture.monitor.id
        )
        XCTAssertEqual(fixture.controller.activeWorkspace()?.id, fixture.workspace)
        fixture.recorder.tokens.removeAll()
    }

    private func makeFixture(commitInitialViewport: Bool = true) throws -> Fixture {
        let recorder = FocusRecorder()
        let controller = WindowAdmissionTestSupport.controller(
            prefix: "NiriCommandNavigationTests",
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { pid, windowId, _ in
                    recorder.tokens.append(WindowToken(pid: pid, windowId: Int(windowId)))
                },
                afterSubmittedFocus: { _ in },
                raiseWindow: { _ in }
            )
        )
        let directory = controller.settings.settingsFileURL.deletingLastPathComponent().deletingLastPathComponent()
        addTeardownBlock { @MainActor in
            controller.deadlineWheel.stop()
            controller.intentLedger.reset()
            controller.axEventHandler.cleanup()
            controller.layoutRefreshController.resetState()
            controller.hotkeys.stop()
            controller.mouseEventHandler.cleanup()
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        controller.setAnimationsEnabled(false)
        controller.settings.niri.infiniteLoop = false
        controller.settings.workspaceBar.hideEmptyWorkspaces = false
        let monitor = Monitor(
            id: .init(displayId: 991_401),
            displayId: 991_401,
            frame: CGRect(x: 0, y: 0, width: 1_600, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_600, height: 900),
            hasNotch: false,
            name: "Command Navigation"
        )
        let manager = controller.workspaceManager
        manager.applyMonitorConfigurationChange([monitor])
        let workspace = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let nextWorkspace = try XCTUnwrap(manager.workspaceId(for: "2", createIfMissing: true))
        manager.assignWorkspaceToMonitor(workspace, monitorId: monitor.id)
        manager.assignWorkspaceToMonitor(nextWorkspace, monitorId: monitor.id)
        _ = manager.focusWorkspace(id: workspace)
        controller.niriLayoutHandler.enableNiriLayout()
        controller.layoutRefreshController.resetState()
        let engine = try XCTUnwrap(controller.niriEngine)
        var nodes: [NiriWindow] = []
        for index in 0 ..< 4 {
            let token = WindowToken(pid: 991_410 + pid_t(index), windowId: 991_420 + index)
            let destination = index == 3 ? nextWorkspace : workspace
            _ = WindowAdmissionTestSupport.track(token, in: destination, controller: controller)
            nodes.append(engine.addWindow(token: token, to: destination, afterSelection: nodes.last?.id))
        }
        var state = ViewportState(selectedNodeId: nodes[0].id)
        let firstColumn = try XCTUnwrap(engine.column(of: nodes[0]))
        manager.withEngineMutationScope(in: workspace) {
            XCTAssertTrue(engine.consumeWindow(
                nodes[1],
                into: firstColumn,
                enteringFrom: .down,
                context: .init(
                    workspaceId: workspace,
                    motion: .disabled,
                    workingFrame: monitor.visibleFrame,
                    gaps: controller.innerGap(for: monitor),
                    orientation: .horizontal
                ),
                state: &state
            ))
        }
        XCTAssertEqual(engine.columns(in: workspace).count, 2)
        XCTAssertEqual(engine.column(of: nodes[0])?.windowNodes.map(\.token), [nodes[0].token, nodes[1].token])
        if commitInitialViewport {
            manager.updateNiriViewportState(state, for: workspace)
        }
        _ = manager.commitWorkspaceSelection(
            nodeId: nodes[3].id,
            focusedToken: nodes[3].token,
            in: nextWorkspace,
            onMonitor: monitor.id
        )
        _ = manager.focusWorkspace(id: workspace)
        controller.layoutRefreshController.resetState()
        return Fixture(
            controller: controller,
            monitor: monitor,
            workspace: workspace,
            nextWorkspace: nextWorkspace,
            nodes: nodes,
            recorder: recorder
        )
    }
}
