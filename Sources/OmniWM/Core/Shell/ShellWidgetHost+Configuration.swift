// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

extension ShellWidgetHost {
    func refreshConfigurationCatalog() {
        configurationCatalogRevision += 1
        configurationCatalogError = nil
        loadConfigurationCatalog()
    }

    private func loadConfigurationCatalog() {
        guard started, configurationCatalogLoading == nil else { return }
        guard let root = config.island?.root else {
            processConfigurationQueue()
            return
        }
        let revision = configurationCatalogRevision
        let directories = config.directories
        configurationCatalogLoading = revision
        Task { [weak self, configurationCatalogLoader] in
            let result: Result<ShellConfigurationCatalog, Error>
            do { result = try await .success(configurationCatalogLoader.load(directories: directories, root: root)) }
            catch { result = .failure(error) }
            guard let self, started, configurationCatalogLoading == revision else { return }
            configurationCatalogLoading = nil
            guard configurationCatalogRevision == revision, config.directories == directories,
                  config.island?.root == root
            else {
                loadConfigurationCatalog()
                return
            }
            switch result {
            case let .success(catalog):
                configurationCatalog = catalog
                configurationCatalogError = nil
            case let .failure(error):
                configurationCatalog = nil
                configurationCatalogError = error.localizedDescription
                ShellConfig.report(error.localizedDescription, &configProblems)
                publishToggleNames()
            }
            if let state = widgets[root] { publishConfigurationCatalog(to: state) }
            watchFiles()
            processConfigurationQueue()
        }
    }

    struct ConfigurationSubmission {
        let request: ShellConfigurationRequest
        let state: WidgetState
        let generation: Int
    }

    func publishConfigurationCatalog(to state: WidgetState) {
        let enabled = state.name == config.island?.root
        let catalog = configurationCatalog.flatMap { value in
            enabled && value.root == state.name && value.directories == config.directories ? value : nil
        }
        state.mailbox?.yield(.catalog(enabled: enabled, catalog: catalog?.bytes ?? [], schema: catalog?.schema ?? []))
    }

    var configurationMetadataPaths: [URL] {
        let manifests = configurationCatalog?.entries.flatMap { entry in
            entry.sources.map { $0.appendingPathComponent("component.toml") }
        } ?? []
        let settings = config.island.map { island in
            config.directories.map { $0.appendingPathComponent("widgets/\(island.root)/settings.toml") }
        } ?? []
        return manifests + settings
    }

    func stopConfiguration() {
        configurationEpoch += 1
        configurationCatalogRevision += 1
        configurationCatalogLoading = nil
        configurationCatalog = nil
        configurationCatalogError = nil
        configurationProcessing = false
        configurationWorkCount = 0
        pendingConfigurationEdits.removeAll()
        if let writer = configurationWriter {
            configurationWriter = nil
            let id = ObjectIdentifier(writer)
            Self.retiringTasks[id] = Task {
                await writer.flush()
                Self.retiringTasks.removeValue(forKey: id)
            }
        }
    }

    func enqueueConfigurationRequests(_ requests: [ShellConfigurationRequest], to state: WidgetState) {
        guard started, !requests.isEmpty, let package = state.package else { return }
        pendingConfigurationEdits.removeAll { submission in
            guard widgets[submission.state.name] !== submission.state || submission.state.generation != submission
                .generation
            else {
                return false
            }
            configurationWorkCount -= 1
            return true
        }
        for request in requests {
            guard configurationWorkCount < 256 else {
                package.services.complete(ShellConfigurationRequest.completion(id: request.id, error: "overload"))
                continue
            }
            configurationWorkCount += 1
            pendingConfigurationEdits.append(ConfigurationSubmission(
                request: request,
                state: state,
                generation: state.generation
            ))
        }
        processConfigurationQueue()
    }

    func processConfigurationQueue() {
        guard started, !configurationProcessing, let first = pendingConfigurationEdits.first else { return }
        if first.state.name == config.island?.root, configurationCatalog == nil,
           configurationCatalogError == nil { return }
        configurationProcessing = true
        let epoch = configurationEpoch
        Task { [weak self] in await self?.applyConfigurationRequests(epoch: epoch) }
    }

