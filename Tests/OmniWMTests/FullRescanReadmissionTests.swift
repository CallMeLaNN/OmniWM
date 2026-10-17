// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class FullRescanReadmissionTests: XCTestCase {
    func testTrackedWindowReadmissionStateMatrix() throws {
        let manager = makeManager()
        let workspaceId = try XCTUnwrap(manager.workspaceId(for: "1", createIfMissing: true))
        let otherWorkspaceId = try XCTUnwrap(manager.workspaceId(for: "2", createIfMissing: true))
        let token = manager.addWindow(axRef(9002, 2), pid: 9002, windowId: 2, to: workspaceId)
        let entry = try XCTUnwrap(manager.entry(for: token))

        let cases: [(
            label: String,
            workspace: WorkspaceDescriptor.ID,
            mode: TrackedWindowMode,
            preserve: Bool,
            fullscreen: Bool,
            expected: Bool
        )] = [
            ("unchanged", workspaceId, .tiling, false, false, false),
            ("workspace", otherWorkspaceId, .tiling, false, false, true),
            ("mode", workspaceId, .floating, false, false, true),
            ("pre-fullscreen", workspaceId, .tiling, true, false, true),
            ("app-fullscreen", workspaceId, .tiling, false, true, true)
        ]
        for row in cases {
            XCTAssertEqual(
                LayoutRefreshController.shouldReadmitTrackedWindow(
                    entry: entry,
                    target: .init(workspaceId: row.workspace, mode: row.mode, ruleEffects: entry.ruleEffects),
                    shouldPreservePreFullscreenState: row.preserve,
                    appFullscreen: row.fullscreen
                ),
                row.expected,
                row.label
            )
        }
    }

    private func makeManager() -> WorkspaceManager {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMFullRescanTests-\(UUID().uuidString)", isDirectory: true)
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
        return WorkspaceManager(settings: settings)
    }

    private func axRef(_ pid: pid_t, _ windowId: Int) -> AXWindowRef {
        AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId)
    }
}
