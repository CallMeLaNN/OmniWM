// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

final class NiriGatherPlanTests: XCTestCase {
    private let geometry = NiriSizingGeometry(
        workingFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
        gaps: 10,
        orientation: .horizontal
    )

    private let firstSource = WorkspaceDescriptor.ID()
    private let secondSource = WorkspaceDescriptor.ID()
    private let destination = WorkspaceDescriptor.ID()

    private func token(_ id: Int) -> WindowToken {
        WindowToken(pid: 72_000, windowId: id)
    }

    @discardableResult
    private func add(
        _ id: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        in engine: NiriLayoutEngine,
        stackingOnto stackTarget: Int? = nil,
        minHeight: CGFloat = 1
    ) -> NiriWindow {
        let node = engine.addWindow(token: token(id), to: workspaceId, afterSelection: nil)
        engine.updateWindowConstraints(
            for: token(id),
            constraints: WindowSizeConstraints(
                minSize: CGSize(width: 1, height: minHeight),
                maxSize: .zero,
                isFixed: false
            ),
            in: workspaceId,
            motion: .disabled
        )
        if let stackTarget,
           let targetNode = engine.findNode(for: token(stackTarget), in: workspaceId),
           let targetColumn = engine.findColumn(containing: targetNode, in: workspaceId),
           let sourceColumn = engine.findColumn(containing: node, in: workspaceId)
        {
            engine.moveWindowToColumn(node, from: sourceColumn, to: targetColumn, in: workspaceId)
            sourceColumn.remove()
        }
        return node
    }

    private func layout(_ workspaceId: WorkspaceDescriptor.ID, in engine: NiriLayoutEngine) -> [[Int]] {
        engine.columns(in: workspaceId).map { $0.windowNodes.map(\.token.windowId) }
    }

    private func column(of id: Int, in engine: NiriLayoutEngine) throws -> NiriContainer {
        let node = try XCTUnwrap(engine.findNode(for: token(id), in: destination))
        return try XCTUnwrap(engine.findColumn(containing: node, in: destination))
    }

    private func request(
        _ ids: [Int],
        sources: [Int: WorkspaceDescriptor.ID],
        geometry: NiriSizingGeometry? = nil,
        nativeFocus: Int? = nil
    ) -> NiriGatherRequest {
        NiriGatherRequest(
            tokens: ids.map(token),
            sourceWorkspaceIds: Dictionary(uniqueKeysWithValues: sources.map { (token($0.key), $0.value) }),
            destinationWorkspaceId: destination,
            geometry: geometry ?? self.geometry,
            nativeFocusToken: nativeFocus.map(token)
        )
    }

    private struct UnexpectedPlanning: Error {
        let planning: NiriGatherPlanning
    }

    private func readyPlan(
        _ engine: NiriLayoutEngine,
        _ request: NiriGatherRequest,
        anchor: NiriWindow?
    ) throws -> NiriGatherPlan {
        let planning = engine.planGather(request, selections: anchor.map { [destination: $0.id] } ?? [:])
        guard case let .ready(plan) = planning else { throw UnexpectedPlanning(planning: planning) }
        return plan
    }

    private func assertApplied(_ plan: NiriGatherPlan, in engine: NiriLayoutEngine) {
        engine.applyGather(plan)
        for patch in plan.workspaces {
            XCTAssertEqual(engine.columns(in: patch.workspaceId).map { $0.windowNodes.map(\.id) }, patch.finalColumns)
        }
    }

