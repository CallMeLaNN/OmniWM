// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

@MainActor
final class CrossDisplayDragTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let controller: WMController
        let niri: NiriLayoutEngine
        let dwindle: DwindleLayoutEngine
        let monitors: [Monitor]
        let workspaces: [WorkspaceDescriptor.ID]

        var manager: WorkspaceManager {
            controller.workspaceManager
        }

        var handler: MouseEventHandler {
            controller.mouseEventHandler
        }

        var source: WorkspaceDescriptor.ID {
            workspaces[0]
        }

        var target: WorkspaceDescriptor.ID {
            workspaces[1]
        }

        func columns(_ workspaceId: WorkspaceDescriptor.ID) -> [[WindowToken]] {
            niri.columns(in: workspaceId).map { $0.windowNodes.map(\.token) }
        }

        func niriNode(_ token: WindowToken) -> NiriWindow? {
            manager.workspace(for: token).flatMap { niri.findNode(for: token, in: $0) }
        }

        func dwindleTile(_ token: WindowToken) -> [WindowToken]? {
            manager.workspace(for: token)
                .flatMap { dwindle.tile(containing: token, in: $0) }?
                .members.map(\.token)
        }

        func frame(_ token: WindowToken) -> CGRect? {
            guard let workspaceId = manager.workspace(for: token) else { return nil }
            return switch manager.activeLayoutKind(for: workspaceId) {
            case .niri: niri.findNode(for: token, in: workspaceId)?.frame
            case .dwindle: dwindle.presentedFrame(for: token, in: workspaceId, at: 0)
            }
        }

        func layout() {
            for (monitor, workspaceId) in zip(monitors, workspaces) {
                let workingFrame = controller.insetWorkingFrame(for: monitor)
                switch manager.activeLayoutKind(for: workspaceId) {
                case .niri:
                    let gap = controller.innerGap(for: monitor)
                    _ = niri.calculateLayout(
                        state: manager.niriViewportState(for: workspaceId),
                        workspaceId: workspaceId,
                        monitorFrame: workingFrame,
                        gaps: (horizontal: gap, vertical: gap),
                        orientation: .horizontal
                    )
                case .dwindle:
                    _ = dwindle.calculateLayout(for: workspaceId, screen: workingFrame)
                    dwindle.cancelAnimations(in: workspaceId)
                }
            }
        }

        func beginDrag(_ token: WindowToken) throws {
            layout()
            let start = try XCTUnwrap(frame(token)).center
            XCTAssertFalse(handler.dispatchMouseDown(at: start, modifiers: .maskControl))
            XCTAssertTrue(handler.state.isMoving)
        }

        func finishDrag(at point: CGPoint) {
            handler.dispatchMouseDragged(at: point)
            handler.dispatchMouseUp(at: point)
            XCTAssertFalse(handler.state.isMoving)
            XCTAssertNil(niri.interactiveMove)
            XCTAssertNil(dwindle.interactiveMove)
        }

        func drag(_ token: WindowToken, to point: CGPoint) throws {
            try beginDrag(token)
            finishDrag(at: point)
        }
    }

    func testNiriColumnEdgesInsertANewColumnOnTheOtherDisplay() throws {
        for (direction, expectedIndex) in [(Direction.left, 0), (.right, 1)] {
            let fixture = try makeFixture([.niri, .niri])
            let moved = addWindow(1, to: fixture.source, fixture)
            let first = addWindow(2, to: fixture.target, fixture)
            let second = addWindow(3, to: fixture.target, fixture)
            fixture.layout()

            try fixture.drag(moved, to: dropPoint(in: XCTUnwrap(fixture.frame(first)), direction))

            var expected = [[first], [second]]
            expected.insert([moved], at: expectedIndex)
            XCTAssertEqual(fixture.columns(fixture.target), expected)
            XCTAssertEqual(fixture.columns(fixture.source).flatMap(\.self), [])
            XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
            XCTAssertEqual(
                fixture.manager.niriViewportState(for: fixture.target).selectedNodeId,
                fixture.niriNode(moved)?.id
            )
        }
    }

    func testNiriColumnEdgeStacksIntoTheTargetColumnAndActivatesTheWindow() throws {
        for direction in [Direction.up, .down] {
            let fixture = try makeFixture([.niri, .niri])
            let moved = addWindow(1, to: fixture.source, fixture)
            let target = addWindow(2, to: fixture.target, fixture)
            fixture.layout()

            try fixture.drag(moved, to: dropPoint(in: XCTUnwrap(fixture.frame(target)), direction))
            fixture.layout()

            let column = try XCTUnwrap(fixture.niri.columns(in: fixture.target).first)
            XCTAssertEqual(Set(column.windowNodes.map(\.token)), [target, moved])
            XCTAssertTrue(column.activeWindow === fixture.niriNode(moved))
            XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
            let movedFrame = try XCTUnwrap(fixture.frame(moved))
            let targetFrame = try XCTUnwrap(fixture.frame(target))
            XCTAssertEqual(movedFrame.midX, targetFrame.midX, accuracy: 0.5)
            XCTAssertEqual(movedFrame.midY > targetFrame.midY, direction == .up)
        }
    }

    func testRefusedNiriStackFallsBackToANewColumnAtTheEnd() throws {
        let fixture = try makeFixture([.niri, .niri])
        let moved = addWindow(1, to: fixture.source, fixture)
        let target = addWindow(2, to: fixture.target, fixture)
        let other = addWindow(3, to: fixture.target, fixture)
        fixture.manager.setCachedConstraints(constraints(minHeight: 2_000), for: moved)
        fixture.layout()

        try fixture.drag(moved, to: dropPoint(in: XCTUnwrap(fixture.frame(target)), .down))

        XCTAssertEqual(fixture.columns(fixture.target), [[target], [other], [moved]])
        XCTAssertEqual(fixture.niriNode(moved)?.constraints.minSize.height, 2_000)
    }

    func testNiriSwapKeepsBothSlotsAndSelectsTheArrivals() throws {
        let fixture = try makeFixture([.niri, .niri])
        let moved = addWindow(1, to: fixture.source, fixture)
        let sourceSibling = addWindow(2, to: fixture.source, fixture)
        let partnerSibling = addWindow(3, to: fixture.target, fixture)
        let partner = addWindow(4, to: fixture.target, fixture)
        try stack(sourceSibling, onto: moved, in: fixture.source, fixture)
        try stack(partnerSibling, onto: partner, in: fixture.target, fixture)
        let movedNode = try XCTUnwrap(fixture.niriNode(moved))
        let partnerNode = try XCTUnwrap(fixture.niriNode(partner))
        movedNode.size = 1.4
        partnerNode.size = 0.6
        fixture.layout()

        try fixture.drag(moved, to: XCTUnwrap(fixture.frame(partner)).center)

        XCTAssertEqual(fixture.columns(fixture.source), [[partner, sourceSibling]])
        XCTAssertEqual(fixture.columns(fixture.target), [[moved, partnerSibling]])
        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
        XCTAssertEqual(fixture.manager.workspace(for: partner), fixture.source)
        XCTAssertEqual(partnerNode.size, 1.4)
        XCTAssertEqual(movedNode.size, 0.6)
        XCTAssertEqual(fixture.manager.niriViewportState(for: fixture.source).selectedNodeId, partnerNode.id)
        XCTAssertEqual(fixture.manager.niriViewportState(for: fixture.target).selectedNodeId, movedNode.id)
        XCTAssertNil(fixture.niri.findNode(for: moved, in: fixture.source))
        XCTAssertNil(fixture.niri.findNode(for: partner, in: fixture.target))
    }

    func testRefusedNiriSwapLeavesTheWorldUnchanged() throws {
        let fixture = try makeFixture([.niri, .niri])
        let moved = addWindow(1, to: fixture.source, fixture)
        let sourceSibling = addWindow(2, to: fixture.source, fixture)
        let partner = addWindow(3, to: fixture.target, fixture)
        try stack(sourceSibling, onto: moved, in: fixture.source, fixture)
        fixture.manager.setCachedConstraints(constraints(minHeight: 2_000), for: partner)
        fixture.layout()
        let partnerCenter = try XCTUnwrap(fixture.frame(partner)).center
        try fixture.beginDrag(moved)
        let worldSeq = fixture.manager.worldSeq

        fixture.finishDrag(at: partnerCenter)

        XCTAssertEqual(fixture.manager.worldSeq, worldSeq)
        XCTAssertEqual(fixture.columns(fixture.source), [[moved, sourceSibling]])
        XCTAssertEqual(fixture.columns(fixture.target), [[partner]])
        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.source)
        XCTAssertEqual(fixture.manager.workspace(for: partner), fixture.target)
    }

    func testNiriDropBeyondTheColumnStripAppendsAColumn() throws {
        let fixture = try makeFixture([.niri, .niri])
        let moved = addWindow(1, to: fixture.source, fixture)
        let first = addWindow(2, to: fixture.target, fixture)
        let second = addWindow(3, to: fixture.target, fixture)
        for column in fixture.niri.columns(in: fixture.target) {
            column.width = .proportion(0.3)
        }
        fixture.layout()
        let stripEnd = try XCTUnwrap(fixture.frame(second)).maxX
        let workingFrame = fixture.controller.insetWorkingFrame(for: fixture.monitors[1])
        let beyond = CGPoint(x: (stripEnd + workingFrame.maxX) / 2, y: workingFrame.midY)
        XCTAssertLessThan(stripEnd + 100, beyond.x)

        try fixture.drag(moved, to: beyond)

        XCTAssertEqual(fixture.columns(fixture.target), [[first], [second], [moved]])
    }

    func testDropIntoAnEmptyWorkspaceOnTheOtherDisplay() throws {
        for targetLayout in [LayoutType.niri, .dwindle] {
            let fixture = try makeFixture([.niri, targetLayout])
            let moved = addWindow(1, to: fixture.source, fixture)
            let stays = addWindow(2, to: fixture.source, fixture)

            try fixture.drag(moved, to: fixture.monitors[1].frame.center)

            XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
            XCTAssertEqual(fixture.columns(fixture.source), [[stays]])
            if targetLayout == .niri {
                XCTAssertEqual(fixture.columns(fixture.target), [[moved]])
            } else {
                XCTAssertEqual(fixture.dwindleTile(moved), [moved])
                XCTAssertTrue(fixture.dwindle.root(for: fixture.target)?.isLeaf == true)
            }
        }
    }

    func testDwindleTileZonesInsertBesideTheTargetInEveryDirection() throws {
        for direction in [Direction.left, .right, .up, .down] {
            let fixture = try makeFixture([.dwindle, .dwindle])
            let moved = addWindow(1, to: fixture.source, fixture)
            let target = addWindow(2, to: fixture.target, fixture)
            let other = addWindow(3, to: fixture.target, fixture)
            fixture.layout()
            let targetSlot = try XCTUnwrap(fixture.frame(target))
            let otherFrame = try XCTUnwrap(fixture.frame(other))

            try fixture.drag(moved, to: dropPoint(in: targetSlot, direction))
            fixture.layout()

            let movedFrame = try XCTUnwrap(fixture.frame(moved))
            let targetFrame = try XCTUnwrap(fixture.frame(target))
            XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target, "\(direction)")
            XCTAssertTrue(targetSlot.insetBy(dx: -1, dy: -1).contains(movedFrame), "\(direction)")
            XCTAssertTrue(targetSlot.insetBy(dx: -1, dy: -1).contains(targetFrame), "\(direction)")
            XCTAssertEqual(fixture.frame(other), otherFrame, "\(direction)")
            switch direction {
            case .left: XCTAssertLessThan(movedFrame.maxX, targetFrame.minX + 1)
            case .right: XCTAssertGreaterThan(movedFrame.minX, targetFrame.maxX - 1)
            case .up: XCTAssertGreaterThan(movedFrame.minY, targetFrame.maxY - 1)
            case .down: XCTAssertLessThan(movedFrame.maxY, targetFrame.minY + 1)
            }
        }
    }

    func testDwindleWorkspaceEdgeSplitsTheWholeTargetTree() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let first = addWindow(2, to: fixture.target, fixture)
        let second = addWindow(3, to: fixture.target, fixture)
        fixture.layout()
        let workingFrame = fixture.controller.insetWorkingFrame(for: fixture.monitors[1])

        try fixture.drag(moved, to: CGPoint(x: workingFrame.midX, y: workingFrame.maxY - 2))
        fixture.layout()

        let movedFrame = try XCTUnwrap(fixture.frame(moved))
        for resident in [first, second] {
            XCTAssertGreaterThan(movedFrame.minY, try XCTUnwrap(fixture.frame(resident)).maxY - 1)
        }
        XCTAssertEqual(movedFrame.width, workingFrame.width, accuracy: 1)
    }

    func testDwindleSwapTradesSingleTiles() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let sourceSibling = addWindow(2, to: fixture.source, fixture)
        let partner = addWindow(3, to: fixture.target, fixture)
        let partnerSibling = addWindow(4, to: fixture.target, fixture)
        fixture.layout()
        let movedSlot = try XCTUnwrap(fixture.frame(moved))
        let partnerSlot = try XCTUnwrap(fixture.frame(partner))

        try fixture.drag(moved, to: partnerSlot.center)
        fixture.layout()

        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
        XCTAssertEqual(fixture.manager.workspace(for: partner), fixture.source)
        XCTAssertEqual(fixture.frame(moved), partnerSlot)
        XCTAssertEqual(fixture.frame(partner), movedSlot)
        XCTAssertEqual(fixture.dwindleTile(sourceSibling), [sourceSibling])
        XCTAssertEqual(fixture.dwindleTile(partnerSibling), [partnerSibling])
    }

    func testDwindleSwapIntoAGroupedMemberKeepsTheGroup() throws {
        let fixture = try makeFixture([.dwindle, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let member = addWindow(2, to: fixture.target, fixture)
        let partner = addWindow(3, to: fixture.target, fixture)
        fixture.manager.withEngineMutationScope(in: fixture.target) {
            XCTAssertTrue(fixture.dwindle.groupWindow(partner, into: member, in: fixture.target))
        }
        XCTAssertEqual(fixture.dwindleTile(member), [member, partner])
        fixture.layout()
        let groupFrame = try XCTUnwrap(fixture.frame(partner))
        XCTAssertEqual(
            fixture.dwindle.hitTestFocusableWindow(point: groupFrame.center, in: fixture.target, at: 0),
            partner
        )

        try fixture.drag(moved, to: groupFrame.center)

        XCTAssertEqual(fixture.dwindleTile(moved), [member, moved])
        XCTAssertEqual(fixture.dwindleTile(partner), [partner])
        XCTAssertEqual(fixture.manager.workspace(for: partner), fixture.source)
        XCTAssertEqual(fixture.dwindle.tile(containing: moved, in: fixture.target)?.activeToken, moved)
    }

    func testFullscreenTargetCancelsTheDropAndClearsThePreview() throws {
        let fixture = try makeFixture([.niri, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let resident = addWindow(2, to: fixture.target, fixture)
        fixture.manager.withEngineMutationScope(in: fixture.target) {
            XCTAssertEqual(fixture.dwindle.toggleFullscreen(in: fixture.target), resident)
        }
        let point = fixture.monitors[1].frame.center
        try fixture.beginDrag(moved)
        let worldSeq = fixture.manager.worldSeq

        fixture.handler.dispatchMouseDragged(at: point)
        XCTAssertEqual(fixture.handler.classifyMoveLocation(point), .cancel)
        XCTAssertNil(fixture.niri.interactiveMove?.currentHoverTarget)
        fixture.handler.dispatchMouseUp(at: point)

        XCTAssertEqual(fixture.manager.worldSeq, worldSeq)
        XCTAssertEqual(fixture.columns(fixture.source), [[moved]])
        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.source)
    }

    func testNiriToDwindleCapturesSizingThatTheReturnTripRestores() throws {
        let fixture = try makeFixture([.niri, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let stays = addWindow(2, to: fixture.source, fixture)
        let target = addWindow(3, to: fixture.target, fixture)
        let column = try XCTUnwrap(fixture.niri.columns(in: fixture.source).first)
        column.width = .proportion(0.7)
        fixture.layout()

        try fixture.drag(moved, to: dropPoint(in: XCTUnwrap(fixture.frame(target)), .right))

        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
        XCTAssertEqual(fixture.dwindleTile(moved), [moved])
        XCTAssertEqual(
            fixture.manager.restoreIntent(for: moved)?.detachedNiriContainerSizingState?.width,
            .proportion(0.7)
        )

        fixture.layout()
        try fixture.drag(moved, to: dropPoint(in: XCTUnwrap(fixture.frame(stays)), .right))

        XCTAssertEqual(fixture.columns(fixture.source), [[stays], [moved]])
        XCTAssertEqual(fixture.niri.columns(in: fixture.source).last?.width, .proportion(0.7))
        XCTAssertNil(fixture.dwindle.tile(containing: moved, in: fixture.target))
    }

    func testDwindleToNiriInstallsDestinationConstraints() throws {
        for direction in [Direction.right, .down] {
            let fixture = try makeFixture([.dwindle, .niri])
            let moved = addWindow(1, to: fixture.source, fixture)
            let target = addWindow(2, to: fixture.target, fixture)
            fixture.manager.setCachedConstraints(constraints(minWidth: 3_000, minHeight: 200), for: moved)
            fixture.layout()

            try fixture.drag(moved, to: dropPoint(in: XCTUnwrap(fixture.frame(target)), direction))

            XCTAssertEqual(
                fixture.columns(fixture.target),
                direction == .right ? [[target], [moved]] : [[moved, target]]
            )
            let node = try XCTUnwrap(fixture.niriNode(moved))
            let workArea = fixture.controller.insetWorkingFrame(for: fixture.monitors[1])
            XCTAssertEqual(node.constraints.minSize.width, workArea.width, accuracy: 1)
            XCTAssertEqual(node.constraints.minSize.height, 200)
            XCTAssertNil(fixture.dwindle.tile(containing: moved, in: fixture.source))
        }
    }

    func testMixedSwapTradesSlotsAcrossLayouts() throws {
        let fixture = try makeFixture([.niri, .dwindle])
        let moved = addWindow(1, to: fixture.source, fixture)
        let stays = addWindow(2, to: fixture.source, fixture)
        let partner = addWindow(3, to: fixture.target, fixture)
        let resident = addWindow(4, to: fixture.target, fixture)
        fixture.layout()
        let partnerSlot = try XCTUnwrap(fixture.frame(partner))

        try fixture.drag(moved, to: partnerSlot.center)
        fixture.layout()

        XCTAssertEqual(fixture.columns(fixture.source), [[partner], [stays]])
        XCTAssertEqual(fixture.frame(moved), partnerSlot)
        XCTAssertEqual(fixture.dwindleTile(resident), [resident])
        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.target)
        XCTAssertEqual(fixture.manager.workspace(for: partner), fixture.source)
        XCTAssertNotNil(fixture.manager.restoreIntent(for: moved)?.detachedNiriContainerSizingState)
        XCTAssertEqual(
            fixture.manager.niriViewportState(for: fixture.source).selectedNodeId,
            fixture.niriNode(partner)?.id
        )
    }

    func testDropOutsideTheTargetViewportStartsItsScrollAnimation() throws {
        let fixture = try makeFixture([.niri, .niri])
        let moved = addWindow(1, to: fixture.source, fixture)
        let residents = (2 ... 4).map { addWindow($0, to: fixture.target, fixture) }
        for column in fixture.niri.columns(in: fixture.target) {
            column.width = .proportion(0.5)
        }
        fixture.layout()
        let lastVisible = try XCTUnwrap(fixture.frame(residents[1]))
        XCTAssertTrue(fixture.monitors[1].frame.contains(lastVisible.center))
        fixture.controller.motionPolicy.animationsEnabled = true
        fixture.controller.layoutRefreshController.displayLinkActivationForTests = { _ in true }

        try fixture.drag(moved, to: dropPoint(in: lastVisible, .right))

        XCTAssertEqual(fixture.columns(fixture.target), [[residents[0]], [residents[1]], [moved], [residents[2]]])
        XCTAssertEqual(
            fixture.controller.niriLayoutHandler.scrollAnimationByDisplay[fixture.monitors[1].displayId],
            fixture.target
        )
    }

    func testHoverPreviewsOnTheTargetDisplayWithoutMutatingTheWorld() throws {
        let fixture = try makeFixture([.niri, .niri])
        let moved = addWindow(1, to: fixture.source, fixture)
        let neighbor = addWindow(2, to: fixture.source, fixture)
        let target = addWindow(3, to: fixture.target, fixture)
        fixture.layout()
        let targetFrame = try XCTUnwrap(fixture.frame(target))
        let neighborFrame = try XCTUnwrap(fixture.frame(neighbor))
        try fixture.beginDrag(moved)
        let worldSeq = fixture.manager.worldSeq

        fixture.handler.dispatchMouseDragged(at: neighborFrame.center)
        XCTAssertNotNil(fixture.niri.interactiveMove?.currentHoverTarget)

        fixture.handler.dispatchMouseDragged(at: targetFrame.center)
        guard case let .crossDisplay(drop) = fixture.handler.classifyMoveLocation(targetFrame.center) else {
            return XCTFail("expected a cross-display drop")
        }
        XCTAssertEqual(drop.placement, .swap(target: target))
        XCTAssertEqual(drop.previewFrame, targetFrame)
        XCTAssertTrue(fixture.monitors[1].frame.contains(drop.previewFrame))
        XCTAssertNil(fixture.niri.interactiveMove?.currentHoverTarget)
        XCTAssertEqual(fixture.manager.worldSeq, worldSeq)

        fixture.handler.dispatchMouseDragged(at: neighborFrame.center)
        XCTAssertEqual(fixture.handler.classifyMoveLocation(neighborFrame.center), .sourceDisplay)
        XCTAssertNotNil(fixture.niri.interactiveMove?.currentHoverTarget)
        fixture.handler.dispatchMouseUp(at: neighborFrame.center)

        XCTAssertEqual(fixture.manager.workspace(for: moved), fixture.source)
        XCTAssertEqual(fixture.columns(fixture.target), [[target]])
    }

    func testCancelZoneOnAThirdDisplayLeavesTheSourceUnchanged() throws {
        let fixture = try makeFixture([.niri, .niri, .dwindle])
        let tokens = (1 ... 6).map { addWindow($0, to: fixture.source, fixture) }
        for column in fixture.niri.columns(in: fixture.source) {
            column.width = .proportion(1)
        }
        let resident = addWindow(7, to: fixture.workspaces[2], fixture)
        fixture.manager.withEngineMutationScope(in: fixture.workspaces[2]) {
            XCTAssertEqual(fixture.dwindle.toggleFullscreen(in: fixture.workspaces[2]), resident)
        }
        fixture.layout()
        let point = fixture.monitors[2].frame.center
        XCTAssertTrue(tokens.contains { fixture.frame($0)?.contains(point) == true })
        try fixture.beginDrag(tokens[0])
        let worldSeq = fixture.manager.worldSeq

        fixture.finishDrag(at: point)

        XCTAssertEqual(fixture.manager.worldSeq, worldSeq)
        XCTAssertEqual(fixture.columns(fixture.source), tokens.map { [$0] })
    }

    private func makeFixture(_ layouts: [LayoutType]) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrossDisplayDragTests-\(UUID().uuidString)", isDirectory: true)
        let monitors = layouts.indices.map { index in
            let displayId = CGDirectDisplayID(720_000 + index)
            let frame = CGRect(x: CGFloat(index) * 1600, y: 0, width: 1600, height: 900)
            return Monitor(
                id: .init(displayId: displayId), displayId: displayId,
                frame: frame, visibleFrame: frame, hasNotch: false, name: "Display \(index + 1)"
            )
        }
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        settings.animationsEnabled = false
        settings.gestures.mouseMoveModifierKey = .control
        settings.workspaces.configurations = zip(monitors, layouts).enumerated().map { index, pair in
            WorkspaceConfiguration(
                name: "\(index + 1)",
                monitorAssignment: .specificDisplay(OutputId(from: pair.0)),
                layoutType: pair.1
            )
        }
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        let manager = controller.workspaceManager
        manager.applyMonitorConfigurationChange(monitors)
        manager.applySettings()
        let niri = NiriLayoutEngine()
        niri.animationClock = controller.animationClock
        controller.niriEngine = niri
        controller.niriLayoutHandler.syncMonitorsToNiriEngine()
        let dwindle = DwindleLayoutEngine()
        dwindle.animationClock = controller.animationClock
        controller.dwindleEngine = dwindle
        let workspaces = try layouts.indices.map { try XCTUnwrap(manager.workspaceId(named: "\($0 + 1)")) }
        for index in workspaces.indices.reversed() {
            XCTAssertTrue(manager.setActiveWorkspace(
                workspaces[index], on: monitors[index].id, updateInteractionMonitor: index == 0
            ))
        }
        controller.layoutRefreshController.resetState()
        controller.mouseEventHandler.pressedMouseButtonsProvider = { 1 }
        return Fixture(
            controller: controller,
            niri: niri,
            dwindle: dwindle,
            monitors: monitors,
            workspaces: workspaces
        )
    }

    private func addWindow(_ windowId: Int, to workspaceId: WorkspaceDescriptor.ID, _ fixture: Fixture) -> WindowToken {
        let manager = fixture.manager
        let token = manager.addWindow(
            WindowAdmissionTestSupport.axRef(for: WindowToken(pid: 8_660, windowId: windowId)),
            pid: 8_660,
            windowId: windowId,
            to: workspaceId
        )
        manager.withEngineMutationScope(in: workspaceId) {
            switch manager.activeLayoutKind(for: workspaceId) {
            case .niri:
                let selection = fixture.niri.columns(in: workspaceId).last?.windowNodes.last?.id
                _ = fixture.niri.addWindow(token: token, to: workspaceId, afterSelection: selection)
            case .dwindle:
                _ = fixture.dwindle.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
            }
        }
        return token
    }

    private func stack(
        _ token: WindowToken,
        onto target: WindowToken,
        in workspaceId: WorkspaceDescriptor.ID,
        _ fixture: Fixture
    ) throws {
        XCTAssertTrue(fixture.controller.commitWorkspaceBarDrop(
            .niriStack(workspaceId, target: target, position: .after),
            source: .init(tokens: [token], workspaceId: workspaceId, isFloating: false)
        ))
        XCTAssertTrue(try XCTUnwrap(fixture.niri.findColumn(
            containing: XCTUnwrap(fixture.niri.findNode(for: target, in: workspaceId)),
            in: workspaceId
        )).windowNodes.contains { $0.token == token })
    }

    private func dropPoint(in frame: CGRect, _ direction: Direction) -> CGPoint {
        switch direction {
        case .left: CGPoint(x: frame.minX + frame.width * 0.1, y: frame.midY)
        case .right: CGPoint(x: frame.maxX - frame.width * 0.1, y: frame.midY)
        case .up: CGPoint(x: frame.midX, y: frame.maxY - frame.height * 0.1)
        case .down: CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.1)
        }
    }

    private func constraints(minWidth: CGFloat = 0, minHeight: CGFloat) -> WindowSizeConstraints {
        WindowSizeConstraints(minSize: CGSize(width: minWidth, height: minHeight), maxSize: .zero, isFixed: false)
    }
}
