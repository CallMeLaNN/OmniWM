// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class DwindleRootPromotionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let first = WindowToken(pid: 1, windowId: 1)
    private let second = WindowToken(pid: 2, windowId: 2)
    private let third = WindowToken(pid: 3, windowId: 3)
    private let fourth = WindowToken(pid: 4, windowId: 4)

    func testRootChildStackPromotionPreservesLayoutForEitherActiveMember() throws {
        for stable in [false, true] {
            let (engine, workspace) = makeNestedEngine()
            XCTAssertTrue(engine.groupWindow(direction: .left, in: workspace))
            let root = try XCTUnwrap(engine.root(for: workspace))
            let group = try XCTUnwrap(engine.tileSnapshot(for: third, in: workspace))
            XCTAssertEqual(root.splitOrientation, .vertical)
            XCTAssertEqual(root.children.count, 2)
            XCTAssertEqual(root.firstChild()?.tile?.id, group.id)
            XCTAssertEqual(root.secondChild()?.windowToken, second)
            XCTAssertEqual(group.members.map(\.token), [first, third])
            XCTAssertEqual(group.activeToken, third)
            XCTAssertEqual(engine.tileCount(in: workspace), 2)
            XCTAssertEqual(engine.windowCount(in: workspace), 3)

            try assertPromotionDoesNotChange(engine, in: workspace, stable: stable)

            XCTAssertEqual(engine.activateWindowOutcome(first, in: workspace), .activated)
            XCTAssertEqual(engine.tileSnapshot(for: first, in: workspace)?.id, group.id)
            try assertPromotionDoesNotChange(engine, in: workspace, stable: stable)
        }
    }

    func testNestedSingleTilePromotionHonorsStableRootSide() throws {
        for stable in [false, true] {
            let (engine, workspace) = makeNestedEngine()
            let root = try XCTUnwrap(engine.root(for: workspace))
            let ancestor = try XCTUnwrap(root.firstChild())
            let leaf = try XCTUnwrap(engine.findNode(for: third, in: workspace))
            let frames = engine.calculateLayout(for: workspace, screen: screen)
            XCTAssertEqual(leaf.parent?.id, ancestor.id)

            XCTAssertTrue(engine.moveSelectionToRoot(stable: stable, in: workspace))

            XCTAssertEqual(engine.root(for: workspace)?.id, root.id)
            XCTAssertEqual(root.children.map(\.id), stable ? [leaf.id, ancestor.id] : [ancestor.id, leaf.id])
            XCTAssertEqual(ancestor.children.compactMap(\.windowToken), [first, second])
            XCTAssertEqual(leaf.parent?.id, root.id)
            XCTAssertEqual(engine.findNode(for: second, in: workspace)?.parent?.id, ancestor.id)
            XCTAssertEqual(engine.selectedNode(in: workspace)?.id, leaf.id)
            XCTAssertEqual(engine.activeToken(in: workspace), third)
            XCTAssertNotEqual(engine.calculateLayout(for: workspace, screen: screen), frames)
            try assertPromotionDoesNotChange(engine, in: workspace, stable: stable)
        }
    }

    func testNestedStackPromotionPreservesGroupAndHonorsStableRootSide() throws {
        for stable in [false, true] {
            let (engine, workspace) = makeNestedEngine()
            XCTAssertTrue(engine.setPreselection(.right, in: workspace))
            engine.addWindow(token: fourth, to: workspace, activeWindowFrame: nil)
            _ = engine.calculateLayout(for: workspace, screen: screen)
            XCTAssertTrue(engine.groupWindow(direction: .left, in: workspace))
            let frames = engine.calculateLayout(for: workspace, screen: screen)
            let group = try XCTUnwrap(engine.tileSnapshot(for: fourth, in: workspace))
            let root = try XCTUnwrap(engine.root(for: workspace))
            let ancestor = try XCTUnwrap(root.firstChild())
            let leaf = try XCTUnwrap(engine.findNode(for: fourth, in: workspace))
            XCTAssertEqual(group.members.map(\.token), [third, fourth])
            XCTAssertEqual(group.activeToken, fourth)
            XCTAssertEqual(leaf.parent?.id, ancestor.id)

            XCTAssertTrue(engine.moveSelectionToRoot(stable: stable, in: workspace))

            let promoted = try XCTUnwrap(engine.tileSnapshot(for: fourth, in: workspace))
            XCTAssertEqual(promoted.id, group.id)
            XCTAssertEqual(promoted.members, group.members)
            XCTAssertEqual(promoted.activeIndex, group.activeIndex)
            XCTAssertEqual(engine.findNode(for: third, in: workspace)?.id, leaf.id)
            XCTAssertEqual(root.children.map(\.id), stable ? [leaf.id, ancestor.id] : [ancestor.id, leaf.id])
            XCTAssertEqual(ancestor.children.compactMap(\.windowToken), [first, second])
            XCTAssertEqual(leaf.parent?.id, root.id)
            XCTAssertEqual(engine.activeToken(in: workspace), fourth)
            XCTAssertEqual(engine.tileCount(in: workspace), 3)
            XCTAssertEqual(engine.windowCount(in: workspace), 4)
            XCTAssertNotEqual(engine.calculateLayout(for: workspace, screen: screen), frames)
            try assertPromotionDoesNotChange(engine, in: workspace, stable: stable)
        }
    }

    func testSingleWindowAndSingleGroupRootsCannotPromote() throws {
        for stable in [false, true] {
            let engine = DwindleLayoutEngine()
            let workspace = WorkspaceDescriptor.ID()
            engine.addWindow(token: first, to: workspace, activeWindowFrame: nil)
            try assertPromotionDoesNotChange(engine, in: workspace, stable: stable)

            XCTAssertTrue(engine.setPreselection(.right, in: workspace))
            engine.addWindow(token: second, to: workspace, activeWindowFrame: nil)
            _ = engine.calculateLayout(for: workspace, screen: screen)
            XCTAssertTrue(engine.groupWindow(direction: .left, in: workspace))
            XCTAssertTrue(try XCTUnwrap(engine.root(for: workspace)).isLeaf)
            XCTAssertEqual(engine.tileCount(in: workspace), 1)
            XCTAssertEqual(engine.windowCount(in: workspace), 2)
            try assertPromotionDoesNotChange(engine, in: workspace, stable: stable)
        }
    }

    private func makeNestedEngine() -> (DwindleLayoutEngine, WorkspaceDescriptor.ID) {
        let engine = DwindleLayoutEngine()
        let workspace = WorkspaceDescriptor.ID()
        engine.addWindow(token: first, to: workspace, activeWindowFrame: nil)
        XCTAssertTrue(engine.setPreselection(.up, in: workspace))
        engine.addWindow(token: second, to: workspace, activeWindowFrame: nil)
        XCTAssertEqual(engine.activateWindowOutcome(first, in: workspace), .selected)
        XCTAssertTrue(engine.setPreselection(.right, in: workspace))
        engine.addWindow(token: third, to: workspace, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: workspace, screen: screen)
        return (engine, workspace)
    }

    private func assertPromotionDoesNotChange(
        _ engine: DwindleLayoutEngine,
        in workspace: WorkspaceDescriptor.ID,
        stable: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let root = try XCTUnwrap(engine.root(for: workspace), file: file, line: line)
        let topology = Topology(root)
        let tokens = root.collectAllWindows()
        let frames = engine.calculateLayout(for: workspace, screen: screen)
        let tiles = tokens.map { engine.tileSnapshot(for: $0, in: workspace) }
        let selection = engine.selectedNode(in: workspace)?.id
        let tileCount = engine.tileCount(in: workspace)

        XCTAssertFalse(engine.moveSelectionToRoot(stable: stable, in: workspace), file: file, line: line)

        XCTAssertEqual(engine.calculateLayout(for: workspace, screen: screen), frames, file: file, line: line)
        let resultingRoot = try XCTUnwrap(engine.root(for: workspace), file: file, line: line)
        XCTAssertEqual(Topology(resultingRoot), topology, file: file, line: line)
        XCTAssertEqual(tokens.map { engine.tileSnapshot(for: $0, in: workspace) }, tiles, file: file, line: line)
        XCTAssertEqual(engine.selectedNode(in: workspace)?.id, selection, file: file, line: line)
        XCTAssertEqual(engine.tileCount(in: workspace), tileCount, file: file, line: line)
        XCTAssertEqual(engine.windowCount(in: workspace), tokens.count, file: file, line: line)
    }

    private struct Topology: Equatable {
        let id: DwindleNodeId
        let parentId: DwindleNodeId?
        let orientation: DwindleOrientation?
        let ratio: CGFloat?
        let children: [Topology]

        init(_ node: DwindleNode) {
            id = node.id
            parentId = node.parent?.id
            orientation = node.splitOrientation
            ratio = node.splitRatio
            children = node.children.map(Topology.init)
        }
    }
}
