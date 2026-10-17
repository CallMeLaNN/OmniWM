// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension NiriLayoutHandler {
    @discardableResult
    func commitOverviewPans(_ pans: [WorkspaceDescriptor.ID: CGFloat]) -> Set<WorkspaceDescriptor.ID> {
        guard let controller, let engine = controller.niriEngine else { return [] }
        let manager = controller.workspaceManager
        var committed: Set<WorkspaceDescriptor.ID> = []
        for (workspaceId, pan) in pans {
            guard pan.isFinite, pan != 0,
                  manager.descriptor(for: workspaceId) != nil,
                  manager.activeLayoutKind(for: workspaceId) == .niri,
                  let monitor = manager.monitor(for: workspaceId)
            else { continue }
            let applied = manager.withEngineMutationScope(in: workspaceId, label: "overview_pan") {
                cancelAnimationMotion(for: workspaceId)
                for (displayId, animatedWorkspaceId) in scrollAnimationByDisplay
                    where animatedWorkspaceId == workspaceId
                {
                    controller.layoutRefreshController.stopScrollAnimation(for: displayId)
                }
                var state = manager.niriViewportState(for: workspaceId)
                state.jumpOffset(to: state.viewOffset - pan)
                guard manager.applySessionPatch(WorkspaceSessionPatch(
                    workspaceId: workspaceId, viewportState: state, plannedSeq: manager.worldSeq
                )) else { return false }
                if manager.activeWorkspaceOrFirst(on: monitor.id)?.id == workspaceId {
                    applyFramesOnDemand(
                        wsId: workspaceId, state: manager.niriViewportState(for: workspaceId), engine: engine,
                        monitor: monitor, settlesAnimation: true
                    )
                }
                return true
            }
            if applied { committed.insert(workspaceId) }
        }
        return committed
    }
}
