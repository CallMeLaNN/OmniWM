// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import Observation
import TOML

@MainActor
@Observable
final class ShellConfigurationCoordinator {
    private struct MetadataScope: Equatable {
        let directories: [URL]
        let root: String?

        init(_ config: ShellConfig) {
            directories = config.directories
            root = config.island?.root
        }
    }

    struct IslandCommit: Sendable {
        let instanceID: String?
        let revision: UInt64
    }

    let shellDirectory: URL
    private(set) var config = ShellConfig()
    private(set) var catalog: ShellConfigurationCatalog?
    private(set) var widgetSchemas: [String: ShellRootSettings] = [:]
    private(set) var profiles: [String] = []
    private(set) var themes: [String] = []
    private(set) var revision: UInt64 = 0
    private(set) var metadataError: String?
    private var pendingCount = 0
    var isSaving: Bool {
        pendingCount > 0
    }

    @ObservationIgnored var writer: ShellIslandConfigWriter?
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private let catalogLoader = ShellConfigurationCatalogLoader()
    @ObservationIgnored private let sourceLoader = ShellWidgetSourceLoader()
    @ObservationIgnored private var defaultsInstalled = false
    @ObservationIgnored private var metadataScope: MetadataScope?
    @ObservationIgnored private let onDefaultsUpdated: @MainActor ([URL]) -> Void
    @ObservationIgnored var onSave: (@MainActor (ShellConfig) -> Void)?

    init(
        shellDirectory: URL,
        onDefaultsUpdated: @escaping @MainActor ([URL]) -> Void = { _ in },
        onSave: (@MainActor (ShellConfig) -> Void)? = nil
    ) {
        self.shellDirectory = shellDirectory
        self.onDefaultsUpdated = onDefaultsUpdated
        self.onSave = onSave
    }

    func adopt(_ config: ShellConfig) {
        self.config = config
        revision += 1
    }

    func invalidatePreviews() {
        metadataScope = nil
        revision += 1
    }

    func refresh() async throws {
        try await ordered { [self] in
            if !defaultsInstalled {
                let backups = try await persistence().perform { ShellDefaults.sync(into: $0) }
                if !backups.isEmpty { onDefaultsUpdated(backups) }
                defaultsInstalled = true
            }
            try await reload(refreshMetadata: true)
            onSave?(config)
        }
    }

    func previewConfig(profile: String) async throws -> ShellConfig {
        guard ShellProfiles.names(in: shellDirectory).contains(profile) else { throw CocoaError(.fileNoSuchFile) }
        var problems: [String] = []
        guard let value = ShellConfig.load(profile: profile, shellDirectory: shellDirectory, problems: &problems)
        else { throw ShellBarLayout.Unreadable(problem: problems.last ?? "shell.toml") }
        return value
    }

    @discardableResult
    func selectProfile(_ name: String) async throws -> Bool {
        try await editFile { try ShellProfiles.select(name, in: $0) }
    }

    @discardableResult
    func selectTheme(_ name: String) async throws -> Bool {
        try await editFile(refreshMetadata: false) { try ShellProfiles.selectTheme(name, in: $0) }
    }

    @discardableResult
    func selectScheme(_ scheme: ShellWallpaperScheme) async throws -> Bool {
        try await editFile(refreshMetadata: false) { try ShellProfiles.selectScheme(scheme, in: $0) }
    }

    func set<Value: Encodable>(
        _ value: Value?, key: String, table: String = "workspaceBar", profile: String? = nil
    ) async throws {
        let node = try value.map { try ShellTOMLText.node($0) }
        let path = table.split(separator: ".").map(String.init) + [key]
        try await setNode(node, path: path, profile: profile)
    }

    func reset(table: String = "workspaceBar", profile: String? = nil) async throws {
        try await setNode(nil, path: table.split(separator: ".").map(String.init), profile: profile)
    }