    func testMultiRootGatherInsertsAfterTheSurvivingOutsideAnchorColumn() throws {
        let engine = NiriLayoutEngine()
        let firstMoved = add(1, to: firstSource, in: engine)
        let unrelatedFirst = add(11, to: firstSource, in: engine)
        add(2, to: firstSource, in: engine, stackingOnto: 11)
        add(3, to: secondSource, in: engine)
        let unrelatedSecond = add(12, to: secondSource, in: engine)
        let unrelatedDestination = add(13, to: destination, in: engine)
        add(4, to: destination, in: engine)
        XCTAssertEqual(layout(firstSource, in: engine), [[1], [11, 2]])
        XCTAssertEqual(layout(destination, in: engine), [[13], [4]])

        let unrelatedFirstColumn = try XCTUnwrap(engine.findColumn(containing: unrelatedFirst, in: firstSource))
        let unrelatedDestinationColumn = try column(of: 13, in: engine)
        unrelatedDestinationColumn.width = .proportion(0.75)
        let gatherRequest = request(
            [1, 3, 4, 2],
            sources: [1: firstSource, 2: firstSource, 3: secondSource, 4: destination]
        )

        let planning = engine.planGather(
            gatherRequest,
            selections: [
                firstSource: firstMoved.id,
                secondSource: unrelatedSecond.id,
                destination: unrelatedDestination.id
            ]
        )
        guard case let .ready(plan) = planning else {
            return XCTFail("expected a ready plan, got \(planning)")
        }
        XCTAssertEqual(plan.affectedWorkspaceIds, [destination, firstSource, secondSource])
        XCTAssertEqual(plan.placement, .newColumn(after: unrelatedDestinationColumn.id))
        XCTAssertEqual(plan.movedTokens, [1, 3, 4, 2].map(token))
        XCTAssertEqual(plan.selection(in: firstSource), unrelatedFirst.id)
        XCTAssertEqual(plan.selection(in: secondSource), unrelatedSecond.id)
        XCTAssertEqual(plan.selection(in: destination), unrelatedDestination.id)
        XCTAssertEqual(plan.activeColumnIndex(in: destination), 0)
        XCTAssertEqual(plan.activeColumnIndex(in: firstSource), 0)
        XCTAssertEqual(plan.gatheredActiveTileIndex, 0)
        XCTAssertEqual(layout(firstSource, in: engine), [[1], [11, 2]], "planning must not mutate")
        XCTAssertEqual(engine.states.count, 3)

        assertApplied(plan, in: engine)

        XCTAssertEqual(layout(destination, in: engine), [[13], [1, 3, 4, 2]])
        XCTAssertEqual(layout(firstSource, in: engine), [[11]])
        XCTAssertEqual(layout(secondSource, in: engine), [[12]])
        XCTAssertTrue(engine.findNode(for: token(1), in: destination) === firstMoved)
        XCTAssertNil(engine.findNode(for: token(1), in: firstSource))
        XCTAssertNil(engine.findNode(for: token(3), in: secondSource))
        XCTAssertEqual(engine.workspaceIds(containing: token(2)), [destination])
        XCTAssertTrue(engine.findColumn(containing: unrelatedFirst, in: firstSource) === unrelatedFirstColumn)
        XCTAssertTrue(try column(of: 13, in: engine) === unrelatedDestinationColumn)
        XCTAssertEqual(unrelatedDestinationColumn.width, .proportion(0.75))
        XCTAssertEqual(engine.columns(in: destination).last?.displayMode, .normal)
        XCTAssertEqual(
            engine.planGather(
                gatherRequest.reassigned(to: destination),
                selections: [destination: unrelatedDestination.id]
            ),
            .unchanged
        )
    }

    func testFullySelectedAnchorColumnIsReusedInPlaceAndTabbedColumnsAlwaysFit() throws {
        let engine = NiriLayoutEngine()
        add(5, to: destination, in: engine)
        add(1, to: destination, in: engine, minHeight: 500)
        add(2, to: destination, in: engine, stackingOnto: 1, minHeight: 500)
        add(13, to: destination, in: engine)
        add(3, to: firstSource, in: engine, minHeight: 500)
        let anchorColumn = try column(of: 1, in: engine)
        anchorColumn.displayMode = .tabbed
        anchorColumn.width = .proportion(0.4)
        anchorColumn.setActiveTileIdx(1)
        let anchor = try XCTUnwrap(engine.findNode(for: token(2), in: destination))

        let plan = try readyPlan(
            engine,
            request([2, 3, 1], sources: [1: destination, 2: destination, 3: firstSource]),
            anchor: anchor
        )
        XCTAssertEqual(plan.placement, .reuse(anchorColumn.id))
        XCTAssertEqual(plan.movedTokens, [2, 3, 1].map(token))
        XCTAssertEqual(plan.selection(in: destination), anchor.id)

        assertApplied(plan, in: engine)
        XCTAssertTrue(try column(of: 1, in: engine) === anchorColumn)
        XCTAssertEqual(layout(destination, in: engine), [[5], [2, 3, 1], [13]])
        XCTAssertEqual(anchorColumn.displayMode, .tabbed)
        XCTAssertEqual(anchorColumn.width, .proportion(0.4))
        XCTAssertEqual(anchorColumn.activeTileIdx, 0)
        XCTAssertEqual(anchorColumn.windowNodes.map(\.isHiddenInTabbedMode), [false, true, true])
        XCTAssertEqual(layout(firstSource, in: engine), [])
    }

