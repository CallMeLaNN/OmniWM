// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension WMController {
    func performCrossDisplayDrop(_ drop: CrossDisplayDrop) {
        guard let plan = crossDisplayDropPlan(for: drop) else { return }
        let heldSelection = workspaceManager.selectedManagedToken == drop.sourceToken
        workspaceManager.withBatchedCrossWorkspaceDrop(
            into: drop.workspaceId,
            niriWorkspaceIds: plan.niriWorkspaceIds
        ) { states in
            switch plan.operation {
            case let .move(placement):
                applyCrossDisplayMove(plan, placement: placement, states: &states)
                return [.init(token: drop.sourceToken, workspaceId: drop.workspaceId)]
            case let .swap(partner):
                applyCrossDisplaySwap(plan, partner: partner, states: &states)
                return [
                    .init(token: drop.sourceToken, workspaceId: drop.workspaceId),
                    .init(token: partner, workspaceId: drop.sourceWorkspaceId)
                ]
            }
        }
        finishCrossDisplayDrop(plan, heldSelection: heldSelection)
    }

    private enum CrossDisplayUnit {
        case niri(NiriTransferredColumn)
        case dwindle(DwindleTransferredTile)
    }

    private func applyCrossDisplayMove(
        _ plan: CrossDisplayDropPlan,
        placement: CrossDisplayDrop.Placement,
        states: inout [WorkspaceDescriptor.ID: ViewportState]
    ) {
        let drop = plan.drop
        switch detachCrossDisplayUnit(plan, states: &states) {
        case let .niri(column):
            var state = states[drop.workspaceId, default: niriViewportState(for: drop.workspaceId)]
            attachCrossDisplayColumn(column, placement: placement, plan: plan, state: &state)
            states[drop.workspaceId] = state
        case let .dwindle(tile):
            dwindleEngine?.attachTransferredTile(
                tile,
                placement: Self.dwindleTransferPlacement(placement),
                in: drop.workspaceId
            )
        case nil:
            return
        }
        if plan.sourceLayout == .dwindle, plan.targetLayout == .niri {
            dwindleEngine?.releaseConstraintsIfUntracked(drop.sourceToken)
        }
    }

    private func detachCrossDisplayUnit(
        _ plan: CrossDisplayDropPlan,
        states: inout [WorkspaceDescriptor.ID: ViewportState]
    ) -> CrossDisplayUnit? {
        let token = plan.drop.sourceToken
        let source = plan.drop.sourceWorkspaceId
        switch plan.sourceLayout {
        case .niri:
            guard let engine = niriEngine, let node = engine.findNode(for: token, in: source) else { return nil }
            if plan.targetLayout == .dwindle {
                workspaceManager.captureDetachedNiriPlacement(for: token, in: source)
            }
            let sizing = engine.detachWindowForTransfer(
                node,
                from: source,
                sourceState: &states[source, default: niriViewportState(for: source)]
            )
            return plan.targetLayout == .niri
                ? .niri(NiriTransferredColumn(windows: [node], activeIndex: 0, sizing: sizing))
                : .dwindle(DwindleTransferredTile(token: token))
        case .dwindle:
            guard let tile = dwindleEngine?.detachForTransfer(token: token, wholeTile: false, from: source) else {
                return nil
            }
            guard plan.targetLayout == .niri else { return .dwindle(tile) }
            return .niri(NiriTransferredColumn(
                windows: [NiriWindow(token: token)],
                activeIndex: 0,
                sizing: admittedNiriContainerSizing(for: token)
            ))
        }
    }

    private func attachCrossDisplayColumn(
        _ column: NiriTransferredColumn,
        placement: CrossDisplayDrop.Placement,
        plan: CrossDisplayDropPlan,
        state: inout ViewportState
    ) {
        guard let engine = niriEngine else { return }
        let workspaceId = plan.drop.workspaceId
        let window = column.activeWindow
        window.constraints = plan.incomingConstraints
        if case let .niriStack(target, after) = placement,
           let targetNode = engine.findNode(for: target, in: workspaceId)
        {
            engine.attachTransferredWindow(
                window,
                stackedWith: targetNode,
                after: after,
                in: workspaceId,
                state: &state
            )
        } else {
            let index: Int? = if case let .niriNewColumn(durableIndex) = placement { durableIndex } else { nil }
            engine.attachTransferredColumn(column, atDurableColumnIndex: index, in: workspaceId, state: &state)
        }
        prepareCrossDisplayNiriViewport(for: window, in: workspaceId, state: &state)
    }

    private func applyCrossDisplaySwap(
        _ plan: CrossDisplayDropPlan,
        partner: WindowToken,
        states: inout [WorkspaceDescriptor.ID: ViewportState]
    ) {
        let drop = plan.drop
        let moved = (token: drop.sourceToken, workspaceId: drop.sourceWorkspaceId)
        let resident = (token: partner, workspaceId: drop.workspaceId)
        var sourceState = states[moved.workspaceId, default: niriViewportState(for: moved.workspaceId)]
        var targetState = states[resident.workspaceId, default: niriViewportState(for: resident.workspaceId)]
        defer {
            if plan.sourceLayout == .niri { states[moved.workspaceId] = sourceState }
            if plan.targetLayout == .niri { states[resident.workspaceId] = targetState }
        }

        switch (plan.sourceLayout, plan.targetLayout) {
        case (.niri, .niri):
            guard let engine = niriEngine,
                  let node = engine.findNode(for: moved.token, in: moved.workspaceId),
                  let partnerNode = engine.findNode(for: resident.token, in: resident.workspaceId)
            else { return }
            engine.swapWindowsAcrossWorkspaces(
                (node, moved.workspaceId),
                (partnerNode, resident.workspaceId),
                firstState: &sourceState,
                secondState: &targetState
            )
            node.constraints = plan.incomingConstraints
            partnerNode.constraints = plan.partnerConstraints
            prepareCrossDisplayNiriViewport(for: partnerNode, in: moved.workspaceId, state: &sourceState)
            prepareCrossDisplayNiriViewport(for: node, in: resident.workspaceId, state: &targetState)
        case (.niri, .dwindle):
            swapAcrossLayouts(
                niri: moved, dwindle: resident, arrivingConstraints: plan.partnerConstraints, niriState: &sourceState
            )
        case (.dwindle, .niri):
            swapAcrossLayouts(
                niri: resident, dwindle: moved, arrivingConstraints: plan.incomingConstraints, niriState: &targetState
            )
        case (.dwindle, .dwindle):
            guard let dwindle = dwindleEngine,
                  let outgoing = dwindle.replaceSlot(
                      of: resident.token,
                      wholeTile: false,
                      with: DwindleTransferredTile(token: moved.token),
                      in: resident.workspaceId
                  )
            else { return }
            _ = dwindle.replaceSlot(of: moved.token, wholeTile: false, with: outgoing, in: moved.workspaceId)
        }
    }

    private func swapAcrossLayouts(
        niri niriSide: (token: WindowToken, workspaceId: WorkspaceDescriptor.ID),
        dwindle dwindleSide: (token: WindowToken, workspaceId: WorkspaceDescriptor.ID),
        arrivingConstraints: WindowSizeConstraints,
        niriState: inout ViewportState
    ) {
        guard let engine = niriEngine, let dwindle = dwindleEngine,
              let node = engine.findNode(for: niriSide.token, in: niriSide.workspaceId)
        else { return }
        workspaceManager.captureDetachedNiriPlacement(for: niriSide.token, in: niriSide.workspaceId)
        _ = dwindle.replaceSlot(
            of: dwindleSide.token,
            wholeTile: false,
            with: DwindleTransferredTile(token: niriSide.token),
            in: dwindleSide.workspaceId
        )
        let arrived = NiriWindow(token: dwindleSide.token)
        arrived.constraints = arrivingConstraints
        engine.replaceWindowInSlot(node, with: [arrived], activeIndex: 0, in: niriSide.workspaceId, state: &niriState)
        dwindle.releaseConstraintsIfUntracked(dwindleSide.token)
        prepareCrossDisplayNiriViewport(for: arrived, in: niriSide.workspaceId, state: &niriState)
    }

    private func prepareCrossDisplayNiriViewport(
        for node: NiriWindow,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState
    ) {
        guard let engine = niriEngine, let monitor = workspaceManager.monitor(for: workspaceId) else { return }
        state.selectedNodeId = node.id
        engine.activateWindow(node.id, in: workspaceId)
        if engine.singleWindowLayoutContext(in: workspaceId) != nil {
            niriLayoutHandler.resetViewportForSingleWindowFit(state: &state)
            return
        }
        let geometry = niriSizingGeometry(for: monitor)
        engine.ensureSelectionVisible(
            node: node,
            context: NiriInteractionContext(
                workspaceId: workspaceId,
                motion: motionPolicy.snapshot(),
                workingFrame: geometry.workingFrame,
                gaps: geometry.gaps,
                orientation: geometry.orientation
            ),
            state: &state
        )
    }

    private func finishCrossDisplayDrop(_ plan: CrossDisplayDropPlan, heldSelection: Bool) {
        let drop = plan.drop
        let source = drop.sourceWorkspaceId
        let target = drop.workspaceId
        switch plan.operation {
        case .move:
            workspaceManager.recordLayoutOperation(
                .windowMovedToWorkspace(token: drop.sourceToken, to: target), in: source, source: .mouse
            )
            workspaceManager.recordLayoutOperation(.windowInserted(token: drop.sourceToken), in: target, source: .mouse)
            recoverSourceFocusAfterMove(
                in: source,
                preferredNodeId: plan.sourceLayout == .niri ? niriViewportState(for: source).selectedNodeId : nil
            )
        case let .swap(partner):
            workspaceManager.recordLayoutOperation(.windowsSwapped, in: source, source: .mouse)
            workspaceManager.recordLayoutOperation(.windowsSwapped, in: target, source: .mouse)
            recoverSourceFocusAfterMove(in: source, preferredToken: partner)
        }
        workspaceNavigationHandler.applySessionPatch(workspaceId: target, rememberedFocusToken: drop.sourceToken)
        guard let handle = workspaceManager.handle(for: drop.sourceToken) else { return }
        let mutation = StructuralMutation(
            sourceWorkspaceId: source,
            destinationWorkspaceId: target,
            selectedHandle: handle,
            scrollWorkspaceId: plan.targetLayout == .niri ? target : nil
        )
        let follows = heldSelection || settings.focus.followsWindowToMonitor
        workspaceNavigationHandler.finishWorkspaceMove(
            mutation,
            focusPolicy: follows ? .configured : .retainCurrent,
            focusOrigin: .pointerSelection
        )
        if mutation.scrollWorkspaceId != nil, let engine = niriEngine {
            niriLayoutHandler.startScrollAnimationIfNeeded(
                for: target,
                state: niriViewportState(for: target),
                engine: engine
            )
        }
    }

    private func admittedNiriContainerSizing(for token: WindowToken) -> NiriContainerSizingState? {
        if let detached = workspaceManager.restoreIntent(for: token)?.detachedNiriContainerSizingState {
            return detached
        }
        return workspaceManager.admissionHints(for: token)?.initialNiriContainerPrimarySpan.flatMap { span in
            niriEngine?.initialContainerSizingState(for: CGFloat(span))
        }
    }

    private func niriViewportState(for workspaceId: WorkspaceDescriptor.ID) -> ViewportState {
        workspaceManager.niriViewportState(for: workspaceId)
    }

    private static func dwindleTransferPlacement(_ placement: CrossDisplayDrop.Placement) -> DwindleTransferPlacement {
        switch placement {
        case let .dwindleBeside(target, direction):
            .beside(target, direction)
        case let .dwindleEdge(direction):
            .workspaceEdge(direction)
        case .niriNewColumn,
             .niriStack,
             .swap,
             .workspace:
            .defaultPlacement
        }
    }
}
