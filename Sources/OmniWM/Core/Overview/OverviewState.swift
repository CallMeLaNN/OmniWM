// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

enum OverviewState {
    case closed
    case opening
    case open
    case closing(targetWindow: WindowHandle?)

    var isOpen: Bool {
        switch self {
        case .open,
             .opening,
             .closing:
            return true
        case .closed:
            return false
        }
    }

    var isAnimating: Bool {
        switch self {
        case .opening,
             .closing:
            return true
        case .open,
             .closed:
            return false
        }
    }

    var gestureAction: OverviewGestureAction {
        switch self {
        case .closed:
            .open
        case .open:
            .close
        case .opening,
             .closing:
            .resume
        }
    }
}

struct OverviewWorkspaceSection {
    let workspaceId: WorkspaceDescriptor.ID
    let name: String
    var windows: [OverviewWindowItem]
    var sectionFrame: CGRect
    var labelFrame: CGRect
    var gridFrame: CGRect
    var isActive: Bool
    var displayId: CGDirectDisplayID?
    var viewportFrame: CGRect = .zero
    var visibleFrame: CGRect = .zero
    var ribbonFrame: CGRect = .zero
    var orientation: Monitor.Orientation = .horizontal
    var hiddenColumnsBefore = 0
    var hiddenColumnsAfter = 0

    var isEmpty: Bool {
        windows.isEmpty
    }

    var contentScale: CGFloat {
        viewportFrame.width > 0 ? visibleFrame.width / viewportFrame.width : 1
    }

    func clipFrame(for window: OverviewWindowItem) -> CGRect {
        window.isTiled ? ribbonFrame : visibleFrame
    }

    func containsInRibbon(_ frame: CGRect) -> Bool {
        ribbonFrame.isEmpty || frame.intersects(ribbonFrame)
    }
}

struct OverviewOverflowPill: Equatable {
    enum Edge: Equatable {
        case leading
        case trailing
    }

    let workspaceId: WorkspaceDescriptor.ID
    let edge: Edge
    let count: Int
    let frame: CGRect
    var orientation: Monitor.Orientation = .horizontal
}

struct OverviewNewWorkspaceTarget {
    let monitorId: Monitor.ID
    let frame: CGRect
}

struct OverviewDwindleGroup: Equatable {
    let id: DwindleTileId
    let windowHandles: [WindowHandle]
    let activeHandle: WindowHandle
}

struct OverviewWindowItem {
    let handle: WindowHandle
    let windowId: Int
    let workspaceId: WorkspaceDescriptor.ID
    let title: String
    let appName: String
    let appIcon: CGImage?
    let originalFrame: CGRect
    var overviewFrame: CGRect
    let matchesSearch: Bool
    var restFrame: CGRect?
    var isNativeFullscreen = false
    var contentScale: CGFloat = 1
    var isTiled = false
    var isViewportAnchored = false
    var isDisplayed = true

    var closeButtonFrame: CGRect {
        let size: CGFloat = 20
        let padding: CGFloat = 6
        return CGRect(
            x: overviewFrame.maxX - size - padding,
            y: overviewFrame.maxY - size - padding,
            width: size,
            height: size
        )
    }

    func translated(by delta: CGFloat, orientation: Monitor.Orientation) -> OverviewWindowItem {
        var translated = self
        translated.overviewFrame = overviewFrame.offsetBy(
            dx: orientation == .horizontal ? delta : 0,
            dy: orientation == .vertical ? delta : 0
        )
        return translated
    }

    func interpolatedFrame(progress: Double) -> CGRect {
        let fraction = CGFloat(progress)
        let from = restFrame ?? originalFrame
        return CGRect(
            x: from.origin.x + (overviewFrame.origin.x - from.origin.x) * fraction,
            y: from.origin.y + (overviewFrame.origin.y - from.origin.y) * fraction,
            width: from.width + (overviewFrame.width - from.width) * fraction,
            height: from.height + (overviewFrame.height - from.height) * fraction
        )
    }
}

struct OverviewLayout {
    struct WindowHit {
        let window: OverviewWindowItem
        let isCloseButton: Bool
    }

    private struct WindowPosition {
        let sectionIndex: Int
        let windowIndex: Int
    }

    private(set) var workspaceSections: [OverviewWorkspaceSection]
    private(set) var anchorWorkspaceId: WorkspaceDescriptor.ID?