    func testPartiallySelectedAnchorColumnKeepsUnlistedSurvivorsAfterTheNewColumn() throws {
        let engine = NiriLayoutEngine()
        add(5, to: destination, in: engine)
        let anchor = add(1, to: destination, in: engine)
        add(9, to: destination, in: engine, stackingOnto: 1)
        add(6, to: destination, in: engine)
        add(3, to: firstSource, in: engine)
        let survivorColumn = try column(of: 9, in: engine)
        survivorColumn.width = .proportion(0.3)
        let unrelatedColumns = try [5, 6].map { try column(of: $0, in: engine) }

        let plan = try readyPlan(
            engine,
            request([1, 3], sources: [1: destination, 3: firstSource]),
            anchor: anchor
        )
        XCTAssertEqual(plan.placement, .newColumn(after: unrelatedColumns[0].id))
        XCTAssertEqual(plan.selection(in: destination), anchor.id)
        XCTAssertEqual(plan.activeColumnIndex(in: destination), 1)

        assertApplied(plan, in: engine)
        XCTAssertEqual(layout(destination, in: engine), [[5], [1, 3], [9], [6]])
        XCTAssertTrue(try column(of: 9, in: engine) === survivorColumn)
        XCTAssertEqual(survivorColumn.width, .proportion(0.3))
        XCTAssertTrue(try column(of: 1, in: engine) !== survivorColumn)
        XCTAssertEqual(
            try [5, 6].map { try column(of: $0, in: engine) }.map(ObjectIdentifier.init),
            unrelatedColumns.map(ObjectIdentifier.init)
        )
    }

    func testPlacementUsesSurvivingColumnIdentitiesAfterSelectedColumnsAreRemoved() throws {
        let engine = NiriLayoutEngine()
        add(1, to: destination, in: engine)
        add(2, to: destination, in: engine)
        let outsideAnchor = add(5, to: destination, in: engine)
        add(6, to: destination, in: engine)
        let unrelatedColumns = try [5, 6].map { try column(of: $0, in: engine) }

        let outsidePlan = try readyPlan(
            engine,
            request([1, 2], sources: [1: destination, 2: destination]),
            anchor: outsideAnchor
        )
        XCTAssertEqual(outsidePlan.patch(in: destination)?.finalColumns.count, 3)
        assertApplied(outsidePlan, in: engine)
        XCTAssertEqual(layout(destination, in: engine), [[5], [1, 2], [6]])
        XCTAssertEqual(
            try [5, 6].map { try column(of: $0, in: engine) }.map(ObjectIdentifier.init),
            unrelatedColumns.map(ObjectIdentifier.init)
        )

        let partialEngine = NiriLayoutEngine()
        add(1, to: destination, in: partialEngine)
        add(7, to: destination, in: partialEngine)
        add(9, to: destination, in: partialEngine)
        let partialAnchor = add(3, to: destination, in: partialEngine, stackingOnto: 9)
        add(8, to: destination, in: partialEngine)

        let partialPlan = try readyPlan(
            partialEngine,
            request([1, 3], sources: [1: destination, 3: destination]),
            anchor: partialAnchor
        )
        assertApplied(partialPlan, in: partialEngine)
        XCTAssertEqual(layout(destination, in: partialEngine), [[7], [1, 3], [9], [8]])
    }

