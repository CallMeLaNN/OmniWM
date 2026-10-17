// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class WorkspaceBarIconOverrideUITests: XCTestCase {
    func testSourcesStoreLocatorsAndRefreshResolver() {
        let cases: [(WorkspaceBarIconOverrideSource, String, String, String)] = [
            (.bundleResource("AppIconDark"), " com.cmuxterm.app ", "COM.CMUXTERM.APP", "bundle-resource:AppIconDark"),
            (.file("/tmp/custom.icns"), "  com.example.App \n", "COM.EXAMPLE.APP", "/tmp/custom.icns")
        ]
        for (source, bundleID, lookupID, expected) in cases {
            let settings = makeSettingsStore()
            var refreshes: [Bool] = []
            XCTAssertTrue(WorkspaceBarIconOverrideEdits.applySource(
                source, bundleID: bundleID, settings: settings, refresh: { refreshes.append($0) }
            ))
            XCTAssertEqual(settings.workspaceBar.iconOverrideValue(for: lookupID), expected)
            XCTAssertEqual(refreshes, [true])
        }
    }

    func testReselectingSamePathForcesReloadWithoutMutatingSettings() {
        let settings = makeSettingsStore()
        let selectedPath = "/tmp/custom.icns"
        XCTAssertTrue(
            settings.workspaceBar.setIconOverride(
                selectedPath,
                for: "com.example.App"
            )
        )
        let before = settings.workspaceBar.iconOverrides
        var refreshes: [Bool] = []

        XCTAssertFalse(
            WorkspaceBarIconOverrideEdits.applySource(
                .file(selectedPath),
                bundleID: "COM.EXAMPLE.APP",
                settings: settings,
                refresh: { refreshes.append($0) }
            )
        )

        XCTAssertEqual(settings.workspaceBar.iconOverrides, before)
        XCTAssertEqual(refreshes, [true])
    }

    func testBlankBundleIDDoesNotMutateOrRefresh() {
        let settings = makeSettingsStore()
        var refreshes: [Bool] = []
        XCTAssertFalse(
            WorkspaceBarIconOverrideEdits.applySource(
                .file("/tmp/custom.icns"), bundleID: " \n",
                settings: settings, refresh: { refreshes.append($0) }
            )
        )
        XCTAssertTrue(settings.workspaceBar.iconOverrides.isEmpty)
        XCTAssertTrue(refreshes.isEmpty)
    }

    func testRemoveRefreshesOnlyWhenOverrideExists() {
        let settings = makeSettingsStore()
        XCTAssertTrue(
            settings.workspaceBar.setIconOverride(
                "/tmp/custom.icns",
                for: "com.example.App"
            )
        )
        var refreshes: [Bool] = []

        XCTAssertTrue(
            WorkspaceBarIconOverrideEdits.remove(
                bundleID: "COM.EXAMPLE.APP",
                settings: settings,
                refresh: { refreshes.append($0) }
            )
        )
        XCTAssertFalse(
            WorkspaceBarIconOverrideEdits.remove(
                bundleID: "com.example.App",
                settings: settings,
                refresh: { refreshes.append($0) }
            )
        )

        XCTAssertTrue(settings.workspaceBar.iconOverrides.isEmpty)
        XCTAssertEqual(refreshes, [false])
    }

    private func makeSettingsStore() -> SettingsStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "OmniWMWorkspaceBarIconOverrideUITests-\(UUID().uuidString)",
                isDirectory: true
            )
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