    private func applyConfigurationRequests(epoch: Int) async {
        defer { if configurationEpoch == epoch { configurationProcessing = false } }
        while started, configurationEpoch == epoch, !pendingConfigurationEdits.isEmpty {
            let submission = pendingConfigurationEdits.removeFirst()
            let state = submission.state
            let request = submission.request
            guard widgets[state.name] === state, state.generation == submission.generation,
                  let package = state.package
            else {
                configurationWorkCount -= 1
                continue
            }
            do {
                guard request.id.owner.owner == 0, request.id.owner.generation == package.services.generation,
                      state.name == config.island?.root, let island = config.island,
                      let catalog = configurationCatalog, catalog.directories == config.directories,
                      catalog.root == island.root
                else {
                    throw ShellComponentCatalog
                        .Failure(configurationCatalogError ?? "Island configuration is not available")
                }
                let snapshot = config
                let fingerprint = state.fingerprint
                let layout = ShellIslandLayout(
                    profile: config.profile,
                    root: island.root,
                    components: island.components
                )
                let edit = try layout.applying(
                    request.operation,
                    catalog: catalog.descriptors,
                    rootOptions: catalog.settings?.options ?? [:]
                )
                switch edit.change {
                case let .components(components):
                    let prepared = try await configurationSourceLoader.prepare(.init(
                        name: state.name, shellDirectory: shellDirectory, sourceURL: state.sourceURL,
                        directories: snapshot.directories, profile: snapshot.profile, components: components
                    ))
                    guard started, configurationEpoch == epoch, widgets[state.name] === state,
                          state.generation == submission.generation, state.package === package,
                          config == snapshot, configurationCatalog == catalog, state.fingerprint == fingerprint
                    else { throw ShellComponentCatalog.Failure("configuration_changed") }
                    config.island?.components = components
                    applyComponentSource(prepared.source, fingerprint: prepared.fingerprint, to: state)
                case let .rootSetting(key, value):
                    var fields: [String: ShellServiceValue] = [:]
                    if let bytes = config.widgetSettings[state.name], !bytes.isEmpty {
                        guard let current = try ShellServiceValue.decode(bytes).fields
                        else { throw ShellServiceValue.Failure() }
                        fields = current
                    }
                    var encodedValue = ShellValueWriter()
                    value.write(to: &encodedValue)
                    fields[key] = try ShellServiceValue.decode(encodedValue.bytes)
                    var writer = ShellValueWriter()
                    ShellServiceValue.object(fields).write(to: &writer)
                    config.widgetSettings[state.name] = writer.bytes
                    state.mailbox?.yield(.settings(writer.bytes))
                    if key == "interval" {
                        config.widgetIntervals[state.name] = if case let .number(number) = value {
                            ShellWidgetDeclaration.validInterval(number)
                        } else { nil }
                        state.mailbox?.yield(.interval(interval(of: state)))
                        publishDemand()
                    }
                }
                let write = ShellIslandConfigWriter.Write(
                    id: request.id,
                    profile: layout.profile,
                    root: layout.root,
                    change: edit.change
                )
                configurationPersistence().submit(write) { [
                    weak self,
                    services = package.services,
                    instance = edit.instanceID
                ] result in
                    Task { @MainActor [weak self] in
                        if let self, configurationEpoch == epoch { configurationWorkCount -= 1 }
                        services.complete(ShellConfigurationRequest.completion(
                            id: result.id, instance: instance, revision: result.revision, error: result.error
                        ))
                    }
                }
                onConfigChange?(config)
            } catch {
                if configurationEpoch == epoch { configurationWorkCount -= 1 }
                package.services.complete(ShellConfigurationRequest.completion(
                    id: request.id,
                    error: error.localizedDescription
                ))
            }
        }
    }

    private func configurationPersistence() -> ShellIslandConfigWriter {
        if let configurationWriter { return configurationWriter }
        let writer = ShellIslandConfigWriter(shellDirectory: shellDirectory) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, started else { return }
                reloadConfig()
            }
        }
        configurationWriter = writer
        return writer
    }
}