    func testWithoutATiledAnchorTheNewColumnLeadsAndAFullyListedLeadingColumnIsNotReused() throws {
        let engine = NiriLayoutEngine()
        add(1, to: destination, in: engine)
        add(2, to: destination, in: engine, stackingOnto: 1)
        add(13, to: destination, in: engine)
        let leading = try column(of: 1, in: engine)
        leading.displayMode = .tabbed
        leading.width = .proportion(0.4)
        let gatherRequest = request([2, 1], sources: [1: destination, 2: destination])

        XCTAssertEqual(
            engine.planGather(gatherRequest, selections: [destination: NodeId()]),
            engine.planGather(gatherRequest, selections: [:])
        )
        let plan = try readyPlan(engine, gatherRequest, anchor: nil)
        XCTAssertEqual(plan.placement, .newColumn(after: nil))
        XCTAssertEqual(plan.selection(in: destination), engine.findNode(for: token(2), in: destination)?.id)

        assertApplied(plan, in: engine)
        XCTAssertEqual(layout(destination, in: engine), [[2, 1], [13]])
        let gathered = try column(of: 1, in: engine)
        XCTAssertTrue(gathered !== leading)
        XCTAssertEqual(gathered.displayMode, .normal)
        XCTAssertNotEqual(gathered.width, .proportion(0.4))
    }

    func testAlreadyMatchingColumnAtTheComputedSlotIsUnchanged() throws {
        let engine = NiriLayoutEngine()
        let outsideAnchor = add(5, to: destination, in: engine)
        add(1, to: destination, in: engine)
        let member = add(2, to: destination, in: engine, stackingOnto: 1)
        let pair = request([1, 2], sources: [1: destination, 2: destination])

        XCTAssertEqual(engine.planGather(pair, selections: [destination: outsideAnchor.id]), .unchanged)
        XCTAssertEqual(engine.planGather(pair, selections: [destination: member.id]), .unchanged)
        guard case .ready = engine.planGather(pair, selections: [:]) else {
            return XCTFail("without an anchor the matching column must move to the leading slot")
        }

        let leadingEngine = NiriLayoutEngine()
        add(1, to: destination, in: leadingEngine)
        add(2, to: destination, in: leadingEngine, stackingOnto: 1)
        add(9, to: destination, in: leadingEngine, stackingOnto: 1)
        add(5, to: destination, in: leadingEngine)
        XCTAssertEqual(
            leadingEngine.planGather(
                request([1, 2, 9], sources: [1: destination, 2: destination, 9: destination]),
                selections: [:]
            ),
            .unchanged
        )
        let partialAnchor = try XCTUnwrap(leadingEngine.findNode(for: token(1), in: destination))
        guard case .ready = leadingEngine.planGather(
            request([1, 2], sources: [1: destination, 2: destination]),
            selections: [destination: partialAnchor.id]
        ) else {
            return XCTFail("a partially selected anchor column is split, never unchanged")
        }
    }

    func testGatheredNativeFocusBecomesTheSelectedActiveTab() throws {
        let engine = NiriLayoutEngine()
        let anchor = add(1, to: destination, in: engine)
        add(2, to: destination, in: engine, stackingOnto: 1)
        add(5, to: destination, in: engine)
        let focused = add(3, to: firstSource, in: engine)
        let sourceSurvivor = add(4, to: firstSource, in: engine)
        let anchorColumn = try column(of: 1, in: engine)
        anchorColumn.displayMode = .tabbed

        let planning = engine.planGather(
            request([2, 1, 3], sources: [1: destination, 2: destination, 3: firstSource], nativeFocus: 3),
            selections: [destination: anchor.id, firstSource: focused.id]
        )
        guard case let .ready(plan) = planning else { return XCTFail("expected ready, got \(planning)") }
        XCTAssertEqual(plan.placement, .reuse(anchorColumn.id))
        XCTAssertEqual(plan.selection(in: destination), focused.id)
        XCTAssertEqual(plan.gatheredActiveTileIndex, 2)
        XCTAssertEqual(plan.selection(in: firstSource), sourceSurvivor.id)

        assertApplied(plan, in: engine)
        XCTAssertEqual(layout(destination, in: engine), [[2, 1, 3], [5]])
        XCTAssertEqual(anchorColumn.activeTileIdx, 2)
        XCTAssertEqual(anchorColumn.windowNodes.map(\.isHiddenInTabbedMode), [true, true, false])
        XCTAssertEqual(layout(firstSource, in: engine), [[4]])
    }

