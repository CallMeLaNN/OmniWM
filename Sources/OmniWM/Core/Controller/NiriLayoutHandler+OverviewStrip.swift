// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension NiriLayoutHandler {
    func overviewSnapshot(for workspaceId: WorkspaceDescriptor.ID) -> NiriOverviewWorkspaceSnapshot? {
        guard let controller,
              let engine = controller.niriEngine,
              !engine.columns(in: workspaceId).isEmpty,
              let monitor = controller.workspaceManager.monitor(for: workspaceId),
              let snapshot = makeWorkspaceSnapshot(
                  workspaceId: workspaceId,
                  monitor: monitor,
                  options: SnapshotOptions(
                      viewportState: controller.workspaceManager.niriViewportState(for: workspaceId),
                      useScrollAnimationPath: false,
                      removalSeed: nil,
                      isActiveWorkspace: controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
                          == workspaceId
                  )
              )
        else { return nil }
        let area = WorkingAreaContext(
            workingFrame: snapshot.niriWorkingFrame,
            singleWindowFrame: snapshot.monitor.workingFrame,
            borderSafeFillFrame: snapshot.monitor.borderSafeFillFrame,
            fullscreenLayoutFrame: snapshot.fullscreenLayoutFrame,
            viewFrame: snapshot.monitor.frame,
            scale: snapshot.monitor.scale
        )
        return controller.workspaceManager.withEngineMutationScope(in: workspaceId, label: "overview_geometry") {
            engine.overviewSnapshot(
                for: workspaceId,
                state: snapshot.viewportState,
                geometry: NiriLayoutGeometry(
                    workingArea: area,
                    gaps: LayoutGaps(horizontal: snapshot.gap, vertical: snapshot.gap),
                    orientation: snapshot.monitor.orientation
                )
            )
        }
    }
}
