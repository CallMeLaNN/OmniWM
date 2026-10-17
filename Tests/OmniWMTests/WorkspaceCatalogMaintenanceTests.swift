// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceCatalogMaintenanceTests: XCTestCase {
    func testGarbageCollectionPreservesVisibleEmptyWorkspaceOnEachMonitor() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMWorkspaceCatalogMaintenance-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(directory: directory, startWatching: false, deferSaves: false),
            runtimeState: RuntimeStateStore(directory: directory.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
        let manager = WorkspaceManager(settings: settings)
        let monitors = (0 ... 1).map { index in
            let displayId = CGDirectDisplayID(91_080 + index)
            let frame = CGRect(x: index * 1600, y: 0, width: 1600, height: 900)
            return Monitor(
                id: .init(displayId: displayId), displayId: displayId, frame: frame, visibleFrame: frame,
                hasNotch: false, name: "Catalog Maintenance \(index)"
            )
        }
        manager.applyMonitorConfigurationChange(monitors)
        let first = try XCTUnwrap(manager.createDynamicWorkspace(named: "91", on: monitors[0].id))
        let second = try XCTUnwrap(manager.createDynamicWorkspace(named: "92", on: monitors[1].id))
        let unused = try XCTUnwrap(manager.createDynamicWorkspace(named: "93", on: monitors[0].id))
        let focused = try XCTUnwrap(manager.createDynamicWorkspace(named: "94", on: monitors[0].id))
        manager.assignWorkspaceToMonitor(first.id, monitorId: monitors[0].id)
        manager.assignWorkspaceToMonitor(second.id, monitorId: monitors[1].id)
        XCTAssertTrue(manager.setActiveWorkspace(first.id, on: monitors[0].id))
        XCTAssertTrue(manager.setActiveWorkspace(second.id, on: monitors[1].id))

        manager.garbageCollectUnusedWorkspaces(focusedWorkspaceId: focused.id)

        XCTAssertNotNil(manager.descriptor(for: first.id))
        XCTAssertNotNil(manager.descriptor(for: second.id))
        XCTAssertNotNil(manager.descriptor(for: focused.id))
        XCTAssertNil(manager.descriptor(for: unused.id))
        XCTAssertEqual(manager.activeWorkspace(on: monitors[0].id)?.id, first.id)
        XCTAssertEqual(manager.activeWorkspace(on: monitors[1].id)?.id, second.id)

        manager.garbageCollectUnusedWorkspaces(focusedWorkspaceId: nil)

        XCTAssertNotNil(manager.descriptor(for: first.id))
        XCTAssertNotNil(manager.descriptor(for: second.id))
        XCTAssertNil(manager.descriptor(for: focused.id))
    }
}
