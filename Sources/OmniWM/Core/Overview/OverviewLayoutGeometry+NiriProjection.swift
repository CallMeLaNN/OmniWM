// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

extension OverviewLayoutGeometry {
    struct NiriWorkspaceProjection {
        let section: OverviewWorkspaceSection
        let columns: [OverviewNiriColumn]
        let columnDropZones: [OverviewColumnDropZone]
    }

    func buildNiriWorkspaceProjection(
        workspace: OverviewWorkspaceLayoutItem,
        snapshot: NiriOverviewWorkspaceSnapshot,
        windows: [(WindowHandle, OverviewWindowLayoutData)],
        searchQuery: String,
        currentY: inout CGFloat
    ) -> NiriWorkspaceProjection? {
        guard !snapshot.columns.isEmpty else { return nil }
        let labelFrame = makeWorkspaceLabelFrame(currentY: &currentY)
        let visibleFrame = visibleFrame(top: currentY, scale: stripScale)
        let windowsByToken = Dictionary(windows.map { ($0.1.token, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [OverviewWindowItem] = []
        var columns: [OverviewNiriColumn] = []
        var tiledTokens: Set<WindowToken> = []
        for column in snapshot.columns {
            let members = makeNiriColumnItems(
                column,
                windowsByToken: windowsByToken,
                visibleFrame: visibleFrame,
                searchQuery: searchQuery
            )
            items.append(contentsOf: members)
            tiledTokens.formUnion(column.tiles.map(\.token))
            let frame = column.stripFrame.map { project($0, into: visibleFrame, scale: stripScale) }
                ?? members.reduce(CGRect.null) { $0.union($1.overviewFrame) }
            if !members.isEmpty {
                columns.append(OverviewNiriColumn(
                    workspaceId: workspace.id,
                    columnIndex: column.index,
                    frame: frame,
                    windowHandles: members.map(\.handle),
                    isTabbed: column.isTabbed
                ))
            }
        }
        items.append(contentsOf: makeFloatingItems(
            windows.filter { !tiledTokens.contains($0.1.token) },
            visibleFrame: visibleFrame,
            searchQuery: searchQuery
        ))
        var section = makeWorkspaceSection(
            workspace: workspace,
            windows: items,
            labelFrame: labelFrame,
            visibleFrame: visibleFrame,
            currentY: &currentY
        )
        section.orientation = snapshot.strip?.orientation ?? .horizontal
        return NiriWorkspaceProjection(
            section: section,
            columns: columns,
            columnDropZones: buildNiriColumnDropZones(section: section, columns: columns)
        )
    }

    private func makeFloatingItems(
        _ windows: [(WindowHandle, OverviewWindowLayoutData)],
        visibleFrame: CGRect,
        searchQuery: String
    ) -> [OverviewWindowItem] {
        windows.map { handle, data in
            makeWindowItem(
                handle: handle,
                workspaceId: data.workspaceId,
                windowData: data,
                overviewFrame: project(
                    normalizedSourceFrame(data.floatingPreviewFrame ?? data.frame),
                    into: visibleFrame,
                    scale: stripScale
                ),
                searchQuery: searchQuery
            )
        }
    }

    private func makeNiriColumnItems(
        _ column: NiriOverviewColumnSnapshot,
        windowsByToken: [WindowToken: (WindowHandle, OverviewWindowLayoutData)],
        visibleFrame: CGRect,
        searchQuery: String
    ) -> [OverviewWindowItem] {
        let members = column.tiles.compactMap { tile -> OverviewWindowItem? in
            guard let (handle, data) = windowsByToken[tile.token] else { return nil }
            var item = makeWindowItem(
                handle: handle, workspaceId: data.workspaceId, windowData: data,
                overviewFrame: project(tile.stripFrame ?? data.frame, into: visibleFrame, scale: stripScale),
                searchQuery: searchQuery
            )
            item.isTiled = true
            item.isViewportAnchored = tile.isViewportAnchored
            return item
        }
        let displayed = members.first { !searchQuery.isEmpty && $0.matchesSearch }?.handle
            ?? column.activeToken.flatMap { windowsByToken[$0]?.0 } ?? members.first?.handle
        return members.map {
            var item = $0
            item.isDisplayed = !column.isTabbed || item.handle == displayed
            return item
        }
    }

    private func buildNiriColumnDropZones(
        section: OverviewWorkspaceSection,
        columns: [OverviewNiriColumn]
    ) -> [OverviewColumnDropZone] {
        guard let first = columns.first, let last = columns.last else { return [] }
        let axis = OverviewRibbonAxis(section.orientation)
        let edgeWidth = max(12 * metricsScale, min(30 * metricsScale, scaledWindowSpacing))
        var positions = [(first.columnIndex, axis.minimum(first.frame) - edgeWidth, edgeWidth)]
        for (left, right) in zip(columns, columns.dropFirst()) {
            positions.append((
                right.columnIndex,
                axis.maximum(left.frame),
                max(0, axis.minimum(right.frame) - axis.maximum(left.frame))
            ))
        }
        positions.append((last.columnIndex + 1, axis.maximum(last.frame), edgeWidth))
        return positions.map { index, start, span in
            OverviewColumnDropZone(
                workspaceId: section.workspaceId,
                insertIndex: index,
                frame: axis.frame(start: start, span: span, across: section.ribbonFrame)
            )
        }
    }
}
