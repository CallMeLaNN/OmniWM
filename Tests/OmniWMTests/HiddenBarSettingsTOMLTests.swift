// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

final class HiddenBarSettingsTOMLTests: XCTestCase {
    func testRoundTripsAllHiddenBarFields() throws {
        let cases: [([String], Bool, Double)] = [(["com.example.a", "com.example.b"], false, 12), ([], true, 5)]
        for (bundleIDs, enabled, rehideInterval) in cases {
            var export = SettingsExport.defaults()
            export.hiddenBar.enabled = enabled
            export.hiddenBar.hiddenBundleIDs = bundleIDs
            export.hiddenBar.rehideIntervalSeconds = rehideInterval

            let decoded = try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(export))

            XCTAssertEqual(decoded.hiddenBar.enabled, enabled)
            XCTAssertEqual(decoded.hiddenBar.hiddenBundleIDs, bundleIDs)
            XCTAssertEqual(decoded.hiddenBar.rehideIntervalSeconds, rehideInterval)
        }
    }

    func testPopulatedBundleListSurvivesPreservingEncode() throws {
        var export = SettingsExport.defaults()
        export.hiddenBar.hiddenBundleIDs = ["com.keep.me"]
        var previousExport = export
        previousExport.hiddenBar.hiddenBundleIDs = ["com.old"]
        let previous = try SettingsTOMLCodec.encode(previousExport)

        let rewritten = String(
            decoding: try SettingsTOMLCodec.encode(export, preservingUnknownKeysFrom: previous),
            as: UTF8.self
        )
        XCTAssertTrue(rewritten.contains("com.keep.me"))
        XCTAssertFalse(rewritten.contains("com.old"))
        XCTAssertEqual(try SettingsTOMLCodec.decode(Data(rewritten.utf8)).hiddenBar.hiddenBundleIDs, ["com.keep.me"])
    }

    @MainActor
    func testApplyExportNormalizesRehideIntervalFromTOML() throws {
        let settings = makeSettingsStore()
        let cases = [
            (literal: "nan", expected: 5.0),
            (literal: "inf", expected: 5.0),
            (literal: "-inf", expected: 5.0),
            (literal: "1", expected: 2.0),
            (literal: "12", expected: 12.0),
            (literal: "31", expected: 30.0)
        ]

        for testCase in cases {
            let export = try SettingsTOMLCodec.decode(tomlWithRehideInterval(testCase.literal))
            settings.applyExport(export)

            XCTAssertEqual(
                settings.hiddenBar.rehideIntervalSeconds,
                testCase.expected,
                "TOML value: \(testCase.literal)"
            )
        }
    }

    @MainActor
    func testHiddenListEditsNormalizeAndReconcileOnlyAcceptedChanges() {
        let settings = makeSettingsStore()
        var reconciliations = 0

        HiddenBarSettingsEdits.setHidden(
            true,
            bundleID: "com.example.item",
            settings: settings
        ) {
            reconciliations += 1
        }
        XCTAssertEqual(settings.hiddenBar.hiddenBundleIDs, ["com.example.item"])
        XCTAssertEqual(reconciliations, 1)

        HiddenBarSettingsEdits.setHidden(
            true,
            bundleID: "com.apple.systemuiserver",
            settings: settings
        ) {
            reconciliations += 1
        }
        XCTAssertEqual(settings.hiddenBar.hiddenBundleIDs, ["com.example.item"])
        XCTAssertEqual(reconciliations, 1)
    }

    private func tomlWithRehideInterval(_ literal: String) throws -> Data {
        let toml = String(decoding: try SettingsTOMLCodec.encode(.defaults()), as: UTF8.self)
        let lines = toml.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard line.hasPrefix("rehideIntervalSeconds = ") else { return String(line) }
            return "rehideIntervalSeconds = \(literal)"
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMHiddenBarSettingsTests-\(UUID().uuidString)", isDirectory: true)
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
