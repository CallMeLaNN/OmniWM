// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import Synchronization
import XCTest

@MainActor
final class ShellConfigurationCoordinatorTests: XCTestCase {
    func testNativeIslandEditsPersistWithoutEnablingAnyShellSurface() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shell = directory.appendingPathComponent("shell")
        _ = ShellDefaults.sync(into: shell)
        _ = try ShellProfiles.select("lake", in: shell)
        let coordinator = ShellConfigurationCoordinator(shellDirectory: shell)
        try await coordinator.refresh()
        let initial = try XCTUnwrap(coordinator.config.island).components
        let addedID = try await coordinator.island(.add(
            widget: "world-clock", options: ["label": .string("Toronto"), "zone": .string("America/Toronto")]
        ))
        let added = try XCTUnwrap(addedID)
        try await coordinator.island(.move(id: added, index: 1))
        try await coordinator.island(.enable(id: added, value: false))
        try await coordinator.island(.set(id: added, key: "seconds", value: .bool(true)))
        try await coordinator.island(.rootSetting(key: "width", value: .number(540)))
        let persisted = try load(shell)
        let components = try XCTUnwrap(persisted.island).components
        XCTAssertEqual(components.first?.id, added)
        XCTAssertEqual(Array(components.dropFirst()), initial)
        XCTAssertFalse(components[0].enabled)
        XCTAssertFalse(components[0].provider)
        XCTAssertNil(components[0].capabilities)
        XCTAssertEqual(components[0].options["seconds"], .bool(true))
        XCTAssertEqual(
            try ShellServiceValue.decode(try XCTUnwrap(persisted.widgetSettings["lake"])).fields?["width"]?.number,
            540
        )
        try await coordinator.island(.remove(id: added))
        XCTAssertEqual(coordinator.config.island?.components, initial)
        XCTAssertFalse(coordinator.isSaving)
        await coordinator.flush()
    }

    func testPreviewingSystemKeepsLakeSelectedAndSupportsItsSimpleIsland() async throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        _ = ShellDefaults.sync(into: shell)
        _ = try ShellProfiles.select("lake", in: shell)
        let coordinator = ShellConfigurationCoordinator(shellDirectory: shell)
        try await coordinator.refresh()
        let before = try Data(contentsOf: shell.appendingPathComponent("shell.toml"))
        let system = try await coordinator.previewConfig(profile: "system")
        XCTAssertEqual(system.profile, "system")
        XCTAssertEqual(system.island?.root, "focus-ribbon")
        XCTAssertEqual(coordinator.config.profile, "lake")
        XCTAssertEqual(try Data(contentsOf: shell.appendingPathComponent("shell.toml")), before)
        try await coordinator.selectProfile("system")
        try await coordinator.set("main", key: "displays", table: "island")
        XCTAssertEqual(coordinator.config.island?.root, "focus-ribbon")
        XCTAssertEqual(coordinator.config.island?.displays, .main)
        XCTAssertNil(coordinator.catalog?.settings)
        let lake = try await coordinator.previewConfig(profile: "lake")
        XCTAssertEqual(lake.island?.root, "lake")
    }

    func testFailedPersistenceDoesNotPublishOrModifyTheEffectiveIsland() async throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        _ = ShellDefaults.sync(into: shell)
        _ = try ShellProfiles.select("lake", in: shell)
        let coordinator = ShellConfigurationCoordinator(shellDirectory: shell)
        try await coordinator.refresh()
        let initial = coordinator.config
        var publications = 0
        coordinator.onSave = { _ in publications += 1 }
        let attempts = Mutex(0)
        coordinator.writer = ShellIslandConfigWriter(shellDirectory: shell, writeFile: { data, url in
            XCTAssertFalse(Thread.isMainThread)
            let fail = attempts.withLock { value in value += 1
                return value == 1
            }
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try SettingsFileAccess.writeAtomically(data, at: url)
        }, reloadReady: {})
        do {
            _ = try await coordinator.island(.add(widget: "world-clock", options: [:]))
            XCTFail("The first persistence attempt must fail")
        } catch {}
        XCTAssertEqual(coordinator.config, initial)
        XCTAssertEqual(try load(shell), initial)
        XCTAssertEqual(publications, 0)
        _ = try await coordinator.island(.add(widget: "world-clock", options: [:]))
        XCTAssertEqual(coordinator.config.island?.components.count, (initial.island?.components.count ?? 0) + 1)
        XCTAssertEqual(publications, 1)
        XCTAssertFalse(coordinator.isSaving)
    }

    func testQueuedProfileAndIslandEditsPublishOnlyAfterTheirOrderedWrites() async throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        _ = ShellDefaults.sync(into: shell)
        _ = try ShellProfiles.select("lake", in: shell)
        let coordinator = ShellConfigurationCoordinator(shellDirectory: shell)
        try await coordinator.refresh()
        let entered = expectation(description: "island write started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        coordinator.writer = ShellIslandConfigWriter(shellDirectory: shell, writeFile: { data, url in
            entered.fulfill()
            release.wait()
            try SettingsFileAccess.writeAtomically(data, at: url)
        }, reloadReady: {})
        let initialCount = coordinator.config.island?.components.count
        let island = Task { try await coordinator.island(.add(widget: "world-clock", options: [:])) }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertTrue(coordinator.isSaving)
        XCTAssertEqual(coordinator.config.island?.components.count, initialCount)
        let switched = Task { try await coordinator.selectProfile("system") }
        release.signal()
        _ = try await island.value
        _ = try await switched.value
        XCTAssertEqual(coordinator.config.profile, "system")
        let lake = try await coordinator.previewConfig(profile: "lake")
        XCTAssertEqual(lake.island?.components.count, (initialCount ?? 0) + 1)
        await coordinator.flush()
        XCTAssertFalse(coordinator.isSaving)
    }

    func testWidgetSchemaFollowsTheEffectiveSourceFolder() async throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        let own = shell.appendingPathComponent("widgets/clock")
        let inherited = shell.appendingPathComponent("default/widgets/clock")
        for folder in [own, inherited] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("function render(ctx) return ui.box{} end".utf8)
                .write(to: folder.appendingPathComponent("init.luau"))
        }
        try Data("[options.date]\ntype = 'boolean'\ndefault = true\n".utf8)
            .write(to: inherited.appendingPathComponent("settings.toml"))
        let loader = ShellConfigurationCatalogLoader()
        let directories = [shell, shell.appendingPathComponent("default")]
        let overridden = try await loader.settings(widgets: ["clock"], directories: directories)
        XCTAssertNil(overridden["clock"])
        try FileManager.default.removeItem(at: own.appendingPathComponent("init.luau"))
        let resolved = try await loader.settings(widgets: ["clock"], directories: directories)
        XCTAssertEqual(resolved["clock"]?.options["date"]?.defaultValue, .bool(true))
    }

    func testDeferredExternalReloadSurvivesNoChangeAndFailedPersistence() async throws {
        for fail in [false, true] {
            let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: shell) }
            _ = ShellDefaults.sync(into: shell)
            _ = try ShellProfiles.select("lake", in: shell)
            let coordinator = ShellConfigurationCoordinator(shellDirectory: shell)
            try await coordinator.refresh()
            let entered = expectation(description: "persistence operation entered")
            let observed = expectation(description: "deferred external edit published")
            observed.assertForOverFulfill = true
            let release = DispatchSemaphore(value: 0)
            defer { release.signal() }
            var publications = 0
            coordinator.onSave = { config in
                XCTAssertEqual(config.barOverride?.settings.height, 48)
                publications += 1
                observed.fulfill()
            }
            let operation = Task {
                try await coordinator.editFile { _ in
                    XCTAssertFalse(Thread.isMainThread)
                    entered.fulfill()
                    release.wait()
                    if fail { throw CocoaError(.fileWriteNoPermission) }
                    return false
                }
            }
            await fulfillment(of: [entered], timeout: 5)
            _ = try ShellProfiles.setValue(
                48,
                at: ShellProfiles.key("workspaceBar", of: "lake") + ["height"],
                in: shell
            )
            XCTAssertTrue(try XCTUnwrap(coordinator.writer).deferReloadIfWriting())
            release.signal()
            do {
                let changed = try await operation.value
                XCTAssertFalse(fail)
                XCTAssertFalse(changed)
            } catch {
                XCTAssertTrue(fail)
                XCTAssertEqual((error as? CocoaError)?.code, .fileWriteNoPermission)
            }
            await coordinator.flush()
            XCTAssertEqual(coordinator.config.barOverride?.settings.height, 48)
            XCTAssertFalse(coordinator.isSaving)
            XCTAssertEqual(publications, 1)
            await fulfillment(of: [observed], timeout: 5)
        }
    }

    func testScalarEditsReuseMetadataUntilAnExplicitSourceRefresh() async throws {
        let shell = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: shell) }
        _ = ShellDefaults.sync(into: shell)
        _ = try ShellProfiles.select("lake", in: shell)
        let coordinator = ShellConfigurationCoordinator(shellDirectory: shell)
        try await coordinator.refresh()
        let clock = try XCTUnwrap(coordinator.widgetSchemas["clock"])
        let catalog = try XCTUnwrap(coordinator.catalog)
        let root = try XCTUnwrap(catalog.settings)
        let component = try XCTUnwrap(catalog.descriptors["world-clock"])
        try Data("[options.date]\ntype = 'number'\ndefault = 5\n".utf8)
            .write(to: clock.folder.appendingPathComponent("settings.toml"))
        try Data("[options.width]\ntype = 'number'\ndefault = 100\nmin = 0\nmax = 200\nstep = 20\n".utf8)
            .write(to: root.folder.appendingPathComponent("settings.toml"))
        try Data("views = []\n".utf8).write(to: component.folder.appendingPathComponent("component.toml"))

        try await coordinator.set(44, key: "height")
        try await coordinator.setWidgetValue(.bool(false), widget: "clock", key: "date")
        try await coordinator.island(.rootSetting(key: "width", value: .number(540)))
        XCTAssertEqual(coordinator.widgetSchemas["clock"], clock)
        XCTAssertEqual(coordinator.catalog, catalog)
        XCTAssertNil(coordinator.metadataError)

        coordinator.invalidatePreviews()
        try await coordinator.refresh()
        XCTAssertEqual(coordinator.widgetSchemas["clock"]?.options["date"]?.kind, .number)
        XCTAssertEqual(coordinator.catalog?.settings?.options["width"]?.maximum, 200)
        XCTAssertNil(coordinator.catalog?.descriptors["world-clock"])
        XCTAssertNotNil(coordinator.catalog?.entries.first { $0.widget == "world-clock" }?.error)
        let saved = try Data(contentsOf: shell.appendingPathComponent("shell.toml"))
        do {
            try await coordinator.setWidgetValue(.bool(true), widget: "clock", key: "date")
            XCTFail("The refreshed number option must reject a boolean")
        } catch {}
        do {
            try await coordinator.island(.rootSetting(key: "width", value: .number(540)))
            XCTFail("The refreshed maximum must reject 540")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: shell.appendingPathComponent("shell.toml")), saved)
    }

    private func load(_ shell: URL) throws -> ShellConfig {
        var problems: [String] = []
        return try XCTUnwrap(ShellConfig.load(shellDirectory: shell, problems: &problems), "\(problems)")
    }
}
