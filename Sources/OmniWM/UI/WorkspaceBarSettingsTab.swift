// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import SwiftUI

struct WorkspaceBarSettingsTab: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController

    @State private var selectedMonitor: Monitor.ID?
    @State private var connectedMonitors: [Monitor] = Monitor.current()
    @State private var editError: String?

    private var shellDirectory: URL {
        ShellWidgetHost.shellDirectory(in: settings.settingsFileURL.deletingLastPathComponent())
    }

    var body: some View {
        Form {
            IslandSettingsSection(settings: settings, controller: controller, shellDirectory: shellDirectory)

            if let override = settings.workspaceBar.profileOverride {
                Section {
                    Label(
                        String(
                            localized: "Settings are saved for the “\(override.profile)” shell profile."
                        ),
                        systemImage: "paintbrush"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            MonitorScopeSection(
                selectedMonitor: $selectedMonitor,
                monitors: connectedMonitors,
                hasOverrides: {
                    MonitorSettingsStore.get(
                        for: $0,
                        in: settings.workspaceBar.profileOverride?.monitorOverrides ?? []
                    ) != nil
                },
                reset: { monitor in
                    do {
                        try ShellSettingsEdits.updateMonitor(
                            monitor,
                            settings: settings,
                            controller: controller,
                            change: nil
                        )
                    } catch {
                        editError = error.localizedDescription
                    }
                }
            )

            if let monitorId = selectedMonitor,
               let monitor = connectedMonitors.first(where: { $0.id == monitorId })
            {
                MonitorBarSettingsSection(
                    settings: settings,
                    controller: controller,
                    monitor: monitor
                )
            } else {
                GlobalBarSettingsSection(
                    settings: settings,
                    controller: controller
                )
            }

            WorkspaceBarWidgetsSection(
                shellDirectory: shellDirectory,
                vertical: ShellBarLayout.vertical(settings.workspaceBar, on: connectedMonitors)
            )

            ShellSettingsSection(shellDirectory: shellDirectory)

            WorkspaceBarExcludedAppsSection(
                settings: settings,
                controller: controller
            )

            WorkspaceBarIconOverridesSection(
                settings: settings,
                controller: controller
            )
        }
        .formStyle(.grouped)
        .onAppear {
            connectedMonitors = Monitor.current()
        }
        .shellSettingsError($editError)
    }
}
