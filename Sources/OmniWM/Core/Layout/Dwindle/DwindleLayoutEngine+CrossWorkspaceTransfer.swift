// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

struct DwindleTransferredTile {
    let tile: DwindleTile
    let excludedTokens: Set<WindowToken>

    init(tile: DwindleTile, excludedTokens: Set<WindowToken> = []) {
        self.tile = tile
        self.excludedTokens = excludedTokens
    }

    init(token: WindowToken, excluded: Bool = false) {
        self.init(tile: DwindleTile(token: token), excludedTokens: excluded ? [token] : [])
    }
}

enum DwindleTransferPlacement: Equatable {
    case beside(WindowToken, Direction)
    case workspaceEdge(Direction)
    case defaultPlacement
}

extension DwindleLayoutEngine {
    func visibleTiles(in workspaceId: WorkspaceDescriptor.ID) -> (any: Bool, fullscreen: Bool) {
        guard let state = existingState(for: workspaceId) else { return (false, false) }
        var hasVisibleTile = false
        for leaf in state.root.collectAllLeaves() {
            guard let member = visibleMember(in: leaf.tile, excluding: state.excludedTokens) else { continue }
            if member.isFullscreen { return (true, true) }
            hasVisibleTile = true
        }
        return (hasVisibleTile, false)
    }

    func tile(containing token: WindowToken, in workspaceId: WorkspaceDescriptor.ID) -> DwindleTile? {
        existingState(for: workspaceId)?.leafByToken[token]?.tile
    }

    func transferTile(
        containing token: WindowToken,
        wholeTile: Bool,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> DwindleTransferredTile? {
        guard let state = existingState(for: workspaceId), let tile = state.leafByToken[token]?.tile else {
            return nil
        }
        guard wholeTile || tile.members.count == 1 else {
            return DwindleTransferredTile(token: token, excluded: state.excludedTokens.contains(token))
        }
        return DwindleTransferredTile(
            tile: tile,
            excludedTokens: state.excludedTokens.intersection(tile.members.map(\.token))
        )
    }

    func detachForTransfer(
        token: WindowToken,
        wholeTile: Bool,
        from workspaceId: WorkspaceDescriptor.ID
    ) -> DwindleTransferredTile? {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId),
              let leaf = state.leafByToken[token],
              let tile = leaf.tile,
              let memberIndex = tile.memberIndex(for: token)
        else { return nil }

        seedMovementFramesFromPresentedLeaves(in: state)
        guard wholeTile || tile.members.count == 1 else {
            _ = tile.remove(at: memberIndex)
            state.leafByToken.removeValue(forKey: token)
            state.pendingMovementFrameSeeds.removeValue(forKey: token)
            let excluded = state.excludedTokens.remove(token) != nil
            return DwindleTransferredTile(token: token, excluded: excluded)
        }

        let successorToken = state.selectedNodeId == leaf.id
            ? removalSuccessorToken(for: token, in: workspaceId)
            : nil
        let tokens = tile.members.map(\.token)
        let excluded = state.excludedTokens.intersection(tokens)
        for member in tokens {
            state.leafByToken.removeValue(forKey: member)
            state.pendingMovementFrameSeeds.removeValue(forKey: member)
            state.excludedTokens.remove(member)
        }
        leaf.kind = .leaf(tile: nil)
        leaf.cachedContentFrame = nil
        state.tileCount -= 1
        cleanupAfterRemoval(leaf, state: state, successorToken: successorToken)
        if state.leafByToken.isEmpty {
            state.selectedNodeId = nil
        }
        return DwindleTransferredTile(tile: tile, excludedTokens: excluded)
    }

