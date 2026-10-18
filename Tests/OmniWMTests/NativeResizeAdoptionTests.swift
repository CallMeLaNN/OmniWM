// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

private final class ReportedFrame {
    var frame: CGRect?

    init(_ frame: CGRect?) {
        self.frame = frame
    }
}

@MainActor
final class NativeResizeAdoptionTests: NiriInteractionTestCase {
    @MainActor
    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let monitor: Monitor
        let tokens: [WindowToken]

        var handler: MouseEventHandler {
            controller.mouseEventHandler
        }

        var manager: WorkspaceManager {
            controller.workspaceManager
        }

        var phase: MouseInputState.NativeTitleBarDragPhase? {
            handler.state.nativeTitleBarDrag?.phase
        }

        func entry(_ token: WindowToken) throws -> WindowState {
            try XCTUnwrap(manager.entry(for: token))
        }

        func niriNode(_ token: WindowToken) throws -> NiriWindow {
            try XCTUnwrap(controller.niriEngine?.findNode(for: token, in: workspaceId))
        }

        func frames() throws -> [WindowToken: CGRect] {
            let workingFrame = controller.insetWorkingFrame(for: monitor)
            switch manager.activeLayoutKind(for: workspaceId) {
            case .niri:
                let gap = controller.innerGap(for: monitor)
                return try XCTUnwrap(controller.niriEngine).calculateLayout(
                    state: manager.niriViewportState(for: workspaceId),
                    workspaceId: workspaceId,
                    monitorFrame: workingFrame,
                    gaps: (horizontal: gap, vertical: gap),
                    orientation: controller.settings.monitors.effectiveOrientation(for: monitor)
                )
            case .dwindle:
                let engine = try XCTUnwrap(controller.dwindleEngine)
                return engine.calculateLayout(
                    for: workspaceId,
                    screen: workingFrame,
                    calculationSettings: controller.dwindleLayoutHandler.calculationSettings(
                        controller.resolvedDwindleSettings(for: monitor),
                        from: engine
                    )
                )
            }
        }

        func frame(_ token: WindowToken) throws -> CGRect {
            try XCTUnwrap(frames()[token])
        }

        func confirmLayout() throws {
            for (token, frame) in try frames() {
                controller.axManager.confirmFrameWrite(for: token.windowId, frame: frame)
            }
        }

        func beginDrag(_ token: WindowToken) throws {
            handler.retireNativeTitleBarDragAtInputBoundary()
            handler.pressedMouseButtonsProvider = { MouseEventHandler.MouseButton.left.pressedMask }
            let start = try frame(token)
            XCTAssertFalse(handler.dispatchMouseDown(
                at: start.center,
                modifiers: [],
                windowIdUnderPointer: token.windowId
            ))
            handler.dispatchMouseDragged(at: CGPoint(x: start.center.x + 5, y: start.center.y))
            XCTAssertEqual(phase, .dragging)
        }

        func release(_ token: WindowToken, at observed: CGRect) throws {
            let reported = ReportedFrame(controller.axManager.lastAppliedFrame(for: token.windowId))
            handler.nativeWindowFrameProvider = { _ in reported.frame }
            try beginDrag(token)
            reported.frame = observed
            let entry = try entry(token)
            XCTAssertTrue(handler.handleNativeTitleBarDragFrameChanged(for: entry))
            handler.dispatchMouseUp(at: observed.center)
        }

        func wireFrameApplyCallbacks() {
            controller.axManager.onFrameApplySucceeded = { [weak controller] result in
                controller?.serviceLifecycleManager.handleFrameApplySucceeded(result)
            }
            controller.axManager.onStableSizeClamp = { [weak controller] result in
                controller?.adoptObservedMinimumAfterStableSizeClamp(result)
            }
        }

        func confirmWrite(of token: WindowToken) throws {
            _ = controller.axManager.cancelPendingFrameRetry(for: token.windowId)
            let target = try frame(token)
            let request = try XCTUnwrap(controller.axManager.stageFrameWrite(
                for: AXFrameApplicationTarget(pid: token.pid, window: entry(token).axRef, frame: target)
            ))
            controller.axManager
                .handleFrameApplyResults([WindowAdmissionTestSupport.successfulFrameResult(request: request)])
            XCTAssertEqual(controller.axManager.lastAppliedFrame(for: token.windowId), target)
        }

