// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon
@testable import OmniWM
import XCTest

@MainActor
final class KeyboardModeIndicatorTests: XCTestCase {
    private func isApplied(_ result: HotkeyCaptureResult) -> Bool {
        if case .applied = result { return true }
        return false
    }

    func testBorderIndicatorReplacesColourGradientAndGlowColour() throws {
        let base = BorderConfig(
            enabled: true,
            color: SettingsColor(red: 0, green: 0, blue: 1, alpha: 1),
            gradient: .default,
            glow: BorderGlow(
                enabled: true,
                radius: 8,
                opacity: 0.6,
                color: SettingsColor(red: 1, green: 0, blue: 0, alpha: 1)
            )
        )
        XCTAssertEqual(base.indicating(.normal), base)

        for kind in [KeyboardModeKind.paused, .prefix, .window] {
            let color = try XCTUnwrap(BorderConfig.keyboardModeColor(kind))
            let indicated = base.indicating(kind)
            XCTAssertEqual(indicated.color, color)
            XCTAssertNil(indicated.gradient)
            XCTAssertEqual(indicated.glow?.color, color)
            XCTAssertEqual(indicated.width, base.width)
        }
        XCTAssertNotEqual(BorderConfig.keyboardModeColor(.paused), BorderConfig.keyboardModeColor(.prefix))
        XCTAssertEqual(BorderConfig.keyboardModeColor(.prefix), BorderConfig.keyboardModeColor(.window))
    }

    func testControllerBorderFollowsTheKeyboardMode() {
        let controller = WindowAdmissionTestSupport.controller(prefix: "KeyboardModeBorder")
        let settingsColor = WorldView(controller: controller).borderConfig.color

        controller.keyboardModeDidChange(.paused)
        XCTAssertEqual(WorldView(controller: controller).borderConfig.color, BorderConfig.keyboardModeColor(.paused))

        controller.keyboardModeDidChange(.normal)
        XCTAssertEqual(WorldView(controller: controller).borderConfig.color, settingsColor)
    }

    func testStatusTitleNamesTheKeyboardMode() {
        XCTAssertNil(StatusBarController.keyboardModeTitle(.normal))
        XCTAssertEqual(
            StatusBarController.statusButtonTitle(workspaceLabel: "2", focusedAppName: "Safari", modeTitle: "Paused"),
            " Paused · 2 \u{2013} Safari"
        )
        XCTAssertEqual(StatusBarController.statusButtonTitle(workspaceLabel: "2", focusedAppName: nil), " 2")
    }

    func testPauseTimeoutPickerOffersOnlyValidDurations() {
        let defaults: [Double] = [60, 300, 900, 1800, 3600]
        for seconds in [nil, 0, -5, 1e100, .infinity, .nan] as [Double?] {
            XCTAssertNil(HotkeySettingsView.pauseTimeoutSelection(seconds))
            XCTAssertEqual(HotkeySettingsView.pauseTimeoutChoices(including: seconds), defaults)
        }
        XCTAssertEqual(HotkeySettingsView.pauseTimeoutSelection(90), 90)
        XCTAssertEqual(HotkeySettingsView.pauseTimeoutChoices(including: 90), [60, 90, 300, 900, 1800, 3600])
        XCTAssertEqual(HotkeySettingsView.pauseTimeoutChoices(including: 300), defaults)
    }

    func testModeKeyCaptureAcceptsOnlyFreeSingleKeys() throws {
        let settings = WindowAdmissionTestSupport.controller(prefix: "KeyboardModeCapture").settings
        let keyH = KeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: 0)
        let shiftK = KeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(shiftKey))
        settings.updateTrigger(for: "focus.up", newTrigger: .chord(shiftK))

        XCTAssertTrue(isApplied(HotkeyBindingEditor.captureModeKey(
            .chord(keyH),
            for: "focus.left",
            settings: settings
        )))
        XCTAssertEqual(settings.hotkeyBindings.first { $0.id == "focus.left" }?.modeKey, keyH)

        let rejected: [HotkeyTrigger] = [
            .chord(keyH),
            .chord(shiftK),
            .chord(KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey))),
            .mouseButton(try XCTUnwrap(MouseButtonBinding(button: 4, modifiers: 0)))
        ]
        for trigger in rejected {
            XCTAssertFalse(isApplied(HotkeyBindingEditor.captureModeKey(
                trigger,
                for: "focus.right",
                settings: settings
            )))
        }
        XCTAssertNil(settings.hotkeyBindings.first { $0.id == "focus.right" }?.modeKey)
    }

    func testBordersAndBarsScopeSitsBetweenBorderAndFullScene() {
        let controller = WindowAdmissionTestSupport.controller(prefix: "KeyboardModeScope")
        let reconciler = SurfaceReconciler(controller: controller)
        defer { reconciler.reconcileNow() }

        reconciler.noteBorderChanged()
        XCTAssertEqual(reconciler.pendingReconcileScope, .borderOnly)
        reconciler.noteBordersAndBarsChanged()
        reconciler.noteBorderChanged()
        XCTAssertEqual(reconciler.pendingReconcileScope, .bordersAndBars)
        reconciler.noteWorldChanged()
        reconciler.noteBordersAndBarsChanged()
        XCTAssertEqual(reconciler.pendingReconcileScope, .fullScene)
    }

    func testBarStyleCarriesTheKeyboardMode() {
        let settings = WindowAdmissionTestSupport.controller(prefix: "KeyboardModeBarStyle").settings.workspaceBar
        let monitor = Monitor(
            id: .init(displayId: 1),
            displayId: 1,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            hasNotch: false,
            name: "M1"
        )
        let resolved = settings.resolved(for: monitor)
        for kind in [KeyboardModeKind.normal, .paused, .prefix, .window] {
            let snapshot = WorkspaceBarSnapshot(
                projection: .init(items: [], scratchpads: []),
                backgroundOpacity: 1,
                barHeight: 28,
                keyboardMode: kind
            )
            XCTAssertEqual(ShellBarStyle(resolved, settings: settings, snapshot: snapshot).keyboardMode, kind.rawValue)
            XCTAssertEqual(snapshot.replacingShellWidgets([]).keyboardMode, kind)
        }
    }
}