    func attachTransferredTile(
        _ transferred: DwindleTransferredTile,
        placement: DwindleTransferPlacement,
        in workspaceId: WorkspaceDescriptor.ID
    ) {
        assertSanctionedMutation()
        let state = ensureState(for: workspaceId)
        seedMovementFramesFromPresentedLeaves(in: state)
        _ = exitFullscreen(in: workspaceId)
        let tile = transferred.tile
        let leaf: DwindleNode = switch placement {
        case let .beside(targetToken, direction):
            state.leafByToken[targetToken].map { target in
                splitLeaf(
                    target,
                    tiles: (new: tile, existing: target.tile),
                    state: state,
                    activeWindowFrame: nil,
                    preselectedDirection: direction,
                    splitRatio: 1
                )
            } ?? attachAtDefaultPlacement(tile, state: state, in: workspaceId)
        case let .workspaceEdge(direction) where state.tileCount > 0:
            attachAtWorkspaceEdge(tile, direction: direction, state: state)
        case .workspaceEdge,
             .defaultPlacement:
            attachAtDefaultPlacement(tile, state: state, in: workspaceId)
        }
        for member in tile.members {
            state.leafByToken[member.token] = leaf
        }
        state.excludedTokens.formUnion(transferred.excludedTokens)
        state.selectedNodeId = leaf.id
    }

    func replaceSlot(
        of partnerToken: WindowToken,
        wholeTile: Bool,
        with incoming: DwindleTransferredTile,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> DwindleTransferredTile? {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId),
              let leaf = state.leafByToken[partnerToken],
              let tile = leaf.tile
        else { return nil }

        let outgoing: DwindleTransferredTile
        if wholeTile || tile.members.count == 1 {
            let tokens = tile.members.map(\.token)
            outgoing = DwindleTransferredTile(tile: tile, excludedTokens: state.excludedTokens.intersection(tokens))
            for member in tokens {
                state.leafByToken.removeValue(forKey: member)
                state.pendingMovementFrameSeeds.removeValue(forKey: member)
                state.excludedTokens.remove(member)
            }
            leaf.kind = .leaf(tile: incoming.tile)
        } else {
            guard incoming.tile.members.count == 1 else { return nil }
            let incomingToken = incoming.tile.activeToken
            let excluded = state.excludedTokens.remove(partnerToken) != nil
            outgoing = DwindleTransferredTile(token: partnerToken, excluded: excluded)
            state.leafByToken.removeValue(forKey: partnerToken)
            state.pendingMovementFrameSeeds.removeValue(forKey: partnerToken)
            tile.rekey(from: partnerToken, to: incomingToken)
        }
        for member in leaf.tile?.members ?? [] {
            state.leafByToken[member.token] = leaf
        }
        state.excludedTokens.formUnion(incoming.excludedTokens)
        state.selectedNodeId = leaf.id
        return outgoing
    }

    private func attachAtWorkspaceEdge(
        _ tile: DwindleTile,
        direction: Direction,
        state: DwindleWorkspaceState
    ) -> DwindleNode {
        let leaf = DwindleNode(kind: .leaf(tile: tile))
        let root = state.root
        let remainder = DwindleNode(kind: root.kind)
        for child in root.children {
            remainder.appendChild(child)
        }
        for member in remainder.tile?.members ?? [] {
            state.leafByToken[member.token] = remainder
        }
        root.kind = .split(orientation: direction.dwindleOrientation, ratio: 1)
        if direction == .left || direction == .down {
            root.replaceChildren(first: leaf, second: remainder)
        } else {
            root.replaceChildren(first: remainder, second: leaf)
        }
        state.tileCount += 1
        return leaf
    }

    private func attachAtDefaultPlacement(
        _ tile: DwindleTile,
        state: DwindleWorkspaceState,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> DwindleNode {
        if case .leaf(nil) = state.root.kind {
            state.root.kind = .leaf(tile: tile)
            state.tileCount = 1
            return state.root
        }
        let target = selectedNode(in: workspaceId).flatMap { $0.isLeaf ? $0 : nil }
            ?? state.root.descendToFirstLeaf()
        let leaf = splitLeaf(
            target,
            tiles: (new: tile, existing: target.tile),
            state: state,
            activeWindowFrame: nil,
            preselectedDirection: state.preselection
        )
        state.preselection = nil
        return leaf
    }
}
