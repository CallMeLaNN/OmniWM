// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct CrossDisplayDropPlan {
    enum Operation: Equatable {
        case move(CrossDisplayDrop.Placement)
        case swap(partner: WindowToken)
    }

    let drop: CrossDisplayDrop
    let sourceLayout: ActiveLayoutKind
    let targetLayout: ActiveLayoutKind
    let operation: Operation
    let incomingConstraints: WindowSizeConstraints
    let partnerConstraints: WindowSizeConstraints

    var niriWorkspaceIds: [WorkspaceDescriptor.ID] {
        [(drop.sourceWorkspaceId, sourceLayout), (drop.workspaceId, targetLayout)]
            .filter { $0.1 == .niri }
            .map(\.0)
    }
}

extension WMController {
    func crossDisplayDropPlan(for drop: CrossDisplayDrop) -> CrossDisplayDropPlan? {
        let manager = workspaceManager
        guard drop.sourceWorkspaceId != drop.workspaceId,
              isCrossDisplayTransferable(drop.sourceToken, in: drop.sourceWorkspaceId),
              let sourceMonitor = manager.monitor(for: drop.sourceWorkspaceId)
        else {
            return nil
        }
        let sourceLayout = manager.activeLayoutKind(for: drop.sourceWorkspaceId)
        let targetLayout = manager.activeLayoutKind(for: drop.workspaceId)
        let incoming = layoutRefreshController.destinationConstraints(for: drop.sourceToken, on: drop.monitor)

        let operation: CrossDisplayDropPlan.Operation
        var partnerConstraints = WindowSizeConstraints.unconstrained
        if case let .swap(partner) = drop.placement {
            guard isCrossDisplayTransferable(partner, in: drop.workspaceId) else { return nil }
            partnerConstraints = layoutRefreshController.destinationConstraints(for: partner, on: sourceMonitor)
            guard niriSlotAccepts(
                drop.sourceToken, constraints: incoming, replacing: partner, in: drop.workspaceId, on: drop.monitor
            ),
                niriSlotAccepts(
                    partner,
                    constraints: partnerConstraints,
                    replacing: drop.sourceToken,
                    in: drop.sourceWorkspaceId,
                    on: sourceMonitor
                )
            else {
                return nil
            }
            operation = .swap(partner: partner)
        } else {
            operation = .move(validatedCrossDisplayPlacement(drop, incoming: incoming))
        }
        return CrossDisplayDropPlan(
            drop: drop,
            sourceLayout: sourceLayout,
            targetLayout: targetLayout,
            operation: operation,
            incomingConstraints: incoming,
            partnerConstraints: partnerConstraints
        )
    }

    private func isCrossDisplayTransferable(_ token: WindowToken, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let entry = workspaceManager.entry(for: token),
              entry.workspaceId == workspaceId,
              entry.mode == .tiling,
              !workspaceManager.isWindowSuppressedByMacOS(token)
        else {
            return false
        }
        switch workspaceManager.activeLayoutKind(for: workspaceId) {
        case .niri:
            guard let engine = niriEngine, let node = engine.findNode(for: token, in: workspaceId) else { return false }
            return !node.isFullscreen && !engine.projectionExclusions(in: workspaceId).contains(token)
        case .dwindle:
            guard let engine = dwindleEngine,
                  engine.tile(containing: token, in: workspaceId) != nil else { return false }
            return !engine.isWindowFullscreen(token, in: workspaceId)
                && !engine.excludedTokens(in: workspaceId).contains(token)
        }
    }

    private func niriSlotAccepts(
        _ token: WindowToken,
        constraints: WindowSizeConstraints,
        replacing partner: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        on monitor: Monitor
    ) -> Bool {
        guard workspaceManager.activeLayoutKind(for: workspaceId) == .niri else { return true }
        guard let engine = niriEngine,
              let partnerNode = engine.findNode(for: partner, in: workspaceId),
              let column = engine.findColumn(containing: partnerNode, in: workspaceId)
        else {
            return false
        }
        return engine.columnCanAcceptTransfer(
            column,
            adding: NiriWindow(token: token),
            addingConstraints: constraints,
            removing: partnerNode,
            in: workspaceId,
            geometry: niriSizingGeometry(for: monitor)
        )
    }

    private func validatedCrossDisplayPlacement(
        _ drop: CrossDisplayDrop,
        incoming: WindowSizeConstraints
    ) -> CrossDisplayDrop.Placement {
        let workspaceId = drop.workspaceId
        switch drop.placement {
        case let .niriStack(target, _):
            guard let engine = niriEngine,
                  let targetNode = engine.findNode(for: target, in: workspaceId),
                  !targetNode.isFullscreen,
                  let column = engine.findColumn(containing: targetNode, in: workspaceId),
                  engine.columnCanAcceptTransfer(
                      column,
                      adding: NiriWindow(token: drop.sourceToken),
                      addingConstraints: incoming,
                      in: workspaceId,
                      geometry: niriSizingGeometry(for: drop.monitor)
                  )
            else {
                return .workspace
            }
            return drop.placement
        case let .dwindleBeside(target, _):
            guard let engine = dwindleEngine,
                  engine.tile(containing: target, in: workspaceId) != nil,
                  !engine.isWindowFullscreen(target, in: workspaceId)
            else {
                return .workspace
            }
            return drop.placement
        case .dwindleEdge:
            return dwindleEngine?.visibleTiles(in: workspaceId).any == true ? drop.placement : .workspace
        case .niriNewColumn,
             .swap,
             .workspace:
            return drop.placement
        }
    }

    func niriSizingGeometry(for monitor: Monitor) -> NiriSizingGeometry {
        NiriSizingGeometry(
            workingFrame: niriWorkingFrame(for: monitor),
            gaps: innerGap(for: monitor),
            orientation: settings.monitors.effectiveOrientation(for: monitor)
        )
    }
}