    func setWidgetValue(
        _ value: ShellComponentValue?, widget: String, key: String, profile: String? = nil
    ) async throws {
        let profile = try load(profile: profile).profile
        try await ordered { [self] in
            let snapshot = try load(profile: profile)
            let schema = if metadataScope == MetadataScope(snapshot) {
                widgetSchemas[widget]
            } else {
                try await catalogLoader.settings(widgets: [widget], directories: snapshot.directories)[widget]
            }
            guard let schema,
                  let option = schema.options[key], value.map(option.accepts) != false
            else { throw ShellComponentCatalog.Failure("Invalid setting \(key) for \(widget)") }
            let name = snapshot.profile
            _ = try await persistence().perform { directory in
                try ShellProfiles.setNodes(
                    [(ShellProfiles.key("widgets", of: name) + [widget, key], value?.node)],
                    in: directory
                )
            }
            try await saved()
        }
    }

    func setWidgetOptions<Value: Encodable>(
        _ value: Value?, widget: String, key: String, profile: String? = nil
    ) async throws {
        guard ShellComponentCatalog.validName(widget), ShellComponentCatalog.validName(key) else {
            throw ShellTOMLText.Failure.invalidValue(key)
        }
        try await setNode(
            try value.map { try ShellTOMLText.node($0) },
            path: ["widgets", widget, key],
            profile: profile
        )
    }

    func setWeather<Value: Encodable>(_ value: Value?) async throws {
        let node = try value.map { try ShellTOMLText.node($0) }
        _ = try await editFile(refreshMetadata: false) { directory in
            try ShellProfiles.setNodes([(["weather"], node)], in: directory)
        }
    }

    @discardableResult
    func island(_ operation: ShellIslandLayout.Operation, profile: String? = nil) async throws -> String? {
        try await islandCommit(operation, profile: try load(profile: profile).profile).instanceID
    }

    func islandCommit(
        _ operation: ShellIslandLayout.Operation,
        profile: String? = nil,
        validate: @escaping @MainActor (ShellConfig) throws -> Void = { _ in }
    ) async throws -> IslandCommit {
        try await ordered { [self] in
            let snapshot = try load(profile: profile)
            try validate(snapshot)
            guard let island = snapshot.island else {
                throw ShellComponentCatalog.Failure("This profile has no island")
            }
            let metadata: ShellConfigurationCatalog
            if metadataScope == MetadataScope(snapshot), let catalog { metadata = catalog }
            else { metadata = try await catalogLoader.load(directories: snapshot.directories, root: island.root) }
            let layout = ShellIslandLayout(profile: snapshot.profile, root: island.root, components: island.components)
            let edit = try layout.applying(
                operation, catalog: metadata.descriptors, rootOptions: metadata.settings?.options ?? [:]
            )
            if case let .components(components) = edit.change {
                guard let source = snapshot.widget(island.root) ?? ShellConfig.bundledWidget(island.root) else {
                    throw ShellComponentCatalog.Failure("The island widget is missing")
                }
                _ = try await sourceLoader.prepare(.init(
                    name: island.root, shellDirectory: shellDirectory, sourceURL: source,
                    directories: snapshot.directories, profile: snapshot.profile, components: components
                ))
            }
            guard try load(profile: profile) == snapshot else {
                throw ShellComponentCatalog.Failure("configuration_changed")
            }
            try validate(snapshot)
            let revision = try await persistence().persist(edit.change, profile: layout.profile, root: layout.root)
            try await saved()
            return IslandCommit(instanceID: edit.instanceID, revision: revision)
        }
    }

    func editBar(_ change: @escaping @MainActor (inout ShellBarLayout) -> Void) async throws {
        let profile = try load().profile
        try await ordered { [self] in
            var layout = try ShellBarLayout.load(shellDirectory: shellDirectory, profile: profile).get()
            change(&layout)
            let next = layout
            _ = try await persistence().perform { directory in
                try next.save(shellDirectory: directory)
                return true
            }
            try await saved()
        }
    }

    func resetBarLayout() async throws {
        let profile = try load().profile
        try await ordered { [self] in
            _ = try await persistence().perform { directory in
                try ShellProfiles.setNodes(
                    ["leading", "center", "trailing"].map { (ShellProfiles.key($0, of: profile), nil) },
                    in: directory
                )
            }
            try await saved()
        }
    }

    func setSystemStatsEnabled(_ enabled: Bool) async throws {
        _ = try await editFile(refreshMetadata: false) { try ShellBarLayout.setSystemStatsEnabled(enabled, in: $0) }
    }