    var searchBarFrame: CGRect
    var viewportFrame: CGRect
    var totalContentHeight: CGFloat
    var scrollOffset: CGFloat
    var scale: CGFloat
    var niriColumnDropZonesByWorkspace: [WorkspaceDescriptor.ID: [OverviewColumnDropZone]]
    var dragTarget: OverviewDragTarget?
    var newWorkspaceTarget: OverviewNewWorkspaceTarget?
    var niriColumnsByWorkspace: [WorkspaceDescriptor.ID: [OverviewNiriColumn]]
    var dwindleGroupsByWorkspace: [WorkspaceDescriptor.ID: [OverviewDwindleGroup]]
    private(set) var stripPanByWorkspace: [WorkspaceDescriptor.ID: CGFloat]
    private var windowPositionByHandle: [WindowHandle: WindowPosition]

    init() {
        workspaceSections = []
        searchBarFrame = .zero
        viewportFrame = .zero
        totalContentHeight = 0
        scrollOffset = 0
        scale = 1.0
        niriColumnDropZonesByWorkspace = [:]
        dragTarget = nil
        newWorkspaceTarget = nil
        niriColumnsByWorkspace = [:]
        dwindleGroupsByWorkspace = [:]
        stripPanByWorkspace = [:]
        windowPositionByHandle = [:]
    }

    var allWindows: [OverviewWindowItem] {
        workspaceSections.flatMap(\.windows)
    }

    mutating func replaceWorkspaceSections(_ sections: [OverviewWorkspaceSection]) {
        workspaceSections = sections
        rebuildWindowIndex()
    }

    mutating func settleRestFrames(anchorWorkspaceId: WorkspaceDescriptor.ID?) {
        self.anchorWorkspaceId = anchorWorkspaceId
        let anchor = workspaceSections
            .first { $0.workspaceId == anchorWorkspaceId }
            .flatMap { OverviewRenderGeometry.restAnchor(for: $0) }
        for sectionIndex in workspaceSections.indices {
            let isAnchor = workspaceSections[sectionIndex].workspaceId == anchorWorkspaceId
            for windowIndex in workspaceSections[sectionIndex].windows.indices {
                let overviewFrame = workspaceSections[sectionIndex].windows[windowIndex].overviewFrame
                workspaceSections[sectionIndex].windows[windowIndex].restFrame = isAnchor
                    ? nil
                    : anchor.map { OverviewRenderGeometry.restFrame(for: overviewFrame, anchor: $0) }
            }
        }
    }

    private mutating func rebuildWindowIndex() {
        windowPositionByHandle.removeAll(keepingCapacity: true)
        for sectionIndex in workspaceSections.indices {
            for windowIndex in workspaceSections[sectionIndex].windows.indices {
                let handle = workspaceSections[sectionIndex].windows[windowIndex].handle
                windowPositionByHandle[handle] = WindowPosition(sectionIndex: sectionIndex, windowIndex: windowIndex)
            }
        }
    }

    func windowAt(point: CGPoint) -> OverviewWindowItem? {
        windowHit(at: point)?.window
    }

