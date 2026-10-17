// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class OverviewWorkspaceCreationTests: XCTestCase {
    func testCreationUsesNextLocalIDSkippingGlobalIDsWithoutChangingConfiguration() throws {
        let fixture = makeFixture(workspaceNames: ["2"], secondaryWorkspaceNames: ["3", "4"])
        let manager = fixture.controller.workspaceManager
        let configurations = fixture.controller.settings.workspaces.configurations
        let visible = manager.activeVisibleWorkspaceMap()

        let first = try XCTUnwrap(
            fixture.controller.workspaceNavigationHandler.createOverviewWorkspace(on: fixture.monitors[0].id)
        )
        let second = try XCTUnwrap(
            fixture.controller.workspaceNavigationHandler.createOverviewWorkspace(on: fixture.monitors[1].id)
        )

        XCTAssertEqual(first.name, "5")
        XCTAssertEqual(second.name, "6")
        XCTAssertEqual(manager.monitorId(for: first.id), fixture.monitors[0].id)
        XCTAssertEqual(manager.monitorId(for: second.id), fixture.monitors[1].id)
        XCTAssertEqual(fixture.controller.settings.workspaces.configurations, configurations)
        XCTAssertEqual(manager.activeVisibleWorkspaceMap(), visible)
        XCTAssertEqual(
            fixture.controller.niriEngine?.monitor(for: fixture.monitors[0].id)?.containsWorkspace(first.id), true
        )
        XCTAssertEqual(
            fixture.controller.niriEngine?.monitor(for: fixture.monitors[1].id)?.containsWorkspace(second.id), true
        )
    }

    func testEmptyMonitorStartsAtOneAndSkipsGlobalIDs() throws {
        let fixture = makeFixture(workspaceNames: ["1", "2", "7"])

        let created = try XCTUnwrap(
            fixture.controller.workspaceNavigationHandler.createOverviewWorkspace(on: fixture.monitors[1].id)
        )

        XCTAssertEqual(created.name, "3")
        XCTAssertEqual(fixture.controller.workspaceManager.monitorId(for: created.id), fixture.monitors[1].id)
    }

    func testCreationStartsAtOneWithEmptyCatalog() throws {
        let fixture = makeFixture(workspaceNames: ["7"])
        let manager = fixture.controller.workspaceManager
        manager.removeWorkspaces(manager.workspaces.map(\.id))
        XCTAssertTrue(manager.workspaces.isEmpty)

        let created = try XCTUnwrap(
            fixture.controller.workspaceNavigationHandler.createOverviewWorkspace(on: fixture.monitors[1].id)
        )

        XCTAssertEqual(created.name, "1")
        XCTAssertEqual(manager.monitorId(for: created.id), fixture.monitors[1].id)
        XCTAssertEqual(fixture.controller.settings.workspaces.configurations.map(\.name), ["7"])
    }

    func testCreationRejectsMissingMonitorAndExhaustedNumericIDs() {
        let fixture = makeFixture(workspaceNames: [String(Int.max)])
        let before = fixture.controller.workspaceManager.workspaces

        XCTAssertNil(fixture.controller.workspaceNavigationHandler.createOverviewWorkspace(on: .init(displayId: 99)))
        XCTAssertNil(
            fixture.controller.workspaceNavigationHandler.createOverviewWorkspace(on: fixture.monitors[0].id)
        )
        XCTAssertEqual(fixture.controller.workspaceManager.workspaces, before)
    }

    private func makeFixture(
        workspaceNames: [String], secondaryWorkspaceNames: [String] = []
    ) -> (controller: WMController, monitors: [Monitor]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMOverviewWorkspaceCreation-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(directory: directory, startWatching: false, deferSaves: false),
            runtimeState: RuntimeStateStore(directory: directory.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
        settings.animationsEnabled = false
        let monitors = (0 ... 1).map { index in
            let displayId = CGDirectDisplayID(91_090 + index)
            let frame = CGRect(x: index * 1600, y: 0, width: 1600, height: 900)
            return Monitor(
                id: .init(displayId: displayId), displayId: displayId, frame: frame, visibleFrame: frame,
                hasNotch: false, name: "Overview Creation \(index)"
            )
        }
        settings.workspaces.configurations = workspaceNames.map {
            WorkspaceConfiguration(name: $0, monitorAssignment: .main, layoutType: .niri)
        } + secondaryWorkspaceNames.map {
            WorkspaceConfiguration(
                name: $0, monitorAssignment: .specificDisplay(OutputId(from: monitors[1])), layoutType: .niri
            )
        }
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in }, focusSpecificWindow: { _, _, _ in }, raiseWindow: { _ in }
            )
        )
        controller.workspaceManager.applyMonitorConfigurationChange(monitors)
        controller.workspaceManager.applySettings()
        controller.niriEngine = NiriLayoutEngine()
        controller.syncMonitorsToNiriEngine()
        return (controller, monitors)
    }
}
