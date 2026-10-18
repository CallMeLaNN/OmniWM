// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension MouseEventHandler {
    func adoptNativeResizeIfEligible(
        _ drag: inout MouseInputState.NativeTitleBarDrag,
        entry: WindowState,
        observedFrame: CGRect?
    ) -> Bool {
        guard let controller,
              controller.settings.gestures.adoptNativeResize,
              let start = drag.adoptionStartFrame,
              let observedFrame,
              entry.layoutReason == .standard,
              !controller.axManager.isAwaitingFrameWrite(entry.windowId),
              controller.axManager.lastAppliedFrame(for: entry.windowId)?.approximatelyEqual(
                  to: start,
                  tolerance: FrameTolerance.frameWrite
              ) == true
        else {
            return false
        }
        let edges = Self.nativeResizeEdges(from: start, to: observedFrame)
        guard !edges.isEmpty else { return false }
        let adopted = switch controller.workspaceManager.activeLayoutKind(for: entry.workspaceId) {
        case .niri:
            adoptNiriNativeResize(entry, edges: edges, from: start, to: observedFrame)
        case .dwindle:
            adoptDwindleNativeResize(entry, edges: edges, from: start, to: observedFrame)
        }
        guard adopted else { return false }
        drag.adoptionStartFrame = nil
        drag.phase = .awaitingCorrection
        drag.receivedFrameChange = false
        return true
    }

    static func nativeResizeEdges(from start: CGRect, to observed: CGRect) -> ResizeEdge {
        func moved(_ before: CGFloat, _ after: CGFloat) -> Bool {
            abs(after - before) > FrameTolerance.screenMatch
        }
        let left = moved(start.minX, observed.minX)
        let right = moved(start.maxX, observed.maxX)
        let bottom = moved(start.minY, observed.minY)
        let top = moved(start.maxY, observed.maxY)
        guard !(left && right), !(bottom && top) else { return [] }
        var edges: ResizeEdge = []
        if left { edges.insert(.left) }
        if right { edges.insert(.right) }
        if bottom { edges.insert(.bottom) }
        if top { edges.insert(.top) }
        return edges
    }

    private static func nativeResizeLocation(
        _ edges: ResizeEdge,
        from start: CGRect,
        to observed: CGRect
    ) -> CGPoint {
        let dx: CGFloat = if edges.contains(.left) {
            observed.minX - start.minX
        } else if edges.contains(.right) {
            observed.maxX - start.maxX
        } else {
            0
        }
        let dy: CGFloat = if edges.contains(.bottom) {
            observed.minY - start.minY
        } else if edges.contains(.top) {
            observed.maxY - start.maxY
        } else {
            0
        }
        return CGPoint(x: start.minX + dx, y: start.minY + dy)
    }

    private func adoptNiriNativeResize(
        _ entry: WindowState,
        edges: ResizeEdge,
        from start: CGRect,
        to observed: CGRect
    ) -> Bool {
        let workspaceId = entry.workspaceId
        guard let controller,
              let engine = controller.niriEngine,
              let monitor = controller.workspaceManager.monitor(for: workspaceId),
              !controller.niriLayoutHandler.hasScrollAnimation(for: workspaceId),
              let window = engine.findNode(for: entry.token, in: workspaceId),
              engine.interactiveResizeTarget(windowId: window.id, in: workspaceId) != nil
        else {
            return false
        }
        let context = nativeResizeContext(controller, engine: engine, workspaceId: workspaceId, monitor: monitor)
        let horizontal = context.orientation == .horizontal
        let primaryEdges = edges.intersection(horizontal ? [.left, .right] : [.top, .bottom])
        let adoptsSecondary = !edges.subtracting(primaryEdges).isEmpty
            && !(horizontal && engine.singleWindowLayoutContext(in: workspaceId) != nil)
        guard !primaryEdges.isEmpty || adoptsSecondary else { return false }

        var changed = false
        controller.workspaceManager.withNiriViewportState(for: workspaceId) { viewportState in
            if adoptsSecondary {
                changed = adoptNiriSecondarySpan(
                    window,
                    span: horizontal ? observed.height : observed.width,
                    renderedSpan: horizontal ? start.height : start.width,
                    context: context
                )
            }
            if !primaryEdges.isEmpty,
               resizeNiriPrimarySpan(
                   window,
                   edges: primaryEdges,
                   frames: (start, observed),
                   context: context,
                   state: &viewportState
               )
            {
                changed = true
            }
        }
        guard changed else { return false }
        controller.axManager.forceApplyNextFrame(for: entry.windowId)
        settleNiriResize(entry.token, in: workspaceId)
        return true
    }

    private func adoptNiriSecondarySpan(
        _ window: NiriWindow,
        span: CGFloat,
        renderedSpan: CGFloat,
        context: NiriInteractionContext
    ) -> Bool {
        guard let engine = controller?.niriEngine,
              let column = engine.findColumn(containing: window, in: context.workspaceId)
        else {
            return false
        }
        let siblings = engine.projectedWindows(in: column, workspaceId: context.workspaceId)
            .map { (window: $0, height: $0.height, width: $0.windowWidth) }
        let savedHeight = window.savedHeight
        let sizingMode = window.sizingMode
        engine.setWindowSecondarySpan(
            window,
            change: .setFixed(span),
            in: context.workspaceId,
            geometry: context.sizingGeometry
        )
        let applied = context.orientation == .horizontal ? window.height : window.windowWidth
        guard case let .fixed(value) = applied, abs(value - renderedSpan) <= FrameTolerance.frameWrite else {
            return true
        }
        for sibling in siblings {
            sibling.window.height = sibling.height
            sibling.window.windowWidth = sibling.width
        }
        window.savedHeight = savedHeight
        window.sizingMode = sizingMode
        return false
    }

    private func nativeResizeContext(
        _ controller: WMController,
        engine: NiriLayoutEngine,
        workspaceId: WorkspaceDescriptor.ID,
        monitor: Monitor
    ) -> NiriInteractionContext {
        let geometry = controller.niriInteractionGeometry(for: monitor)
        return NiriInteractionContext(
            workspaceId: workspaceId,
            motion: controller.motionPolicy.snapshot(),
            workingFrame: geometry.workingFrame,
            gaps: geometry.innerGap,
            orientation: resolvedNiriOrientation(engine: engine, workspaceId: workspaceId, monitor: monitor)
        )
    }

    private func resizeNiriPrimarySpan(
        _ window: NiriWindow,
        edges: ResizeEdge,
        frames: (start: CGRect, observed: CGRect),
        context: NiriInteractionContext,
        state: inout ViewportState
    ) -> Bool {
        guard let engine = controller?.niriEngine,
              engine.interactiveResizeBegin(
                  windowId: window.id,
                  edges: edges,
                  startLocation: frames.start.origin,
                  in: context.workspaceId,
                  orientation: context.orientation,
                  viewOffset: state.viewOffset
              )
        else {
            return false
        }
        guard engine.interactiveResizeUpdate(
            currentLocation: Self.nativeResizeLocation(edges, from: frames.start, to: frames.observed),
            monitorFrame: context.workingFrame,
            gaps: LayoutGaps(horizontal: context.gaps, vertical: context.gaps),
            viewportState: { $0(&state) }
        ) else {
            engine.clearInteractiveResize()
            return false
        }
        engine.interactiveResizeEnd(
            motion: context.motion,
            state: &state,
            workingFrame: context.workingFrame,
            gaps: context.gaps
        )
        return true
    }

    private func adoptDwindleNativeResize(
        _ entry: WindowState,
        edges: ResizeEdge,
        from start: CGRect,
        to observed: CGRect
    ) -> Bool {
        let workspaceId = entry.workspaceId
        guard let controller,
              let engine = controller.dwindleEngine,
              let monitor = controller.workspaceManager.monitor(for: workspaceId)
        else {
            return false
        }
        controller.dwindleLayoutHandler.refreshEngineConstraints(workspaceId: workspaceId, monitor: monitor)
        guard engine.interactiveResizeBegin(
            token: entry.token,
            edges: edges,
            startLocation: start.origin,
            in: workspaceId,
            innerGap: controller.resolvedDwindleSettings(for: monitor).innerGap,
            edgePolicy: .exact
        ) else {
            return false
        }
        guard engine.interactiveResizeUpdate(
            currentLocation: Self.nativeResizeLocation(edges, from: start, to: observed)
        ) else {
            engine.clearInteractiveResize()
            return false
        }
        controller.layoutRefreshController.stopDwindleAnimation(for: monitor.displayId)
        engine.cancelAnimations(in: workspaceId)
        controller.axManager.forceApplyNextFrame(for: entry.windowId)
        controller.layoutRefreshController.renderDwindleInteractiveResize(for: workspaceId)
        finishDwindleResize()
        return true
    }
}
