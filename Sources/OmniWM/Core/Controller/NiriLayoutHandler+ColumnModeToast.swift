// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension NiriLayoutHandler {
    func showColumnModeToast(
        engine: NiriLayoutEngine,
        workspaceId: WorkspaceDescriptor.ID,
        state: ViewportState,
        motion: MotionSnapshot
    ) {
        guard let controller,
              let monitor = controller.workspaceManager.monitor(for: workspaceId),
              let selectedId = state.selectedNodeId,
              let selectedNode = engine.findNode(by: selectedId, in: workspaceId),
              let column = engine.column(of: selectedNode),
              let frame = column.renderedFrame,
              !frame.isNull,
              !frame.isInfinite,
              frame.width > 0,
              frame.height > 0
        else {
            controller?.columnModeToast.hide()
            return
        }
        controller.columnModeToast.show(
            isTabbed: column.isTabbed,
            columnFrame: frame,
            visibleFrame: monitor.visibleFrame,
            motion: motion,
            source: .init(workspaceId: workspaceId, monitorId: monitor.id)
        )
    }
}