    func updateMonitor(_ monitor: Monitor, change: (@MainActor (inout MonitorBarSettings) -> Void)?) async throws {
        let profile = try load().profile
        try await ordered { [self] in
            let snapshot = try load(profile: profile)
            var overrides = snapshot.barOverride?.monitorOverrides ?? []
            if let change {
                var value = MonitorSettingsStore.get(for: monitor, in: overrides)
                    ?? MonitorBarSettings(monitorName: monitor.name)
                change(&value)
                if value.overriddenKeys.isEmpty { MonitorSettingsStore.remove(for: monitor, from: &overrides) }
                else { MonitorSettingsStore.update(value, for: monitor, in: &overrides) }
            } else { MonitorSettingsStore.remove(for: monitor, from: &overrides) }
            let node = try overrides.isEmpty ? nil : ShellTOMLText.node(overrides)
            let name = snapshot.profile
            _ = try await persistence().perform { directory in
                try ShellProfiles.setNodes([(ShellProfiles.key("monitorBarOverrides", of: name), node)], in: directory)
            }
            try await saved()
        }
    }

    func editFile(
        refreshMetadata: Bool = true,
        _ operation: @escaping @Sendable (URL) throws -> Bool
    ) async throws -> Bool {
        try await ordered { [self] in
            let changed = try await persistence().perform(operation)
            if changed { try await saved(refreshMetadata: refreshMetadata) }
            return changed
        }
    }

    func flush() async {
        await tail?.value
        await writer?.flush()
    }

    private func setNode(_ node: TOMLNode?, path: [String], profile: String?) async throws {
        let profile = try load(profile: profile).profile
        try await ordered { [self] in
            let name = try load(profile: profile).profile
            _ = try await persistence().perform { directory in
                try ShellProfiles.setNodes([([ShellConfig.profilesKey, name] + path, node)], in: directory)
            }
            try await saved()
        }
    }

    private func load(profile: String? = nil) throws -> ShellConfig {
        var problems: [String] = []
        let value = if let profile {
            ShellConfig.load(profile: profile, shellDirectory: shellDirectory, problems: &problems)
        } else { ShellConfig.load(shellDirectory: shellDirectory, problems: &problems) }
        guard let value else { throw ShellBarLayout.Unreadable(problem: problems.last ?? "shell.toml") }
        return value
    }

    private func reload(refreshMetadata: Bool = false) async throws {
        let snapshot = try load()
        config = snapshot
        let scope = MetadataScope(snapshot)
        if !refreshMetadata, metadataScope == scope {
            revision += 1
            return
        }
        metadataScope = nil
        profiles = ShellProfiles.names(in: shellDirectory)
        themes = ShellProfiles.themes(of: snapshot)
        widgetSchemas = [:]
        catalog = nil
        metadataError = nil
        let widgets = ShellConfig.widgetFolders(in: shellDirectory).map(\.lastPathComponent)
            + snapshot.directories.flatMap { ShellConfig.widgetFolders(in: $0).map(\.lastPathComponent) }
        widgetSchemas = try await catalogLoader.settings(widgets: widgets, directories: snapshot.directories)
        if let root = snapshot.island?.root {
            catalog = try await catalogLoader.load(directories: snapshot.directories, root: root)
        } else { catalog = nil }
        metadataScope = scope
        revision += 1
    }

    private func saved(refreshMetadata: Bool = false) async throws {
        config = try load()
        onSave?(config)
        NotificationCenter.default.post(name: .shellConfigDidChange, object: nil)
        do { try await reload(refreshMetadata: refreshMetadata) }
        catch { metadataError = error.localizedDescription }
    }

    private func persistence() -> ShellIslandConfigWriter {
        if let writer { return writer }
        let value = ShellIslandConfigWriter(shellDirectory: shellDirectory) { [weak self] in
            await self?.reloadAfterPersistence()
        }
        writer = value
        return value
    }

    private func reloadAfterPersistence() async {
        do { try await refresh() }
        catch { metadataError = error.localizedDescription }
    }

    private func ordered<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws
        -> Value
    {
        let previous = tail
        pendingCount += 1
        let task = Task { @MainActor [self] in
            await previous?.value
            defer { pendingCount -= 1 }
            return try await operation()
        }
        tail = Task { @MainActor in _ = try? await task.value }
        return try await task.value
    }
}
