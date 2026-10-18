// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
import QuartzCore

extension DwindleLayoutEngine {
    private struct SplitMoveGeometry {
        let frame: CGRect?
        let hasPeer: Bool
        var target: DwindleMoveTarget?
    }

    func canInsertAtSplitBoundary(
        token: WindowToken,
        splitId: DwindleNodeId,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard canInsertAtWorkspaceEdge(token: token, in: workspaceId),
              let state = existingState(for: workspaceId),
              let source = state.leafByToken[token],
              let split = findNodeById(splitId, in: state.root),
              split.children.count == 2
        else { return false }
        return split.children.allSatisfy { branch in
            branch.collectAllLeaves().contains { leaf in
                leaf !== source && leaf.tile.flatMap { visibleMember(in: $0, excluding: state.excludedTokens) } != nil
            }
        }
    }

    @discardableResult
    func insertLeafTile(
        of token: WindowToken,
        betweenChildrenOf splitId: DwindleNodeId,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        assertSanctionedMutation()
        guard canInsertAtSplitBoundary(token: token, splitId: splitId, in: workspaceId),
              let state = existingState(for: workspaceId),
              let source = state.leafByToken[token],
              let split = findNodeById(splitId, in: state.root),
              let orientation = split.splitOrientation,
              let first = split.firstChild(), let second = split.secondChild(),
              let destination = source.sibling() === split ? source.parent : split
        else { return false }

        if let sibling = source.sibling(), let tile = sibling.tile,
           let frame = sibling.presentedFrame(at: animationClock?.now() ?? CACurrentMediaTime())
        {
            for member in tile.members where state.pendingMovementFrameSeeds[member.token] == nil {
                state.pendingMovementFrameSeeds[member.token] = frame
            }
        }
        cleanupAfterRemoval(source, state: state)

        let inserted = DwindleNode(kind: .split(orientation: orientation, ratio: 1))
        destination.replaceChildren(first: first, second: inserted)
        inserted.replaceChildren(first: source, second: second)
        state.selectedNodeId = source.id
        return true
    }

    func splitBoundaryMoveTarget(
        at point: CGPoint,
        for token: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        time: TimeInterval
    ) -> DwindleMoveTarget? {
        guard canInsertAtWorkspaceEdge(token: token, in: workspaceId),
              let state = existingState(for: workspaceId), let source = state.leafByToken[token]
        else { return nil }
        return splitMoveGeometry(
            at: point, in: state.root, source: source, excludedTokens: state.excludedTokens, time: time
        ).target
    }

    private func splitMoveGeometry(
        at point: CGPoint,
        in node: DwindleNode,
        source: DwindleNode,
        excludedTokens: Set<WindowToken>,
        time: TimeInterval
    ) -> SplitMoveGeometry {
        if let tile = node.tile, visibleMember(in: tile, excluding: excludedTokens) != nil {
            return SplitMoveGeometry(frame: node.presentedFrame(at: time), hasPeer: node !== source, target: nil)
        }
        guard let orientation = node.splitOrientation,
              let first = node.firstChild(), let second = node.secondChild()
        else { return SplitMoveGeometry(frame: nil, hasPeer: false, target: nil) }
        let firstGeometry = splitMoveGeometry(
            at: point,
            in: first,
            source: source,
            excludedTokens: excludedTokens,
            time: time
        )
        let secondGeometry = splitMoveGeometry(
            at: point,
            in: second,
            source: source,
            excludedTokens: excludedTokens,
            time: time
        )
        var frame = firstGeometry.frame
        if let next = secondGeometry.frame { frame = frame?.union(next) ?? next }
        var result = SplitMoveGeometry(
            frame: frame,
            hasPeer: firstGeometry.hasPeer || secondGeometry.hasPeer,
            target: firstGeometry.target ?? secondGeometry.target
        )
        guard result.target == nil, firstGeometry.hasPeer, secondGeometry.hasPeer,
              let firstFrame = firstGeometry.frame, let secondFrame = secondGeometry.frame
        else { return result }
        let horizontal = orientation == .horizontal
        let band = splitBoundaryBand(between: firstFrame, and: secondFrame, horizontal: horizontal)
        if band.width > 0, band.height > 0, band.contains(point) {
            result.target = .splitBoundary(
                node.id, frame: WindowMoveGeometry.targetFrame(in: secondFrame, direction: horizontal ? .left : .down)
            )
        }
        return result
    }

    private func splitBoundaryBand(between firstFrame: CGRect, and secondFrame: CGRect, horizontal: Bool) -> CGRect {
        let boundary = horizontal
            ? (firstFrame.maxX + secondFrame.minX) / 2
            : (firstFrame.maxY + secondFrame.minY) / 2
        let tolerance = min(12, (horizontal
                ? min(firstFrame.width, secondFrame.width)
                : min(firstFrame.height, secondFrame.height)) / 10)
        return horizontal
            ? CGRect(
                x: boundary - tolerance,
                y: max(firstFrame.minY, secondFrame.minY),
                width: tolerance * 2,
                height: min(firstFrame.maxY, secondFrame.maxY) - max(firstFrame.minY, secondFrame.minY)
            )
            : CGRect(
                x: max(firstFrame.minX, secondFrame.minX),
                y: boundary - tolerance,
                width: min(firstFrame.maxX, secondFrame.maxX) - max(firstFrame.minX, secondFrame.minX),
                height: tolerance * 2
            )
    }
}
