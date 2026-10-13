// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import SwiftUI

@MainActor
enum ShellSettingsEdits {
    static func apply(
        settings: SettingsStore,
        controller: WMController,
        _ change: (URL, ShellConfig) throws -> Bool
    ) throws {
        let directory = ShellWidgetHost.shellDirectory(in: settings.settingsFileURL.deletingLastPathComponent())
        var problems: [String] = []
        guard let config = ShellConfig.load(shellDirectory: directory, problems: &problems) else {
            throw ShellBarLayout.Unreadable(problem: problems.last ?? "shell.toml")
        }
        if try change(directory, config) {
            if let host = controller.workspaceBarManager.shellHost {
                host.reloadConfig()
            } else {
                let updated = ShellConfig.resolve(shellDirectory: directory)
                settings.workspaceBar.profileOverride = updated.barOverride
                settings.hiddenBar.profileOverride = updated.hiddenBarOverride
                controller.updateHiddenBarSettings()
            }
        }
    }

    static func set<Value: Encodable>(
        _ value: Value?,
        key: String,
        table: String = "workspaceBar",
        settings: SettingsStore,
        controller: WMController
    ) throws {
        try apply(settings: settings, controller: controller) { directory, config in
            try ShellProfiles.setValue(value, at: ShellProfiles.key(table, of: config.profile) + [key], in: directory)
        }
    }

    static func reset(
        table: String = "workspaceBar",
        settings: SettingsStore,
        controller: WMController
    ) throws {
        try apply(settings: settings, controller: controller) { directory, config in
            try ShellProfiles.reset(ShellProfiles.key(table, of: config.profile), in: directory)
        }
    }

    static func updateMonitor(
        _ monitor: Monitor,
        settings: SettingsStore,
        controller: WMController,
        change: ((inout MonitorBarSettings) -> Void)?
    ) throws {
        try apply(settings: settings, controller: controller) { directory, config in
            var overrides = config.barOverride?.monitorOverrides ?? []
            if let change {
                var value = MonitorSettingsStore.get(for: monitor, in: overrides)
                    ?? MonitorBarSettings(monitorName: monitor.name)
                change(&value)
                if value.overriddenKeys.isEmpty {
                    MonitorSettingsStore.remove(for: monitor, from: &overrides)
                } else {
                    MonitorSettingsStore.update(value, for: monitor, in: &overrides)
                }
            } else {
                MonitorSettingsStore.remove(for: monitor, from: &overrides)
            }
            return try ShellProfiles.setValue(
                overrides.isEmpty ? nil : overrides,
                at: ShellProfiles.key("monitorBarOverrides", of: config.profile),
                in: directory
            )
        }
    }
}

extension View {
    func shellSettingsError(_ error: Binding<String?>) -> some View {
        alert("Unable to Save Shell Settings", isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? "")
        }
    }
}
