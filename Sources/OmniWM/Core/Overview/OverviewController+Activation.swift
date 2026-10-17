// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension OverviewController {
    func focusTargetWindow(_ handle: WindowHandle) {
        guard let workspaceId = activationWorkspaceId(for: handle) else { return }
        onActivateWindow?(handle, workspaceId)
    }

    func activateWorkspace(_ workspaceId: WorkspaceDescriptor.ID) {
        guard case .open = state, let wmController else { return }
        guard !hasActiveDragSession else { return }
        commitOverviewPans()
        let workspaceManager = wmController.workspaceManager
        let previousWorkspaceId = workspaceManager.monitorForWorkspace(workspaceId)
            .flatMap { workspaceManager.activeWorkspace(on: $0.id)?.id }
        guard onActivateWorkspace?(workspaceId) == true else {
            dismiss(reason: .cancel, animated: true)
            return
        }
        refreshCachedOverviewProjection(
            affectedWorkspaceIds: Set([previousWorkspaceId, workspaceId].compactMap { $0 }),
            settledNiriFrames: true,
            revealingSelection: false
        )
        dismiss(reason: .workspaceActivation, animated: true)
    }

    func createWorkspace(on monitorId: Monitor.ID) {
        guard case .open = state, !hasActiveDragSession,
              let workspace = wmController?.workspaceNavigationHandler.createOverviewWorkspace(on: monitorId)
        else { return }
        activateWorkspace(workspace.id)
    }

    func prepareActivation(_ handle: WindowHandle) {
        guard let wmController, let workspaceId = activationWorkspaceId(for: handle) else { return }
        let workspaceManager = wmController.workspaceManager
        let previousWorkspaceId = workspaceManager.monitorForWorkspace(workspaceId)
            .flatMap { workspaceManager.activeWorkspace(on: $0.id)?.id }
        onPrepareActivation?(handle, workspaceId)
        refreshCachedOverviewProjection(
            affectedWorkspaceIds: Set([previousWorkspaceId, workspaceId].compactMap { $0 }),
            selectedHandle: handle,
            settledNiriFrames: true
        )
    }

    func activationWorkspaceId(for handle: WindowHandle) -> WorkspaceDescriptor.ID? {
        guard let wmController,
              wmController.workspaceManager.handle(for: handle.id) === handle
        else { return nil }
        return wmController.workspaceManager.entry(for: handle)?.workspaceId
    }

    @discardableResult
    func closeWindow(_ handle: WindowHandle) -> Bool {
        guard case .open = state else { return false }
        return onCloseWindow?(handle) == true
    }
}