    func testEmptyDestinationIsPlannedWithoutAllocationAndSingletonIsolates() throws {
        let engine = NiriLayoutEngine()
        let moved = add(1, to: firstSource, in: engine)
        add(2, to: firstSource, in: engine, stackingOnto: 1)
        let gatherRequest = request([1], sources: [1: firstSource])

        let planning = engine.planGather(gatherRequest, selections: [firstSource: moved.id])
        XCTAssertNil(engine.states[destination], "planning must not allocate destination state")
        guard case let .ready(plan) = planning else { return XCTFail("expected ready, got \(planning)") }
        XCTAssertEqual(plan.affectedWorkspaceIds, [destination, firstSource])
        XCTAssertEqual(plan.selection(in: destination), moved.id)
        XCTAssertEqual(plan.selection(in: firstSource), engine.findNode(for: token(2), in: firstSource)?.id)

        assertApplied(plan, in: engine)
        XCTAssertEqual(layout(destination, in: engine), [[1]])
        XCTAssertEqual(layout(firstSource, in: engine), [[2]])
        XCTAssertEqual(engine.planGather(gatherRequest.reassigned(to: destination), selections: [:]), .unchanged)
    }

    func testFinalAggregateFitUsesDestinationOrientationAndRefusesWithoutMutation() {
        let engine = NiriLayoutEngine()
        add(1, to: firstSource, in: engine, minHeight: 300)
        add(2, to: secondSource, in: engine, minHeight: 300)
        add(3, to: destination, in: engine, minHeight: 300)
        let gatherRequest = request([1, 2, 3], sources: [1: firstSource, 2: secondSource, 3: destination])
        let before = [firstSource, secondSource, destination].map { layout($0, in: engine) }

        XCTAssertEqual(engine.planGather(gatherRequest, selections: [:]), .refused(.doesNotFit))
        XCTAssertEqual([firstSource, secondSource, destination].map { layout($0, in: engine) }, before)
        guard case .ready = engine.planGather(
            request([1, 2], sources: [1: firstSource, 2: secondSource]),
            selections: [:]
        )
        else { return XCTFail("a pair fits on its own") }

        let portrait = NiriSizingGeometry(
            workingFrame: CGRect(x: 0, y: 0, width: 800, height: 1_200),
            gaps: 10,
            orientation: .vertical
        )
        for id in [1, 2, 3] {
            engine.updateWindowConstraints(
                for: token(id),
                constraints: WindowSizeConstraints(
                    minSize: CGSize(width: 300, height: 1),
                    maxSize: .zero,
                    isFixed: false
                ),
                in: id == 1 ? firstSource : id == 2 ? secondSource : destination,
                motion: .disabled
            )
        }
        let sources = [1: firstSource, 2: secondSource, 3: destination]
        guard case .ready = engine.planGather(request([1, 2, 3], sources: sources), selections: [:]) else {
            return XCTFail("narrow minimum widths fit a horizontal destination column")
        }
        XCTAssertEqual(
            engine.planGather(request([1, 2, 3], sources: sources, geometry: portrait), selections: [:]),
            .refused(.doesNotFit)
        )
    }

