// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class MotionPolicyTests: XCTestCase {
    func testSpeedObserversNormalizeWithoutReenteringForValidValues() {
        let policy = MotionPolicy(animationSpeed: 2)
        XCTAssertEqual(policy.snapshot().animationSpeed, 2)
        for (value, expected) in [(Double.nan, 1.0), (.infinity, 1), (0, 0.25), (10, 4), (2, 2)] {
            policy.animationSpeed = value
            XCTAssertEqual(policy.animationSpeed, expected)
            XCTAssertEqual(policy.snapshot().animationSpeed, expected)
        }
    }

    func testSystemReduceMotionMasksUserToggleWithoutOverwritingIt() {
        let policy = MotionPolicy(animationsEnabled: true)
        XCTAssertTrue(policy.animationsEnabled)

        policy.systemReducesMotion = true
        XCTAssertFalse(policy.animationsEnabled)
        XCTAssertTrue(policy.userAnimationsEnabled)
        XCTAssertEqual(policy.snapshot(), .disabled)

        policy.animationsEnabled = false
        XCTAssertFalse(policy.userAnimationsEnabled)
        policy.animationsEnabled = true
        XCTAssertTrue(policy.userAnimationsEnabled)
        XCTAssertFalse(policy.animationsEnabled)

        policy.systemReducesMotion = false
        XCTAssertTrue(policy.animationsEnabled)
        XCTAssertEqual(policy.snapshot(), .enabled)
    }

    func testControllerPersistsUserPreferenceUnderSystemReduceMotion() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMMotionPolicyTests-\(UUID().uuidString)", isDirectory: true)
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
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.motionPolicy.systemReducesMotion = true

        controller.setAnimationSpeed(2)
        XCTAssertEqual(settings.animationSpeed, 2)
        XCTAssertEqual(controller.motionPolicy.snapshot().animationSpeed, 2)
        XCTAssertFalse(controller.motionPolicy.snapshot().animationsEnabled)

        controller.setAnimationSpeed(10)
        XCTAssertEqual(settings.animationSpeed, 4)
        XCTAssertEqual(controller.motionPolicy.animationSpeed, 4)

        controller.setAnimationsEnabled(false)
        XCTAssertFalse(settings.animationsEnabled)
        XCTAssertFalse(controller.motionPolicy.userAnimationsEnabled)

        controller.setAnimationsEnabled(true)
        XCTAssertTrue(settings.animationsEnabled)
        XCTAssertTrue(controller.motionPolicy.userAnimationsEnabled)
        XCTAssertFalse(controller.motionPolicy.animationsEnabled)

        controller.motionPolicy.systemReducesMotion = false
        XCTAssertTrue(controller.motionPolicy.animationsEnabled)
        XCTAssertEqual(controller.motionPolicy.snapshot().animationSpeed, 4)
    }
}
