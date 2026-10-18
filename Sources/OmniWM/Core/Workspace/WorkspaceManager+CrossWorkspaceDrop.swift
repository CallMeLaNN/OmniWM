// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct CrossWorkspaceDropAssignment {
    let token: WindowToken
    let workspaceId: WorkspaceDescriptor.ID
}

extension WorkspaceManager {
    func withBatchedCrossWorkspaceDrop(
        into targetWorkspaceId: WorkspaceDescriptor.ID,
        niriWorkspaceIds: [WorkspaceDescriptor.ID],
        _ apply: (inout [WorkspaceDescriptor.ID: ViewportState]) -> [CrossWorkspaceDropAssignment]
    ) {
        var states = Dictionary(uniqueKeysWithValues: niriWorkspaceIds.map { ($0, niriViewportState(for: $0)) })
        commitWorldEvent(
            .userCommand(workspaceId: targetWorkspaceId, label: "cross_display_drop", source: .mouse),
            monitors: monitors,
            preMutate: {
                let assignments = apply(&states)
                for workspaceId in niriWorkspaceIds {
                    guard var state = states[workspaceId] else { continue }
                    self.normalizeNiriRefreshRate(&state, for: workspaceId)
                    self.applyViewportInBatch(state, for: workspaceId)
                }
                for assignment in assignments {
                    self.setWorkspace(for: assignment.token, to: assignment.workspaceId)
                }
                for workspaceId in niriWorkspaceIds {
                    let arrived = assignments.filter { $0.workspaceId == workspaceId }.map(\.token)
                    if !arrived.isEmpty {
                        self.captureLiveNiriPlacements(containing: arrived, in: workspaceId)
                    }
                }
            },
            resolvePlan: { plan, _, _ in plan }
        )
    }
}