    func windowHit(at point: CGPoint) -> WindowHit? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        for section in workspaceSections {
            for window in section.windows.reversed()
                where window.matchesSearch && window.isDisplayed
            {
                let clip = section.clipFrame(for: window)
                if clip.isEmpty || clip.contains(adjustedPoint), window.overviewFrame.contains(adjustedPoint) {
                    return WindowHit(
                        window: window,
                        isCloseButton: window.closeButtonFrame.contains(adjustedPoint)
                    )
                }
            }
        }
        return nil
    }

    func workspaceSection(at point: CGPoint) -> OverviewWorkspaceSection? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        for section in workspaceSections where section.sectionFrame.contains(adjustedPoint) {
            return section
        }
        return nil
    }

    func ribbonSection(at point: CGPoint) -> OverviewWorkspaceSection? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        for section in workspaceSections where section.ribbonFrame.contains(adjustedPoint) {
            return section
        }
        return nil
    }

    func niriColumn(containing handle: WindowHandle, in workspaceId: WorkspaceDescriptor.ID) -> OverviewNiriColumn? {
        niriColumnsByWorkspace[workspaceId]?.first { $0.windowHandles.contains(handle) }
    }

    func stripPanRange(for workspaceId: WorkspaceDescriptor.ID) -> ClosedRange<CGFloat> {
        guard let section = workspaceSections.first(where: { $0.workspaceId == workspaceId }),
              !section.ribbonFrame.isEmpty
        else { return 0 ... 0 }
        let content = section.windows.lazy.filter { $0.isTiled && !$0.isViewportAnchored }
            .reduce(CGRect.null) { $0.union($1.overviewFrame) }
        guard !content.isNull else { return 0 ... 0 }
        let axis = OverviewRibbonAxis(section.orientation)
        let leading = axis.minimum(section.ribbonFrame) - axis.minimum(content)
        let trailing = axis.maximum(section.ribbonFrame) - axis.maximum(content)
        if axis.span(content) <= axis.span(section.ribbonFrame) {
            return min(0, leading) ... max(0, trailing)
        }
        return min(0, trailing) ... max(0, leading)
    }

    @discardableResult
    mutating func panStrip(_ workspaceId: WorkspaceDescriptor.ID, by delta: CGFloat) -> Bool {
        guard let sectionIndex = workspaceSections.firstIndex(where: { $0.workspaceId == workspaceId }) else {
            return false
        }
        return translateStrip(
            at: sectionIndex,
            by: delta.clamped(to: stripPanRange(for: workspaceId))
        )
    }

    mutating func restoreStripPan(_ workspaceId: WorkspaceDescriptor.ID, to desktopPan: CGFloat) {
        guard let sectionIndex = workspaceSections.firstIndex(where: { $0.workspaceId == workspaceId }),
              workspaceSections[sectionIndex].windows.contains(where: { $0.isTiled && !$0.isViewportAnchored })
        else { return }
        let delta = (desktopPan - (stripPanByWorkspace[workspaceId] ?? 0)) * workspaceSections[sectionIndex]
            .contentScale
        _ = translateStrip(at: sectionIndex, by: delta)
    }

    private mutating func translateStrip(at sectionIndex: Int, by delta: CGFloat) -> Bool {
        guard delta.isFinite, abs(delta) > 0.0001 else { return false }
        let workspaceId = workspaceSections[sectionIndex].workspaceId
        let orientation = workspaceSections[sectionIndex].orientation
        let axis = OverviewRibbonAxis(orientation)
        for windowIndex in workspaceSections[sectionIndex].windows.indices {
            let window = workspaceSections[sectionIndex].windows[windowIndex]
            if window.isTiled && !window.isViewportAnchored {
                workspaceSections[sectionIndex].windows[windowIndex] = window.translated(
                    by: delta,
                    orientation: orientation
                )
            }
        }
        niriColumnsByWorkspace[workspaceId] = niriColumnsByWorkspace[workspaceId]?.map {
            var column = $0
            if column.windowHandles.contains(where: { window(for: $0)?.isViewportAnchored == false }) {
                column.frame = axis.offset(column.frame, by: delta)
            }
            return column
        }
        niriColumnDropZonesByWorkspace[workspaceId] = niriColumnDropZonesByWorkspace[workspaceId]?.map {
            OverviewColumnDropZone(
                workspaceId: $0.workspaceId,
                insertIndex: $0.insertIndex,
                frame: axis.offset($0.frame, by: delta)
            )
        }
        stripPanByWorkspace[workspaceId, default: 0] += delta / workspaceSections[sectionIndex].contentScale
        refreshOverflow(sectionIndex: sectionIndex)
        return true
    }

    mutating func clearPendingStripPans() {
        stripPanByWorkspace.removeAll()
    }

    mutating func revealTab(_ handle: WindowHandle) {
        guard let position = windowPositionByHandle[handle],
              let members = tabGroup(containing: handle, in: workspaceSections[position.sectionIndex].workspaceId)
        else { return }
        for index in workspaceSections[position.sectionIndex].windows.indices {
            let member = workspaceSections[position.sectionIndex].windows[index].handle
            if members.contains(member) {
                workspaceSections[position.sectionIndex].windows[index].isDisplayed = member == handle
            }
        }
        refreshOverflow(sectionIndex: position.sectionIndex)
    }

    func tabGroup(containing handle: WindowHandle, in workspaceId: WorkspaceDescriptor.ID) -> [WindowHandle]? {
        if let column = niriColumn(containing: handle, in: workspaceId), column.isTabbed {
            return column.windowHandles
        }
        return dwindleGroupsByWorkspace[workspaceId]?
            .first(where: { $0.windowHandles.contains(handle) })?.windowHandles
    }

    func tabbedWindowGroups(in workspaceId: WorkspaceDescriptor.ID) -> [[WindowHandle]] {
        let columns = (niriColumnsByWorkspace[workspaceId] ?? []).filter(\.isTabbed).map(\.windowHandles)
        return columns + (dwindleGroupsByWorkspace[workspaceId] ?? []).map(\.windowHandles)
    }

    func stripPanRevealing(_ handle: WindowHandle) -> CGFloat {
        guard let window = window(for: handle), window.isTiled, !window.isViewportAnchored,
              let section = workspaceSections.first(where: { $0.workspaceId == window.workspaceId }),
              !section.ribbonFrame.isEmpty
        else { return 0 }
        let axis = OverviewRibbonAxis(section.orientation)
        if axis.minimum(window.overviewFrame) < axis.minimum(section.ribbonFrame) {
            return axis.minimum(section.ribbonFrame) - axis.minimum(window.overviewFrame)
        }
        if axis.maximum(window.overviewFrame) > axis.maximum(section.ribbonFrame) {
            return axis.maximum(section.ribbonFrame) - axis.maximum(window.overviewFrame)
        }
        return 0
    }

    mutating func refreshOverflow() {
        for sectionIndex in workspaceSections.indices { refreshOverflow(sectionIndex: sectionIndex) }
    }

    private mutating func refreshOverflow(sectionIndex: Int) {
        let section = workspaceSections[sectionIndex]
        let axis = OverviewRibbonAxis(section.orientation)
        workspaceSections[sectionIndex].hiddenColumnsBefore = section.windows.count {
            $0.isTiled && $0.isDisplayed && axis.maximum($0.overviewFrame) <= axis.minimum(section.ribbonFrame)
        }
        workspaceSections[sectionIndex].hiddenColumnsAfter = section.windows.count {
            $0.isTiled && $0.isDisplayed && axis.minimum($0.overviewFrame) >= axis.maximum(section.ribbonFrame)
        }
    }

    func columnDropZone(at point: CGPoint) -> OverviewColumnDropZone? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        for (_, zones) in niriColumnDropZonesByWorkspace {
            for zone in zones where zone.frame.contains(adjustedPoint) {
                guard workspaceSections.first(where: { $0.workspaceId == zone.workspaceId })?
                    .ribbonFrame.contains(adjustedPoint) == true else { continue }
                return zone
            }
        }
        return nil
    }

    func insertPosition(for window: OverviewWindowItem, at point: CGPoint) -> InsertPosition {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        let orientation = workspaceSections.first { $0.workspaceId == window.workspaceId }?.orientation ?? .horizontal
        return orientation == .horizontal
            ? (adjustedPoint.y > window.overviewFrame.midY ? .before : .after)
            : (adjustedPoint.x > window.overviewFrame.midX ? .before : .after)
    }

    func resolveDragTarget(at point: CGPoint, draggedHandle: WindowHandle?) -> OverviewDragTarget? {
        let adjustedPoint = CGPoint(x: point.x, y: point.y + scrollOffset)
        if let newWorkspaceTarget, newWorkspaceTarget.frame.contains(adjustedPoint) {
            return .newWorkspace(monitorId: newWorkspaceTarget.monitorId)
        }
        if let zone = columnDropZone(at: point) {
            return .niriColumnInsert(
                workspaceId: zone.workspaceId,
                insertIndex: zone.insertIndex
            )
        }

        if let window = windowAt(point: point) {
            guard window.handle != draggedHandle else { return nil }
            if !window.isNativeFullscreen, niriColumn(containing: window.handle, in: window.workspaceId) != nil {
                return .niriWindowInsert(
                    workspaceId: window.workspaceId,
                    targetHandle: window.handle,
                    position: insertPosition(for: window, at: point)
                )
            }
            return .workspaceMove(workspaceId: window.workspaceId)
        }

        if let section = workspaceSection(at: point) {
            return .workspaceMove(workspaceId: section.workspaceId)
        }

        return nil
    }

    func window(for handle: WindowHandle) -> OverviewWindowItem? {
        guard let position = windowPositionByHandle[handle],
              workspaceSections.indices.contains(position.sectionIndex),
              workspaceSections[position.sectionIndex].windows.indices.contains(position.windowIndex)
        else {
            return nil
        }
        return workspaceSections[position.sectionIndex].windows[position.windowIndex]
    }
}

struct OverviewNiriColumn: Equatable {
    let workspaceId: WorkspaceDescriptor.ID
    let columnIndex: Int
    var frame: CGRect
    let windowHandles: [WindowHandle]
    var isTabbed = false
}

enum OverviewDragTarget: Equatable {
    case floatingPlacement(destination: OverviewFloatingDestination, frame: CGRect, previewFrame: CGRect)
    case newWorkspace(monitorId: Monitor.ID)
    case niriWindowInsert(
        workspaceId: WorkspaceDescriptor.ID,
        targetHandle: WindowHandle,
        position: InsertPosition
    )
    case niriColumnInsert(
        workspaceId: WorkspaceDescriptor.ID,
        insertIndex: Int
    )
    case workspaceMove(
        workspaceId: WorkspaceDescriptor.ID
    )
}

struct OverviewColumnDropZone: Equatable {
    let workspaceId: WorkspaceDescriptor.ID
    let insertIndex: Int
    let frame: CGRect
}
