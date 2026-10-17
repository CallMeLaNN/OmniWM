// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension WorkspaceNavigationHandler {
    func activateOverviewWorkspace(_ workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let controller,
              let workspace = controller.workspaceManager.descriptor(for: workspaceId)
        else { return false }
        return switchWorkspace(rawWorkspaceID: workspace.name, affectedWorkspaces: [workspaceId])
    }

    func createOverviewWorkspace(on monitorId: Monitor.ID) -> WorkspaceDescriptor? {
        guard let controller,
              controller.workspaceManager.monitor(byId: monitorId) != nil
        else { return nil }
        let manager = controller.workspaceManager
        var candidate = manager.workspaces(on: monitorId).last.flatMap { Int($0.name) } ?? 0
        while true {
            let next = candidate.addingReportingOverflow(1)
            guard !next.overflow else { return nil }
            candidate = next.partialValue
            let name = String(candidate)
            guard manager.workspaceId(named: name) == nil else { continue }
            guard let workspace = manager.createDynamicWorkspace(named: name, on: monitorId) else { return nil }
            controller.syncMonitorsToNiriEngine()
            return workspace
        }
    }
}
