// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class FloatingCrossDisplayMoveTests: XCTestCase {
    func testMovingFloatingWindowToWorkspaceOnOtherDisplayRelocatesFrame() throws {
        let left = makeMonitor(displayId: 95_001, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let right = makeMonitor(displayId: 95_002, frame: CGRect(x: 1000, y: 0, width: 1400, height: 900))
        let controller = makeController(left: left, right: right)
        let manager = controller.workspaceManager
        let sourceId = try XCTUnwrap(manager.workspaceId(named: "1"))
        let targetId = try XCTUnwrap(manager.workspaceId(named: "2"))
        XCTAssertTrue(manager.setActiveWorkspace(sourceId, on: left.id, updateInteractionMonitor: false))
        XCTAssertTrue(manager.setActiveWorkspace(targetId, on: right.id, updateInteractionMonitor: false))
        let token = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(951_001), windowId: 951_101),
            pid: 951_001,
            windowId: 951_101,
            to: sourceId,
            mode: .floating
        )
        manager.updateFloatingGeometry(
            frame: CGRect(x: 120, y: 140, width: 320, height: 240),
            for: token,
            referenceMonitor: left
        )
        let refresh = controller.layoutRefreshController
        refresh.resetState()
        refresh.layoutState.isRefreshSuspendedForLockScreen = true
        defer { refresh.resetState() }

        let handle = try XCTUnwrap(manager.handle(for: token))
        let outcome = controller.workspaceNavigationHandler.commitWindowMove(handle: handle, toWorkspaceId: targetId)
        guard case .changed = outcome else { return XCTFail("move did not change state") }

        let state = try XCTUnwrap(manager.floatingState(for: token))
        XCTAssertEqual(state.referenceMonitorId, right.id)
        XCTAssertTrue(right.visibleFrame.contains(state.lastFrame))

        let pending = try XCTUnwrap(refresh.layoutState.pendingRefresh)
        var plan = EffectPlan(
            workspacePlans: [
                WorkspaceLayoutPlan(
                    workspaceId: targetId,
                    monitor: refresh.buildMonitorSnapshot(for: right),
                    sessionPatch: WorkspaceSessionPatch(workspaceId: targetId, plannedSeq: manager.worldSeq),
                    diff: WorkspaceLayoutDiff()
                )
            ]
        )
        refresh.applyWorkspaceMonitorRelocations(pending.workspaceMonitorRelocations, to: &plan)
        let frameChange = try XCTUnwrap(plan.workspacePlans[0].diff.frameChanges.first { $0.token == token })
        XCTAssertEqual(frameChange.frame, state.lastFrame)
        XCTAssertTrue(frameChange.forceApply)
    }

    private func makeMonitor(displayId: CGDirectDisplayID, frame: CGRect) -> Monitor {
        Monitor(
            id: .init(displayId: displayId),
            displayId: displayId,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Display \(displayId)"
        )
    }

    private func makeController(left: Monitor, right: Monitor) -> WMController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OmniWMFloatingCrossDisplayMoveTests-\(UUID().uuidString)",
            isDirectory: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        settings.workspaces.configurations = [
            WorkspaceConfiguration(
                name: "1",
                monitorAssignment: .specificDisplay(OutputId(from: left)),
                layoutType: .dwindle
            ),
            WorkspaceConfiguration(
                name: "2",
                monitorAssignment: .specificDisplay(OutputId(from: right)),
                layoutType: .dwindle
            )
        ]
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.workspaceManager.applyMonitorConfigurationChange([left, right])
        controller.workspaceManager.applySettings()
        return controller
    }
}