    func testConflictsAndEngineFullscreenRefuseEveryOffendingWindow() {
        let engine = NiriLayoutEngine()
        add(1, to: firstSource, in: engine)
        add(2, to: secondSource, in: engine)
        add(3, to: destination, in: engine)
        _ = engine.addWindow(token: token(1), to: destination, afterSelection: nil)
        engine.findNode(for: token(2), in: secondSource)?.sizingMode = .fullscreen

        XCTAssertEqual(
            engine.planGather(
                request([1, 2, 3, 4], sources: [1: firstSource, 2: secondSource, 3: firstSource, 4: destination]),
                selections: [:]
            ),
            .refused(.windows([
                token(1): .layoutConflict,
                token(2): .layoutFullscreen,
                token(3): .layoutConflict,
                token(4): .layoutConflict
            ]))
        )
        XCTAssertEqual(layout(destination, in: engine), [[3], [1]])
    }

    func testPlanIsAValueThatGoesStaleWhenItsPlannedResultOrSelectionsChange() throws {
        let engine = NiriLayoutEngine()
        add(1, to: firstSource, in: engine)
        let unrelated = add(11, to: firstSource, in: engine)
        add(2, to: destination, in: engine)
        let gatherRequest = request([1, 2], sources: [1: firstSource, 2: destination])
        let accepted = engine.planGather(gatherRequest, selections: [:])
        XCTAssertEqual(engine.planGather(gatherRequest, selections: [:]), accepted)

        XCTAssertNotEqual(engine.planGather(gatherRequest, selections: [firstSource: unrelated.id]), accepted)
        let column = try XCTUnwrap(engine.findColumn(containing: unrelated, in: firstSource))
        let other = try XCTUnwrap(engine.columns(in: firstSource).first)
        engine.moveWindowToColumn(unrelated, from: column, to: other, in: firstSource)
        column.remove()
        XCTAssertEqual(engine.planGather(gatherRequest, selections: [:]), accepted)
        add(12, to: destination, in: engine)
        XCTAssertNotEqual(engine.planGather(gatherRequest, selections: [:]), accepted)
    }

    func testPlannedFinalColumnsMatchTheAppliedTreeAroundStrayEmptyColumns() throws {
        let engine = NiriLayoutEngine()
        add(1, to: destination, in: engine)
        add(2, to: firstSource, in: engine)
        let root = try XCTUnwrap(engine.root(for: destination))
        let leading = try XCTUnwrap(root.columns.first)
        root.insertBefore(NiriContainer(), reference: leading)
        XCTAssertEqual(layout(destination, in: engine), [[], [1]])

        let plan = try readyPlan(engine, request([1, 2], sources: [1: destination, 2: firstSource]), anchor: nil)
        assertApplied(plan, in: engine)
        XCTAssertEqual(layout(destination, in: engine), [[1, 2]])
    }

    func testEmptiedSourceLosesSelectionAndAllItsColumns() throws {
        let engine = NiriLayoutEngine()
        let first = add(1, to: firstSource, in: engine)
        add(2, to: firstSource, in: engine)
        add(3, to: destination, in: engine)

        let planning = engine.planGather(
            request([1, 2], sources: [1: firstSource, 2: firstSource]),
            selections: [firstSource: first.id]
        )
        guard case let .ready(plan) = planning else { return XCTFail("expected ready, got \(planning)") }
        XCTAssertNil(plan.selection(in: firstSource))
        XCTAssertEqual(plan.activeColumnIndex(in: firstSource), 0)
        XCTAssertEqual(plan.selection(in: destination), first.id)
        XCTAssertEqual(plan.activeColumnIndex(in: destination), 0)

        assertApplied(plan, in: engine)
        XCTAssertEqual(layout(firstSource, in: engine), [])
        XCTAssertEqual(layout(destination, in: engine), [[1, 2], [3]])
        XCTAssertNotNil(engine.states[firstSource])
    }
}

private extension NiriGatherRequest {
    func reassigned(to workspaceId: WorkspaceDescriptor.ID) -> NiriGatherRequest {
        NiriGatherRequest(
            tokens: tokens,
            sourceWorkspaceIds: sourceWorkspaceIds.mapValues { _ in workspaceId },
            destinationWorkspaceId: destinationWorkspaceId,
            geometry: geometry,
            nativeFocusToken: nativeFocusToken
        )
    }
}
