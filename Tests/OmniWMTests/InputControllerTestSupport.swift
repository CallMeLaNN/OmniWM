// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
enum InputControllerTestSupport {
    static func controller(for testCase: XCTestCase) -> WMController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(directory: directory, startWatching: false, deferSaves: false),
            runtimeState: RuntimeStateStore(directory: directory.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
        settings.animationsEnabled = false
        let controller = WMController(settings: settings)
        testCase.addTeardownBlock { @MainActor in
            controller.hotkeys.stop()
            controller.mouseEventHandler.cleanup()
            controller.layoutRefreshController.resetState()
            try FileManager.default.removeItem(at: directory)
        }
        return controller
    }
}
