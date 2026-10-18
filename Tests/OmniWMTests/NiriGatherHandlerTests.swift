// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class NiriGatherHandlerTests: XCTestCase {
    private enum FocusScenario: CaseIterable {
        case focusedIncluded
        case focusedExcluded
        case sourceEmptied
        case floatingFocus
        case externalFocus
    }

    private func scheduledRefresh(_ fixture: NiriGatherFixture) -> LayoutRefreshController.ScheduledRefresh? {
        let state = fixture.controller.layoutRefreshController.layoutState
        return state.activeRefresh ?? state.pendingRefresh
    }

    private func assertFocusUnchanged(
        _ fixture: NiriGatherFixture,
        since before: FocusSessionSnapshot,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let after = fixture.manager.focusSessionSnapshot
        XCTAssertEqual(after.nativeFocusOwner, before.nativeFocusOwner, message, file: file, line: line)
        XCTAssertEqual(after.selectedManagedToken, before.selectedManagedToken, message, file: file, line: line)
        XCTAssertEqual(after.pendingManagedFocus, before.pendingManagedFocus, message, file: file, line: line)
        XCTAssertEqual(after.interactionMonitorId, before.interactionMonitorId, message, file: file, line: line)
    }

    func testMonitorReachGathersInactiveWorkspacesIntoTheActiveCommandWorkspaceWithOneRelayout() async throws {
        let monitor = NiriGatherFixture.monitor(displayId: 74_101)
        let fixture = try NiriGatherFixture(
            prefix: "OmniWMNiriGatherHandler",
            monitors: [monitor],
            workspaces: [.init(name: "1"), .init(name: "2"), .init(name: "3")]
        )
        let manager = fixture.manager
        let active = fixture.workspace("1")
        XCTAssertTrue(manager.setActiveWorkspace(active, on: monitor.id))
        fixture.add([1, 11], to: active)
        fixture.add([2], to: fixture.workspace("2"))
        fixture.add([3], to: fixture.workspace("3"))
        _ = manager.setManagedFocus(fixture.token(11), in: active, onMonitor: monitor.id)
        await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)
        fixture.select(11, in: active)
        let focusBefore = manager.focusSessionSnapshot
        XCTAssertEqual(
            fixture.handler.gatherDestination(),
            NiriGatherDestination(workspaceId: active, monitor: monitor)
        )
        XCTAssertEqual(
            try fixture.gather([1, 2, 3], from: .workspace),
            .refused(.windows([fixture.token(2): .outsideReach, fixture.token(3): .outsideReach]))
        )

        let refreshController = fixture.controller.layoutRefreshController
        refreshController.beginPerformanceCapture()
        let sequence = fixture.lastTraceSequence()
        let outcome = try fixture.gather([1, 2, 3], from: .monitor)
        let enqueued = refreshController.performanceSnapshot()?.refreshesEnqueued
        let refresh = scheduledRefresh(fixture)
        let lines = fixture.traceLines(after: sequence)
        let worldSeqBeforeRepeat = manager.worldSeq
        let traceBeforeRepeat = fixture.lastTraceSequence()
        let repeated = try fixture.gather([1, 2, 3], from: .monitor)
        let enqueuedAfterRepeat = refreshController.endPerformanceCapture()?.refreshesEnqueued

        guard case let .gathered(plan) = outcome else { return XCTFail("expected gathered, got \(outcome)") }
        XCTAssertEqual(plan.movedTokens, [1, 2, 3].map(fixture.token))
        XCTAssertEqual(enqueued, 1)
        XCTAssertEqual(refresh?.reason, .layoutCommand)
        XCTAssertEqual(refresh?.affectedWorkspaceIds, [active, fixture.workspace("2"), fixture.workspace("3")])
        XCTAssertEqual(lines.count, 1, lines.joined(separator: "\n"))
        XCTAssertTrue(lines.first?.contains("label=niri_gather") == true, lines.joined())
        XCTAssertEqual(repeated, .unchanged)
        XCTAssertEqual(manager.worldSeq, worldSeqBeforeRepeat)
        XCTAssertTrue(fixture.traceLines(after: traceBeforeRepeat).isEmpty)
        XCTAssertEqual(enqueuedAfterRepeat, 1)
        XCTAssertEqual(fixture.layout(active), [[11], [1, 2, 3]])
        XCTAssertEqual(manager.activeWorkspace(on: monitor.id)?.id, active)
        assertFocusUnchanged(fixture, since: focusBefore)
    }

    func testIneligibleWindowsRefuseTheWholeRequestWithPerWindowReasons() throws {
        let monitor = NiriGatherFixture.monitor(displayId: 74_102)
        let fixture = try NiriGatherFixture(
            prefix: "OmniWMNiriGatherHandler",
            monitors: [monitor],
            workspaces: [.init(name: "1"), .init(name: "2"), .init(name: "3", layoutType: .dwindle)]
        )
        let manager = fixture.manager
        let destination = fixture.workspace("1")
        XCTAssertTrue(manager.setActiveWorkspace(destination, on: monitor.id))
        fixture.add([1, 2, 3, 4, 5, 6, 7, 10], to: destination)
        fixture.add([8], to: fixture.workspace("3"))
        XCTAssertTrue(manager.updateScratchpadMembership(fixture.token(2), to: 1, notify: false))
        manager.setAppHidden(true, pid: fixture.token(3).pid, source: .workspaceManager)
        XCTAssertTrue(manager.setWindowMinimized(true, token: fixture.token(4)))
        XCTAssertTrue(manager.setWindowNativeWithdrawn(true, token: fixture.token(5)))
        XCTAssertTrue(manager.setWindowMode(.floating, for: fixture.token(6)))
        manager.setLayoutReason(.nativeFullscreen, for: fixture.token(7))
        manager.withEngineMutationScope {
            fixture.node(10, in: destination)?.sizingMode = .fullscreen
        }
        let sequence = manager.worldSeq
        let trace = manager.reconcileTraceDump()
        let layout = fixture.layout(destination)

        let refreshController = fixture.controller.layoutRefreshController
        refreshController.beginPerformanceCapture()
        let outcome = try fixture.gather([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], from: .all)
        XCTAssertEqual(refreshController.endPerformanceCapture()?.refreshesEnqueued, 0)

        XCTAssertEqual(outcome, .refused(.windows([
            fixture.token(2): .scratchpad,
            fixture.token(3): .appHidden,
            fixture.token(4): .minimized,
            fixture.token(5): .nativeWithdrawn,
            fixture.token(6): .floating,
            fixture.token(7): .nativeFullscreen,
            fixture.token(8): .unsupportedLayout,
            fixture.token(9): .notFound,
            fixture.token(10): .layoutFullscreen
        ])))
        XCTAssertEqual(manager.worldSeq, sequence)
        XCTAssertEqual(manager.reconcileTraceDump(), trace)
        XCTAssertEqual(fixture.layout(destination), layout)
        XCTAssertEqual(manager.workspace(for: fixture.token(1)), destination)
    }

    func testEachReachValidatesEveryListedWindowBeforeAnyChange() throws {
        let left = NiriGatherFixture.monitor(displayId: 74_111)
        let right = NiriGatherFixture.monitor(displayId: 74_112, x: 1_200)
        let fixture = try NiriGatherFixture(
            prefix: "OmniWMNiriGatherHandler",
            monitors: [left, right],
            workspaces: [
                .init(name: "1", monitor: left),
                .init(name: "2", monitor: left),
                .init(name: "3", monitor: right)
            ]
        )
        let manager = fixture.manager
        let destination = fixture.workspace("1")
        XCTAssertTrue(manager.setActiveWorkspace(destination, on: left.id))
        XCTAssertTrue(manager.setActiveWorkspace(fixture.workspace("3"), on: right.id))
        manager.setInteractionMonitor(left.id)
        fixture.add([1], to: destination)
        fixture.add([2, 4], to: fixture.workspace("2"))
        fixture.add([3], to: fixture.workspace("3"))
        XCTAssertTrue(manager.setWindowMinimized(true, token: fixture.token(4)))
        let sequence = manager.worldSeq
        let layouts = ["1", "2", "3"].map { fixture.layout(fixture.workspace($0)) }

        let refreshController = fixture.controller.layoutRefreshController
        refreshController.beginPerformanceCapture()
        XCTAssertEqual(
            try fixture.gather([1, 2], from: .workspace),
            .refused(.windows([fixture.token(2): .outsideReach]))
        )
        XCTAssertEqual(
            try fixture.gather([1, 2, 3], from: .monitor),
            .refused(.windows([fixture.token(3): .outsideReach]))
        )
        XCTAssertEqual(
            try fixture.gather([1, 2, 4], from: .monitor),
            .refused(.windows([fixture.token(4): .minimized]))
        )
        XCTAssertEqual(
            try fixture.gather([1, 4, 3], from: .workspace),
            .refused(.windows([fixture.token(4): .outsideReach, fixture.token(3): .outsideReach]))
        )
        XCTAssertEqual(refreshController.performanceSnapshot()?.refreshesEnqueued, 0)
        XCTAssertEqual(manager.worldSeq, sequence)
        XCTAssertEqual(["1", "2", "3"].map { fixture.layout(fixture.workspace($0)) }, layouts)

        let traceSequence = fixture.lastTraceSequence()
        guard case .gathered = try fixture.gather([1, 2, 3], from: .all) else {
            return XCTFail("every listed window is within the global reach")
        }
        XCTAssertEqual(refreshController.endPerformanceCapture()?.refreshesEnqueued, 1)
        XCTAssertEqual(fixture.traceLines(after: traceSequence).count, 1)
        XCTAssertEqual(fixture.layout(destination), [[1, 2, 3]])
        XCTAssertEqual(fixture.layout(fixture.workspace("2")), [[4]])
        XCTAssertEqual(fixture.layout(fixture.workspace("3")), [])
        XCTAssertEqual(manager.activeWorkspace(on: right.id)?.id, fixture.workspace("3"))
    }

    func testInactiveTabsOffViewportAndInactiveWorkspaceWindowsAreEligible() throws {
        let monitor = NiriGatherFixture.monitor(displayId: 74_105)
        let fixture = try NiriGatherFixture(
            prefix: "OmniWMNiriGatherHandler",
            monitors: [monitor],
            workspaces: [.init(name: "1"), .init(name: "2")]
        )
        let manager = fixture.manager
        let active = fixture.workspace("1")
        let parked = fixture.workspace("2")
        XCTAssertTrue(manager.setActiveWorkspace(active, on: monitor.id))
        fixture.add([1, 2, 3], to: active)
        fixture.add([4], to: parked)
        manager.withEngineMutationScope {
            let first = fixture.node(1, in: active)!
            let firstColumn = fixture.engine.findColumn(containing: first, in: active)!
            let secondNode = fixture.node(2, in: active)!
            let secondColumn = fixture.engine.findColumn(containing: secondNode, in: active)!
            fixture.engine.moveWindowToColumn(secondNode, from: secondColumn, to: firstColumn, in: active)
            secondColumn.remove()
            firstColumn.displayMode = .tabbed
            fixture.engine.updateTabbedColumnVisibility(column: firstColumn)
        }
        XCTAssertTrue(manager.isInactiveTabMember(fixture.token(2), in: active))
        manager.setHiddenState(
            HiddenState(proportionalPosition: .zero, referenceMonitorId: monitor.id, reason: .layoutTransient(.right)),
            for: fixture.token(3)
        )
        manager.setHiddenState(
            HiddenState(proportionalPosition: .zero, referenceMonitorId: monitor.id, reason: .workspaceInactive),
            for: fixture.token(4)
        )
        fixture.select(1, in: active)

        let outcome = try fixture.gather([2, 3, 4], from: .monitor)

        guard case .gathered = outcome else { return XCTFail("expected gathered, got \(outcome)") }
        XCTAssertEqual(fixture.layout(active), [[1], [2, 3, 4]])
        XCTAssertEqual(fixture.layout(parked), [])
        XCTAssertEqual(manager.activeWorkspace(on: monitor.id)?.id, active)
    }

    func testDestinationIsTheCommandMonitorsActiveNiriWorkspaceAndItsGeometryDecidesFit() throws {
        let tall = NiriGatherFixture.monitor(displayId: 74_103, height: 1_600)
        let short = NiriGatherFixture.monitor(displayId: 74_104, x: 1_200, height: 800)
        let fixture = try NiriGatherFixture(
            prefix: "OmniWMNiriGatherHandler",
            monitors: [tall, short],
            workspaces: [
                .init(name: "1", monitor: tall),
                .init(name: "2", monitor: tall),
                .init(name: "3", monitor: short),
                .init(name: "4", layoutType: .dwindle, monitor: short)
            ]
        )
        let manager = fixture.manager
        let handler = fixture.handler
        XCTAssertTrue(manager.setActiveWorkspace(fixture.workspace("2"), on: tall.id))
        XCTAssertTrue(manager.setActiveWorkspace(fixture.workspace("3"), on: short.id))
        fixture.add([1, 2], to: fixture.workspace("1"), minHeight: 400)
        let tokens = [1, 2].map(fixture.token)

        manager.setInteractionMonitor(short.id)
        XCTAssertEqual(handler.gatherDestination()?.workspaceId, fixture.workspace("3"))
        XCTAssertEqual(try fixture.gather([1, 2], from: .all), .refused(.doesNotFit))
        XCTAssertTrue(manager.setActiveWorkspace(fixture.workspace("4"), on: short.id))
        XCTAssertEqual(try fixture.gather([1, 2], from: .all), .refused(.unsupportedLayout))
        XCTAssertEqual(
            handler.gatherWindows(
                tokens,
                from: .all,
                into: NiriGatherDestination(workspaceId: WorkspaceDescriptor.ID(), monitor: short)
            ),
            .refused(.destinationUnavailable)
        )
        XCTAssertEqual(fixture.layout(fixture.workspace("1")), [[1], [2]])

        manager.setInteractionMonitor(tall.id)
        XCTAssertEqual(handler.gatherDestination()?.workspaceId, fixture.workspace("2"))
        guard case .gathered = try fixture.gather([1, 2], from: .all) else {
            return XCTFail("the taller destination fits both windows")
        }
        XCTAssertEqual(fixture.layout(fixture.workspace("2")), [[1, 2]])
        XCTAssertEqual(fixture.layout(fixture.workspace("1")), [])
    }

    func testCommandMonitorDestinationKeepsNativeFocusFromAnotherMonitorOnTheGatheredWindow() async throws {
        let left = NiriGatherFixture.monitor(displayId: 74_121)
        let right = NiriGatherFixture.monitor(displayId: 74_122, x: 1_200)
        let fixture = try NiriGatherFixture(
            prefix: "OmniWMNiriGatherHandler",
            monitors: [left, right],
            workspaces: [.init(name: "1", monitor: left), .init(name: "3", monitor: right)]
        )
        let manager = fixture.manager
        let destination = fixture.workspace("1")
        let source = fixture.workspace("3")
        XCTAssertTrue(manager.setActiveWorkspace(destination, on: left.id))
        XCTAssertTrue(manager.setActiveWorkspace(source, on: right.id))
        fixture.add([1], to: destination)
        fixture.add([3, 4], to: source)
        XCTAssertTrue(manager.setManagedFocus(fixture.token(3), in: source, onMonitor: right.id))
        manager.setInteractionMonitor(left.id)
        await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)
        fixture.select(1, in: destination)
        fixture.select(3, in: source)
        fixture.focusRecorder.operations.removeAll()
        let focusBefore = manager.focusSessionSnapshot
        XCTAssertEqual(focusBefore.nativeFocusOwner, .managed(fixture.token(3)))
        XCTAssertEqual(focusBefore.interactionMonitorId, left.id)
        XCTAssertEqual(fixture.handler.gatherDestination()?.workspaceId, destination)

        guard case .gathered = try fixture.gather([1, 3], from: .all) else {
            return XCTFail("expected the global reach to gather across monitors")
        }
        await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)

        XCTAssertEqual(fixture.layout(destination), [[1, 3]])
        XCTAssertEqual(fixture.layout(source), [[4]])
        XCTAssertEqual(manager.niriViewportState(for: destination).selectedNodeId, fixture.node(3, in: destination)?.id)
        XCTAssertEqual(fixture.engine.columns(in: destination).first?.activeTileIdx, 1)
        XCTAssertEqual(manager.niriViewportState(for: source).selectedNodeId, fixture.node(4, in: source)?.id)
        XCTAssertEqual(manager.activeWorkspace(on: left.id)?.id, destination)
        XCTAssertEqual(manager.activeWorkspace(on: right.id)?.id, source)
        XCTAssertEqual(fixture.focusRecorder.operations, [])
        assertFocusUnchanged(fixture, since: focusBefore)

        fixture.controller.focusWindow(fixture.token(4))
        XCTAssertFalse(fixture.focusRecorder.operations.isEmpty)
    }

    func testGatherIssuesNoNativeFocusOperationsThroughItsRelayout() async throws {
        for (index, scenario) in FocusScenario.allCases.enumerated() {
            let monitor = NiriGatherFixture.monitor(displayId: 74_131 + UInt32(index))
            let fixture = try NiriGatherFixture(
                prefix: "OmniWMNiriGatherHandler",
                monitors: [monitor],
                workspaces: [.init(name: "1"), .init(name: "2")]
            )
            let manager = fixture.manager
            let active = fixture.workspace("1")
            XCTAssertTrue(manager.setActiveWorkspace(active, on: monitor.id))
            fixture.add([1, 11], to: active)
            fixture.add([2], to: fixture.workspace("2"))
            _ = WindowAdmissionTestSupport.track(fixture.token(5), in: active, controller: fixture.controller)
            XCTAssertTrue(manager.setWindowMode(.floating, for: fixture.token(5)))
            switch scenario {
            case .focusedIncluded:
                XCTAssertTrue(manager.setManagedFocus(fixture.token(1), in: active, onMonitor: monitor.id))
            case .focusedExcluded,
                 .sourceEmptied:
                XCTAssertTrue(manager.setManagedFocus(fixture.token(11), in: active, onMonitor: monitor.id))
            case .floatingFocus:
                XCTAssertTrue(manager.setManagedFocus(fixture.token(5), in: active, onMonitor: monitor.id))
            case .externalFocus:
                XCTAssertTrue(manager.recordExternalFocus(pid: 9_999, windowId: 9_999))
            }
            await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)
            fixture.select(11, in: active)
            fixture.focusRecorder.operations.removeAll()
            let focusBefore = manager.focusSessionSnapshot

            let ids = scenario == .sourceEmptied ? [2] : [1, 2]
            let outcome = try fixture.gather(ids, from: .monitor)
            guard case .gathered = outcome else {
                XCTFail("\(scenario): expected gathered, got \(outcome)")
                continue
            }
            await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)

            XCTAssertEqual(
                fixture.layout(active),
                scenario == .sourceEmptied ? [[1], [11], [2]] : [[11], [1, 2]],
                "\(scenario)"
            )
            XCTAssertEqual(fixture.layout(fixture.workspace("2")), [], "\(scenario)")
            XCTAssertEqual(fixture.focusRecorder.operations, [], "\(scenario)")
            assertFocusUnchanged(fixture, since: focusBefore, "\(scenario)")
        }
    }
}
