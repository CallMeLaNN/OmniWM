// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import ApplicationServices
@testable import OmniWM
import XCTest

@MainActor
final class AXFullscreenButtonStateTests: XCTestCase {
    private func decision(
        result: AXError,
        value: CFTypeRef?,
        engine: WindowRuleEngine
    ) -> WindowDecision {
        let button = AXUIElementCreateApplication(72_037)
        let state = AXWindowService.fullscreenButtonEnabledState(result: result, value: value)
        let facts = AXWindowService.makeWindowFacts(
            AXWindowFactAttributeValues(
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String,
                title: "Fullscreen button evidence",
                closeButton: button,
                fullscreenButton: button,
                fullscreenButtonEnabled: state.enabled,
                zoomButton: button,
                minimizeButton: button
            ),
            appPolicy: .regular,
            bundleId: "org.example.fullscreen-evidence",
            attributeFetchSucceeded: state.succeeded
        )
        return engine.decision(
            for: WindowRuleFacts(appName: "Example", ax: facts, sizeConstraints: nil, windowServer: nil),
            token: nil,
            appFullscreen: false
        )
    }

    func testEnabledAttributeEvidenceControlsAdmissionAndRecovery() {
        let cases: [(String, AXError, CFTypeRef?, Bool, Bool)] = [
            ("disabled", .success, kCFBooleanFalse, true, false),
            ("cannotComplete", .cannotComplete, nil, false, true),
            ("invalidUIElement", .invalidUIElement, nil, false, true),
            ("failure", .failure, nil, false, true),
            ("malformedNull", .success, kCFNull, false, false),
            ("malformedString", .success, "not a boolean" as CFString, false, false),
            ("unavailableSuccess", .success, nil, true, false),
            ("noValue", .noValue, nil, true, false),
            ("unsupported", .attributeUnsupported, nil, true, false)
        ]
        for (label, error, value, floating, recovers) in cases {
            let engine = WindowRuleEngine()
            let result = decision(result: error, value: value, engine: engine)
            if floating {
                XCTAssertEqual(result.disposition, .floating, label)
                XCTAssertEqual(result.heuristicReasons, [.disabledFullscreenButton], label)
                XCTAssertNil(result.deferredReason, label)
            } else {
                XCTAssertEqual(result.disposition, .undecided, label)
                XCTAssertEqual(result.deferredReason, .attributeFetchFailed, label)
                XCTAssertEqual(result.admissionOutcome, .deferred, label)
                XCTAssertFalse(result.tracksWindow, label)
            }
            if recovers {
                let recovered = decision(result: .success, value: kCFBooleanTrue, engine: engine)
                XCTAssertEqual(recovered.disposition, .managed, label)
                XCTAssertNil(recovered.deferredReason, label)
            }
        }
    }

    func testFailedEnabledReadCannotBeAdmittedByRulesOrManualOverrides() {
        let engine = WindowRuleEngine()
        engine.rebuild(rules: [AppRule(bundleId: "org.example.fullscreen-evidence", layout: .tile)])
        let failed = decision(result: .cannotComplete, value: kCFBooleanTrue, engine: engine)

        XCTAssertEqual(failed.disposition, .undecided)
        XCTAssertEqual(failed.deferredReason, .attributeFetchFailed)
        for override in [ManualWindowOverride.forceTile, .forceFloat] {
            XCTAssertEqual(WindowRuleEngine.applyingManualOverride(failed, manualOverride: override), failed)
        }
    }

    func testExplicitTileRuleStillOverridesLegitimateDisabledButton() {
        let engine = WindowRuleEngine()
        let rule = AppRule(bundleId: "org.example.fullscreen-evidence", layout: .tile)
        engine.rebuild(rules: [rule])
        let disabled = decision(result: .success, value: kCFBooleanFalse, engine: engine)

        XCTAssertEqual(disabled.disposition, .managed)
        XCTAssertEqual(disabled.source, .userRule(rule.id))
        XCTAssertNil(disabled.deferredReason)
    }
}
