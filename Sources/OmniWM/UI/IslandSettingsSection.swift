// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import SwiftUI

struct IslandSettingsSection: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    let shellDirectory: URL

    @State private var config = ShellConfig()
    @State private var canCustomize = false
    @State private var islandStatus: String?
    @State private var editError: String?

    var body: some View {
        Section {
            Toggle("Enable Island", isOn: Bindable(settings.island).enabled)
                .disabled(config.island == nil && !settings.island.enabled)
                .onChange(of: settings.island.enabled) { _, _ in
                    controller.updateWorkspaceBarSettings()
                    refreshWidget()
                }

            if config.island != nil {
                LabeledContent("Island Profile", value: config.profile)
                Button("Customize Island Widgets…", action: customize)
                    .disabled(!settings.island.enabled || !canCustomize)
                if !settings.island.enabled {
                    Text("Enable Island to add, arrange, and customize its widgets.")
                        .foregroundStyle(.secondary)
                } else if let islandStatus {
                    Text(islandStatus)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("The selected shell profile has no island.")
                    .foregroundStyle(.secondary)
                Button("Use Lake Profile", action: useLake)
                Text(
                    "Selects the Lake shell profile for both the bar layout and island. Your Workspace Bar enable setting stays the same."
                )
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Dynamic Island")
        } footer: {
            Text("The island and Workspace Bar can run together or separately.")
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .shellConfigDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shellWidgetsDidChange)) { _ in
            refreshWidget()
        }
        .shellSettingsError($editError)
    }

    private func reload() {
        config = controller.workspaceBarManager.shellHost?.config ?? ShellConfig.resolve(shellDirectory: shellDirectory)
        refreshWidget()
    }

    private func refreshWidget() {
        canCustomize = false
        islandStatus = nil
        guard let root = config.island?.root else { return }
        guard let widget = controller.workspaceBarManager.shellHost?.widgets[root] else {
            islandStatus = String(localized: "Waiting for the island profile to load.")
            return
        }
        guard widget.package != nil else {
            islandStatus = widget.lastFailure?.message ?? String(localized: "Waiting for the island profile to load.")
            return
        }
        canCustomize = widget.declaration.hasTrigger
        if !canCustomize {
            islandStatus =
                String(
                    localized: "This island profile has no customization action. Its layout can be edited in the shell folder."
                )
        }
    }

    private func useLake() {
        do {
            try ShellSettingsEdits.apply(settings: settings, controller: controller) { directory, _ in
                try ShellProfiles.select("lake", in: directory)
            }
            if controller.workspaceBarManager.shellHost == nil {
                NotificationCenter.default.post(name: .shellConfigDidChange, object: nil)
            }
            reload()
        } catch {
            editError = error.localizedDescription
        }
    }

    private func customize() {
        guard settings.island.enabled, let root = config.island?.root else { return }
        if controller.workspaceBarManager
            .applyShellRequest(.trigger(widget: root, name: "settings", value: nil)) != .executed
        {
            editError = String(localized: "The island profile is not ready to open its customization controls.")
        }
        refreshWidget()
    }
}