        func refuseWrite(of token: WindowToken, growingWidthBy growth: CGFloat) throws {
            let target = try frame(token)
            let window = try entry(token).axRef
            let observed = CGRect(x: target.minX, y: target.minY, width: target.width + growth, height: target.height)
            controller.axManager.forceApplyNextFrame(for: token.windowId)
            let first = try XCTUnwrap(controller.axManager.stageFrameWrite(
                for: AXFrameApplicationTarget(pid: token.pid, window: window, frame: target)
            ))
            controller.axManager.handleFrameApplyResults([
                WindowAdmissionTestSupport.verificationMismatchFrameResult(request: first, observed: observed)
            ])
            _ = controller.axManager.cancelPendingFrameRetry(for: token.windowId)
            let retry = try XCTUnwrap(WindowAdmissionTestSupport.frameRequest(
                controller.axManager.frameLedger,
                pid: token.pid,
                window: window,
                frame: target,
                isRetry: true
            ))
            controller.axManager.handleFrameApplyResults([
                WindowAdmissionTestSupport.verificationMismatchFrameResult(request: retry, observed: observed)
            ])
        }
    }

    func testSettingOffKeepsCorrectingNativeEdgeResizes() throws {
        for (index, layout) in [LayoutType.niri, .dwindle].enumerated() {
            let fixture = try makeFixture(layout, pid: pid_t(834_001 + index))
            fixture.controller.settings.gestures.adoptNativeResize = false
            let blocker = blockRefreshes(fixture)
            defer { unblockRefreshes(fixture, blocker: blocker) }
            let before = try fixture.frames()
            let worldSeq = fixture.manager.worldSeq
            let start = try fixture.frame(fixture.tokens[0])

            try fixture.release(fixture.tokens[0], at: grown(start, right: 200))

            XCTAssertEqual(fixture.phase, .awaitingCorrection, "\(layout)")
            XCTAssertEqual(
                fixture.controller.layoutRefreshController.layoutState.pendingRefresh?.affectedWorkspaceIds,
                [fixture.workspaceId]
            )
            XCTAssertEqual(try fixture.frames(), before, "\(layout)")
            XCTAssertEqual(fixture.manager.worldSeq, worldSeq, "\(layout)")
        }
    }

    func testNiriRightEdgeWidensOnlyThatColumn() throws {
        let fixture = try makeFixture(.niri, pid: 834_011)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let (resized, neighbor) = (fixture.tokens[0], fixture.tokens[1])
        let start = try fixture.frame(resized)
        let neighborWidth = try fixture.frame(neighbor).width
        let worldSeq = fixture.manager.worldSeq

        try fixture.release(resized, at: grown(start, right: 200))

        XCTAssertEqual(try fixture.frame(resized).width, start.width + 200, accuracy: 1)
        XCTAssertEqual(try fixture.frame(neighbor).width, neighborWidth, accuracy: 1)
        XCTAssertEqual(fixture.phase, .awaitingCorrection)
        XCTAssertNil(fixture.handler.state.nativeTitleBarDrag?.adoptionStartFrame)
        XCTAssertGreaterThan(fixture.manager.worldSeq, worldSeq)
        XCTAssertTrue(
            fixture.controller.layoutRefreshController.layoutState.pendingRefresh != nil
                || fixture.controller.niriLayoutHandler.scrollAnimationByDisplay[fixture.monitor.displayId]
                == fixture.workspaceId
        )
    }

    func testNiriLeftEdgeKeepsTheRightEdgeInPlace() throws {
        let fixture = try makeFixture(.niri, pid: 834_012)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let resized = fixture.tokens[1]
        let start = try fixture.frame(resized)

        try fixture.release(resized, at: grown(start, left: 150))

        let adopted = try fixture.frame(resized)
        XCTAssertEqual(adopted.width, start.width + 150, accuracy: 1)
        XCTAssertEqual(adopted.maxX, start.maxX, accuracy: 1)
    }

    func testNiriStackedEdgeSetsTheExactHeight() throws {
        let fixture = try makeFixture(.niri, stacked: true, pid: 834_013)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let (top, bottom) = try stackedTopAndBottom(fixture)
        let topStart = try fixture.frame(top)
        let bottomStart = try fixture.frame(bottom)

        try fixture.release(top, at: grown(topStart, bottom: 100))

        XCTAssertEqual(try fixture.frame(top).height, topStart.height + 100, accuracy: 1)
        XCTAssertEqual(try fixture.frame(bottom).height, bottomStart.height - 100, accuracy: 1)
        XCTAssertEqual(try fixture.frame(top).width, topStart.width, accuracy: 1)
    }

    func testStackedShrinkUsesTheRenderedSpanNotTheStoredOne() throws {
        for portrait in [false, true] {
            let fixture = try makeFixture(.niri, stacked: true, portrait: portrait, pid: portrait ? 834_015 : 834_014)
            let blocker = blockRefreshes(fixture)
            defer { unblockRefreshes(fixture, blocker: blocker) }
            let (resized, sibling) = try portrait ? stackedLeftAndRight(fixture) : stackedTopAndBottom(fixture)
            let workingFrame = fixture.controller.insetWorkingFrame(for: fixture.monitor)
            let resizedNode = try fixture.niriNode(resized)
            let siblingNode = try fixture.niriNode(sibling)
            if portrait {
                resizedNode.windowWidth = .fixed(workingFrame.width)
                siblingNode.constraints.minSize.width = workingFrame.width / 2
            } else {
                resizedNode.height = .fixed(workingFrame.height)
                siblingNode.constraints.minSize.height = workingFrame.height / 2
            }
            try fixture.confirmLayout()
            let rendered = try fixture.frame(resized)
            XCTAssertLessThan(
                portrait ? rendered.width : rendered.height,
                portrait ? workingFrame.width : workingFrame.height
            )
            let shrunk = portrait ? grown(rendered, right: -50) : grown(rendered, bottom: -50)

            try fixture.release(resized, at: shrunk)

            let adopted = try fixture.frame(resized)
            XCTAssertEqual(
                portrait ? adopted.width : adopted.height,
                portrait ? shrunk.width : shrunk.height,
                accuracy: 1
            )
        }
    }

    func testClampedStackedResizeLeavesTheStackUntouched() throws {
        let fixture = try makeFixture(.niri, stacked: true, pid: 834_016)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let (top, bottom) = try stackedTopAndBottom(fixture)
        let topNode = try fixture.niriNode(top)
        let bottomNode = try fixture.niriNode(bottom)
        bottomNode.constraints.minSize.height = try fixture.frame(bottom).height
        let heights = (topNode.height, bottomNode.height)
        let before = try fixture.frames()

        try fixture.release(top, at: grown(fixture.frame(top), bottom: 100))

        XCTAssertEqual(fixture.phase, .awaitingCorrection)
        XCTAssertEqual(topNode.height, heights.0)
        XCTAssertEqual(bottomNode.height, heights.1)
        XCTAssertEqual(try fixture.frames(), before)
    }

    func testDwindleSplitEdgeMovesTheSharedSplit() throws {
        let fixture = try makeFixture(.dwindle, pid: 834_021)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let (left, right) = (fixture.tokens[0], fixture.tokens[1])
        let leftStart = try fixture.frame(left)
        let rightStart = try fixture.frame(right)
        XCTAssertLessThan(leftStart.maxX, rightStart.minX + 1)

        try fixture.release(left, at: grown(leftStart, right: 150))

        XCTAssertEqual(try fixture.frame(left).width, leftStart.width + 150, accuracy: 1)
        XCTAssertEqual(try fixture.frame(right).width, rightStart.width - 150, accuracy: 1)
        XCTAssertEqual(fixture.phase, .awaitingCorrection)
        XCTAssertNil(fixture.controller.dwindleEngine?.interactiveResize)
    }

    func testDwindleOuterEdgeIsCorrectedAndACornerAdoptsOnlyTheSplitAxis() throws {
        let outer = try makeFixture(.dwindle, pid: 834_022)
        let outerBlocker = blockRefreshes(outer)
        defer { unblockRefreshes(outer, blocker: outerBlocker) }
        let before = try outer.frames()

        try outer.release(outer.tokens[0], at: grown(try outer.frame(outer.tokens[0]), left: 100))

        XCTAssertEqual(outer.phase, .awaitingCorrection)
        XCTAssertEqual(try outer.frames(), before)

        let corner = try makeFixture(.dwindle, pid: 834_023)
        let cornerBlocker = blockRefreshes(corner)
        defer { unblockRefreshes(corner, blocker: cornerBlocker) }
        let start = try corner.frame(corner.tokens[0])

        try corner.release(corner.tokens[0], at: grown(grown(start, right: 150), top: -60))

        let adopted = try corner.frame(corner.tokens[0])
        XCTAssertEqual(adopted.width, start.width + 150, accuracy: 1)
        XCTAssertEqual(adopted.height, start.height, accuracy: 1)
    }

    func testPlainMovesAndTwoSidedResizesAreStillCorrected() throws {
        var pid: pid_t = 834_031
        for layout in [LayoutType.niri, .dwindle] {
            for change in [
                { (frame: CGRect) in frame.offsetBy(dx: 40, dy: 0) },
                { (frame: CGRect) in frame.offsetBy(dx: 0, dy: -30) },
                { (frame: CGRect) in frame.insetBy(dx: -20, dy: 0) }
            ] {
                let fixture = try makeFixture(layout, pid: pid)
                pid += 1
                let blocker = blockRefreshes(fixture)
                defer { unblockRefreshes(fixture, blocker: blocker) }
                let before = try fixture.frames()
                let worldSeq = fixture.manager.worldSeq

                try fixture.release(fixture.tokens[0], at: change(try fixture.frame(fixture.tokens[0])))

                XCTAssertEqual(fixture.phase, .awaitingCorrection, "\(layout)")
                XCTAssertEqual(try fixture.frames(), before, "\(layout)")
                XCTAssertEqual(fixture.manager.worldSeq, worldSeq, "\(layout)")
            }
        }
    }

    func testDelayedFinalFrameIsAdoptedOnce() throws {
        let fixture = try makeFixture(.niri, pid: 834_041)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let token = fixture.tokens[0]
        let start = try fixture.frame(token)
        fixture.handler.nativeWindowFrameProvider = { _ in start }
        try fixture.beginDrag(token)
        fixture.handler.dispatchMouseUp(at: start.center)
        XCTAssertEqual(fixture.phase, .awaitingFrameChange)

        fixture.handler.nativeWindowFrameProvider = { _ in self.grown(start, right: 200) }
        XCTAssertTrue(fixture.handler.handleNativeTitleBarDragFrameChanged(for: try fixture.entry(token)))
        XCTAssertEqual(try fixture.frame(token).width, start.width + 200, accuracy: 1)
        let worldSeq = fixture.manager.worldSeq

        fixture.handler.nativeWindowFrameProvider = { _ in self.grown(start, right: 260) }
        XCTAssertTrue(fixture.handler.handleNativeTitleBarDragFrameChanged(for: try fixture.entry(token)))
        XCTAssertEqual(try fixture.frame(token).width, start.width + 200, accuracy: 1)
        XCTAssertEqual(fixture.manager.worldSeq, worldSeq)
    }

    func testDelayedResizeAfterASettledCorrectionIsCorrected() throws {
        let fixture = try makeFixture(.niri, pid: 834_042)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let token = fixture.tokens[0]
        let start = try fixture.frame(token)
        try fixture.release(token, at: start.offsetBy(dx: 40, dy: 0))
        XCTAssertEqual(fixture.phase, .awaitingCorrection)
        fixture.handler.nativeWindowFrameProvider = { _ in start }
        fixture.handler.handleNativeTitleBarDragFrameApplySucceeded(
            try succeeded(fixture, token: token, frame: start, requestId: 1)
        )
        XCTAssertEqual(fixture.phase, .awaitingFrameChange)
        XCTAssertNil(fixture.handler.state.nativeTitleBarDrag?.adoptionStartFrame)

        fixture.handler.nativeWindowFrameProvider = { _ in self.grown(start, right: 200) }
        XCTAssertTrue(fixture.handler.handleNativeTitleBarDragFrameChanged(for: try fixture.entry(token)))

        XCTAssertEqual(fixture.phase, .awaitingCorrection)
        XCTAssertEqual(try fixture.frame(token).width, start.width, accuracy: 1)
    }

    func testPendingWriteAtDragStartDisablesAdoption() throws {
        let fixture = try makeFixture(.niri, pid: 834_043)
        let blocker = blockRefreshes(fixture)
        defer { unblockRefreshes(fixture, blocker: blocker) }
        let token = fixture.tokens[0]
        let start = try fixture.frame(token)
        fixture.controller.axManager.applyFramesParallel([
            AXFrameApplicationTarget(
                pid: token.pid,
                window: try fixture.entry(token).axRef,
                frame: start.offsetBy(dx: 0, dy: -20)
            )
        ])
        XCTAssertTrue(fixture.controller.axManager.isAwaitingFrameWrite(token.windowId))
        let grownFrame = grown(start, right: 200)
        fixture.handler.nativeWindowFrameProvider = { _ in grownFrame }

        try fixture.beginDrag(token)
        XCTAssertNil(fixture.handler.state.nativeTitleBarDrag?.adoptionStartFrame)
        fixture.handler.dispatchMouseUp(at: grownFrame.center)

        XCTAssertEqual(fixture.phase, .awaitingCorrection)
        XCTAssertEqual(try fixture.frame(token).width, start.width, accuracy: 1)
    }

    func testVerifiedAdoptedWritesLearnNothingWhileRefusedWritesStillLearn() throws {
        for (index, layout) in [LayoutType.niri, .dwindle].enumerated() {
            let fixture = try makeFixture(layout, pid: pid_t(834_051 + index))
            fixture.wireFrameApplyCallbacks()
            let blocker = blockRefreshes(fixture)
            defer { unblockRefreshes(fixture, blocker: blocker) }
            let (resized, neighbor) = (fixture.tokens[0], fixture.tokens[1])
            let start = try fixture.frame(resized)

            try fixture.release(resized, at: grown(start, right: 200))
            XCTAssertEqual(try fixture.frame(resized).width, start.width + 200, accuracy: 1, "\(layout)")
            try fixture.confirmWrite(of: resized)
            XCTAssertEqual(fixture.phase, .awaitingFrameChange, "\(layout)")
            fixture.controller.layoutRefreshController.stopScrollAnimation(for: fixture.monitor.displayId)

            let widened = try fixture.frame(resized)
            try fixture.release(resized, at: grown(widened, right: -300))
            XCTAssertEqual(try fixture.frame(resized).width, widened.width - 300, accuracy: 1, "\(layout)")
            try fixture.confirmWrite(of: resized)
            XCTAssertNil(fixture.manager.observedSizeEvidence(for: resized), "\(layout)")
            XCTAssertNil(fixture.manager.cachedConstraints(for: resized, maxAge: .greatestFiniteMagnitude), "\(layout)")

            try fixture.refuseWrite(of: neighbor, growingWidthBy: 40)
            let neighborEvidence = try XCTUnwrap(fixture.manager.observedSizeEvidence(for: neighbor), "\(layout)")
            XCTAssertEqual(neighborEvidence.minSize.width, try fixture.frame(neighbor).width, accuracy: 41, "\(layout)")
            XCTAssertGreaterThan(neighborEvidence.minSize.width, 1, "\(layout)")
            XCTAssertNil(fixture.manager.observedSizeEvidence(for: resized), "\(layout)")

            try fixture.refuseWrite(of: resized, growingWidthBy: 10)
            let hinted = try XCTUnwrap(fixture.manager.observedSizeEvidence(for: resized), "\(layout)")
            XCTAssertLessThanOrEqual(hinted.minSize.width, 1, "\(layout)")
            XCTAssertFalse(hinted.hints.isEmpty, "\(layout)")
        }
    }

    func testSecondaryEdgesAdoptWhereverTheyRender() throws {
        let columns = try makeFixture(.niri, pid: 834_061)
        let columnsBlocker = blockRefreshes(columns)
        defer { unblockRefreshes(columns, blocker: columnsBlocker) }
        let columnStart = try columns.frame(columns.tokens[0])
        try columns.release(columns.tokens[0], at: grown(columnStart, bottom: -120))
        XCTAssertEqual(try columns.frame(columns.tokens[0]).height, columnStart.height - 120, accuracy: 1)

        let portrait = try makeFixture(.niri, portrait: true, windowCount: 1, pid: 834_062)
        let portraitBlocker = blockRefreshes(portrait)
        defer { unblockRefreshes(portrait, blocker: portraitBlocker) }
        let portraitStart = try portrait.frame(portrait.tokens[0])
        try portrait.release(portrait.tokens[0], at: grown(portraitStart, right: -150))
        XCTAssertEqual(try portrait.frame(portrait.tokens[0]).width, portraitStart.width - 150, accuracy: 1)

        let single = try makeFixture(.niri, windowCount: 1, pid: 834_063)
        let singleBlocker = blockRefreshes(single)
        defer { unblockRefreshes(single, blocker: singleBlocker) }
        let singleBefore = try single.frames()
        try single.release(single.tokens[0], at: grown(try single.frame(single.tokens[0]), bottom: -120))
        XCTAssertEqual(single.phase, .awaitingCorrection)
        XCTAssertEqual(try single.frames(), singleBefore)
    }

    func testAdoptedFrameIsTheFirstWriteForTheResizedWindow() async throws {
        let cases: [(LayoutType, Int, (CGRect) -> CGRect)] = [
            (.niri, 0, { self.grown($0, right: 200) }),
            (.niri, 1, { self.grown($0, left: 150) }),
            (.dwindle, 0, { self.grown($0, right: 150) })
        ]
        for (index, (layout, tokenIndex, change)) in cases.enumerated() {
            let fixture = try makeFixture(layout, pid: pid_t(834_071 + index))
            let token = fixture.tokens[tokenIndex]
            let observed = change(try fixture.frame(token))
            FrameApplyTrace.shared.beginCapture()
            defer { FrameApplyTrace.shared.endCapture() }

            try fixture.release(token, at: observed)
            for _ in 0 ..< 8 where fixture.controller.niriLayoutHandler.hasScrollAnimation(for: fixture.workspaceId) {
                fixture.controller.niriLayoutHandler.tickScrollAnimation(
                    targetTime: CACurrentMediaTime() + 10,
                    displayId: fixture.monitor.displayId
                )
            }
            await WindowAdmissionTestSupport.drainLayoutRefreshes(fixture.controller)

            let target = try XCTUnwrap(firstWriteTarget(for: token), "\(layout) \(tokenIndex)")
            XCTAssertEqual(target.width, observed.width, accuracy: 1, "\(layout) \(tokenIndex)")
            if tokenIndex == 1 {
                XCTAssertEqual(target.maxX, observed.maxX, accuracy: 1, "\(layout) \(tokenIndex)")
            }
        }
    }

    private func firstWriteTarget(for token: WindowToken) -> CGRect? {
        let line = FrameApplyTrace.shared.dump().split(separator: "\n").first { line in
            line.contains(" win=\(token.windowId) ") && !line.contains("cancelled") && line.contains(" target=(")
        }
        guard let line,
              let range = line.range(of: " target=(")
        else { return nil }
        let rest = line[range.upperBound...]
        guard let close = rest.firstIndex(of: ")") else { return nil }
        let numbers = rest[..<close]
            .replacingOccurrences(of: "x", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .compactMap { Double($0) }
        guard numbers.count == 4 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    private func grown(
        _ frame: CGRect,
        left: CGFloat = 0,
        right: CGFloat = 0,
        bottom: CGFloat = 0,
        top: CGFloat = 0
    ) -> CGRect {
        CGRect(
            x: frame.minX - left,
            y: frame.minY - bottom,
            width: frame.width + left + right,
            height: frame.height + bottom + top
        )
    }

    private func stackedTopAndBottom(_ fixture: Fixture) throws -> (WindowToken, WindowToken) {
        let (first, second) = (fixture.tokens[0], fixture.tokens[1])
        return try fixture.frame(first).midY > fixture.frame(second).midY ? (first, second) : (second, first)
    }

    private func stackedLeftAndRight(_ fixture: Fixture) throws -> (WindowToken, WindowToken) {
        let (first, second) = (fixture.tokens[0], fixture.tokens[1])
        return try fixture.frame(first).midX < fixture.frame(second).midX ? (first, second) : (second, first)
    }

    private func succeeded(
        _ fixture: Fixture,
        token: WindowToken,
        frame: CGRect,
        requestId: AXFrameRequestId
    ) throws -> AXFrameApplyResult {
        try AXFrameApplyResult(
            requestId: requestId,
            pid: token.pid,
            windowId: token.windowId,
            expectedWindow: fixture.entry(token).axRef,
            targetFrame: frame,
            currentFrameHint: nil,
            writeResult: AXFrameWriteResult(
                observedFrame: frame,
                writeOrder: .sizeThenPosition,
                sizeError: .success,
                positionError: .success,
                failureReason: nil
            )
        )
    }

    private func blockRefreshes(_ fixture: Fixture) -> Task<Void, Never> {
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        fixture.controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        fixture.controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [fixture.workspaceId]
        )
        return blocker
    }

    private func unblockRefreshes(_ fixture: Fixture, blocker: Task<Void, Never>) {
        blocker.cancel()
        fixture.controller.layoutRefreshController.layoutState.activeRefreshTask = nil
        fixture.controller.layoutRefreshController.layoutState.activeRefresh = nil
        fixture.controller.layoutRefreshController.layoutState.pendingRefresh = nil
    }

    private func makeFixture(
        _ layout: LayoutType,
        stacked: Bool = false,
        portrait: Bool = false,
        windowCount: Int = 2,
        pid: pid_t
    ) throws -> Fixture {
        let controller = WindowAdmissionTestSupport.controller(prefix: "NativeResizeAdoptionTests")
        addTeardownBlock { @MainActor [controller] in
            controller.hasStartedServices = false
            controller.layoutRefreshController.resetState()
            controller.mouseEventHandler.cleanup()
            controller.surfaceReconciler.cleanup()
            controller.axManager.cleanup()
        }
        let frame = portrait ? CGRect(x: 0, y: 0, width: 900, height: 1600) : workingFrame
        let monitor = Monitor(
            id: .init(displayId: 83_401),
            displayId: 83_401,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "Native Resize Adoption"
        )
        controller.settings.gestures.adoptNativeResize = true
        controller.settings.workspaces.configurations = [
            WorkspaceConfiguration(
                name: "1",
                monitorAssignment: .specificDisplay(OutputId(from: monitor)),
                layoutType: layout
            )
        ]
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        controller.workspaceManager.applySettings()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "1"))
        _ = controller.workspaceManager.focusWorkspace(named: "1")
        let tokens = (0 ..< windowCount).map { WindowToken(pid: pid, windowId: Int(pid) + 100 + $0) }
        for token in tokens {
            _ = WindowAdmissionTestSupport.track(token, in: workspaceId, controller: controller)
        }
        if layout == .niri {
            controller.enableNiriLayout()
            let engine = try XCTUnwrap(controller.niriEngine)
            let first = engine.addWindow(token: tokens[0], to: workspaceId, afterSelection: nil)
            if stacked, tokens.count > 1 {
                controller.workspaceManager.withNiriViewportState(for: workspaceId) { state in
                    engine.attachTransferredWindow(
                        NiriWindow(token: tokens[1]),
                        stackedWith: first,
                        after: true,
                        in: workspaceId,
                        state: &state
                    )
                }
            } else if tokens.count > 1 {
                _ = engine.addWindow(token: tokens[1], to: workspaceId, afterSelection: first.id)
            }
        } else {
            controller.enableDwindleLayout()
            let engine = try XCTUnwrap(controller.dwindleEngine)
            controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
                for token in tokens {
                    _ = engine.setPreselection(.right, in: workspaceId)
                    _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
                }
            }
        }
        let fixture = Fixture(controller: controller, workspaceId: workspaceId, monitor: monitor, tokens: tokens)
        if layout == .dwindle {
            controller.dwindleEngine?.cancelAnimations(in: workspaceId)
        }
        let frames = try fixture.frames()
        try fixture.confirmLayout()
        controller.axEventHandler.windowInfoProvider = { windowId in
            guard let token = tokens.first(where: { $0.windowId == Int(windowId) }) else { return nil }
            return WindowServerInfo(id: windowId, pid: token.pid, level: 0, frame: frames[token] ?? .zero)
        }
        controller.layoutRefreshController.resetState()
        controller.layoutRefreshController.displayLinkActivationForTests = { _ in true }
        controller.hasStartedServices = true
        return fixture
    }
}
