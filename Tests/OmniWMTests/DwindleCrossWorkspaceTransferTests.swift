// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class DwindleCrossWorkspaceTransferTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testAttachBesideAResidentAnimatesItFromItsPresentedFrame() throws {
        let engine = makeEngine()
        let target = WorkspaceDescriptor.ID()
        let residents = addTiles(count: 2, firstWindowId: 1, to: target, engine)
        let incoming = WindowToken(pid: 90, windowId: 90)

        try assertResidentsAnimate([residents[0]], in: target, engine) {
            engine.attachTransferredTile(
                DwindleTransferredTile(token: incoming),
                placement: .beside(residents[0], .down),
                in: target
            )
        }
    }

    func testAttachAtTheEdgeOfALeafRootAnimatesThePromotedResident() throws {
        let engine = makeEngine()
        let target = WorkspaceDescriptor.ID()
        let residents = addTiles(count: 1, firstWindowId: 1, to: target, engine)
        let incoming = WindowToken(pid: 90, windowId: 90)

        try assertResidentsAnimate(residents, in: target, engine) {
            engine.attachTransferredTile(
                DwindleTransferredTile(token: incoming),
                placement: .workspaceEdge(.left),
                in: target
            )
        }
    }

    func testSplitBoundaryAttachNeedsALiveSplitWithVisibleBranches() throws {
        let engine = makeEngine()
        let target = WorkspaceDescriptor.ID()
        let residents = addTiles(count: 3, firstWindowId: 1, to: target, engine)
        let root = try XCTUnwrap(engine.root(for: target))
        XCTAssertTrue(engine.canAttachTransfer(atSplitBoundary: root.id, in: target))
        XCTAssertFalse(engine.canAttachTransfer(atSplitBoundary: DwindleNodeId(), in: target))
        engine.setExcludedTokens([residents[0]], in: target)
        XCTAssertFalse(engine.canAttachTransfer(atSplitBoundary: root.id, in: target))
        engine.setExcludedTokens([], in: target)
        let incoming = WindowToken(pid: 90, windowId: 90)

        engine.attachTransferredTile(
            DwindleTransferredTile(token: incoming),
            placement: .splitBoundary(DwindleNodeId()),
            in: target
        )

        XCTAssertNotNil(engine.findNode(for: incoming, in: target))
        XCTAssertEqual(engine.windowCount(in: target), 4)
        XCTAssertEqual(engine.tileCount(in: target), 4)
    }

    func testDetachAnimatesTheTilesThatCollapseIntoItsSlot() throws {
        let engine = makeEngine()
        let source = WorkspaceDescriptor.ID()
        let tokens = addTiles(count: 3, firstWindowId: 1, to: source, engine)

        try assertResidentsAnimate([tokens[2]], in: source, engine) {
            XCTAssertNotNil(engine.detachForTransfer(token: tokens[1], wholeTile: false, from: source))
        }
        XCTAssertNil(engine.existingState(for: source)?.pendingMovementFrameSeeds[tokens[1]])
    }

    func testDetachingTheSelectedTileSelectsTheSameSuccessorAsRemoval() throws {
        func makeTree() throws -> (DwindleLayoutEngine, WorkspaceDescriptor.ID, [WindowToken]) {
            let engine = makeEngine()
            let workspaceId = WorkspaceDescriptor.ID()
            let tokens = (1 ... 3).map { WindowToken(pid: pid_t($0), windowId: $0) }
            for (token, direction) in zip(tokens, [Direction.right, .right, .up]) {
                _ = engine.setPreselection(direction, in: workspaceId)
                _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
            }
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
            let state = try XCTUnwrap(engine.existingState(for: workspaceId))
            state.selectedNodeId = try XCTUnwrap(engine.findNode(for: tokens[0], in: workspaceId)).id
            return (engine, workspaceId, tokens)
        }
        let (removed, removedWorkspace, tokens) = try makeTree()
        let (detached, detachedWorkspace, _) = try makeTree()
        let firstLeafAfterCollapse = try XCTUnwrap(removed.findNode(for: tokens[0], in: removedWorkspace)?.sibling())
            .descendToFirstLeaf().tile?.activeToken

        removed.removeWindow(token: tokens[0], from: removedWorkspace)
        XCTAssertNotNil(detached.detachForTransfer(token: tokens[0], wholeTile: false, from: detachedWorkspace))

        let expected = try XCTUnwrap(removed.selectedNode(in: removedWorkspace)?.tile?.activeToken)
        XCTAssertNotEqual(expected, firstLeafAfterCollapse)
        XCTAssertEqual(detached.selectedNode(in: detachedWorkspace)?.tile?.activeToken, expected)
    }

    private func assertResidentsAnimate(
        _ residents: [WindowToken],
        in workspaceId: WorkspaceDescriptor.ID,
        _ engine: DwindleLayoutEngine,
        mutation: () -> Void
    ) throws {
        let before = engine.presentedFrames(in: workspaceId, at: 100)
        mutation()

        var previousTargets = engine.currentFrames(in: workspaceId)
        var oldFrames = engine.presentedFrames(in: workspaceId, at: 100)
        engine.consumePendingMovementFrameSeeds(
            in: workspaceId,
            oldFrames: &oldFrames,
            previousTargetFrames: &previousTargets
        )
        let newFrames = engine.calculateLayout(for: workspaceId, screen: screen)
        engine.animateWindowMovements(
            .init(oldFrames: oldFrames, previousTargetFrames: previousTargets, newFrames: newFrames),
            in: workspaceId,
            startTime: 100,
            motion: .enabled
        )

        let start = engine.calculateAnimatedFrames(baseFrames: newFrames, in: workspaceId, at: 100)
        let end = engine.calculateAnimatedFrames(baseFrames: newFrames, in: workspaceId, at: 200)
        for token in residents {
            let beforeFrame = try XCTUnwrap(before[token])
            XCTAssertNotEqual(newFrames[token], beforeFrame, "\(token)")
            XCTAssertEqual(start[token], beforeFrame, "\(token)")
            XCTAssertEqual(end[token], newFrames[token], "\(token)")
        }
    }

    private func makeEngine() -> DwindleLayoutEngine {
        let engine = DwindleLayoutEngine()
        engine.settings.innerGap = 0
        return engine
    }

    private func addTiles(
        count: Int,
        firstWindowId: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        _ engine: DwindleLayoutEngine
    ) -> [WindowToken] {
        let tokens = (0 ..< count).map { WindowToken(pid: pid_t(firstWindowId + $0), windowId: firstWindowId + $0) }
        for token in tokens {
            _ = engine.setPreselection(.right, in: workspaceId)
            _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
        }
        _ = engine.calculateLayout(for: workspaceId, screen: screen)
        return tokens
    }
}
