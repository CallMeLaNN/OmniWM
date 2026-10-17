// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import OmniWMIPC
import XCTest

final class SystemStatsCommandTests: XCTestCase {
    func testToggleSystemStatsSpecRegistered() throws {
        let spec = try XCTUnwrap(ActionCatalog.spec(for: .presentation(.systemStats)))

        XCTAssertEqual(spec.id, "toggleSystemStats")
        XCTAssertEqual(spec.title, "Toggle System Stats")
        XCTAssertEqual(spec.layoutCompatibility, .shared)
        XCTAssertEqual(spec.defaultBinding, .unassigned)
        XCTAssertEqual(spec.ipcCommandName, .presentation(.systemStats))
        XCTAssertNotNil(spec.ipcDescriptor)
    }

    func testToggleSystemStatsManifestResolves() throws {
        let descriptors = IPCAutomationManifest.commandDescriptors(matching: ["toggle-system-stats"])
        let descriptor = try XCTUnwrap(descriptors.first { $0.name == .presentation(.systemStats) })

        XCTAssertEqual(descriptor.commandWords, ["toggle-system-stats"])
        XCTAssertEqual(try IPCCommandRequest(name: descriptor.name, argumentValues: []), .presentation(.systemStats))
    }

    @MainActor
    func testRouterExecutesToggleSystemStats() {
        let controller = WMController(settings: makeSettingsStore())
        addTeardownBlock { @MainActor in
            controller.hasStartedServices = false
            controller.workspaceBarManager.cleanup()
            controller.layoutRefreshController.resetState()
            controller.mouseEventHandler.cleanup()
            controller.surfaceReconciler.cleanup()
            controller.axManager.cleanup()
            await controller.workspaceBarManager.flushShellForQuit()
        }
        let router = IPCCommandRouter(controller: controller, sessionToken: "test")

        XCTAssertEqual(router.handle(.presentation(.systemStats)), .executed)
    }

    func testSystemStatsButtonSettingRoundTrips() throws {
        XCTAssertFalse(SettingsExport.defaults().workspaceBar.systemStatsButton)

        var export = SettingsExport.defaults()
        export.workspaceBar.systemStatsButton = true
        let data = try SettingsTOMLCodec.encode(export)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("systemStatsButton = true"))
        XCTAssertTrue(try SettingsTOMLCodec.decode(data).workspaceBar.systemStatsButton)
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMSystemStatsTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { @MainActor in
            try FileManager.default.removeItem(at: root)
        }
        return SettingsStore(
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
    }
}
