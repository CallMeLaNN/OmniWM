// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

extension OverviewLayoutGeometry {
    func buildGenericWorkspaceSection(
        workspace: OverviewWorkspaceLayoutItem,
        windows: [(WindowHandle, OverviewWindowLayoutData)],
        dwindleGroups: [OverviewDwindleGroup] = [],
        searchQuery: String,
        currentY: inout CGFloat
    ) -> OverviewWorkspaceSection? {
        guard !windows.isEmpty else { return nil }

        let orderedWindows = windows.sorted { lhs, rhs in
            compareWindowsForPreview(lhs.1, rhs.1)
        }

        let labelFrame = makeWorkspaceLabelFrame(currentY: &currentY)
        let visibleFrame = visibleFrame(top: currentY, scale: stripScale)

        var windowItems: [OverviewWindowItem] = []
        windowItems.reserveCapacity(orderedWindows.count)
        let windowsByHandle = dwindleGroups.isEmpty ? [:] : Dictionary(uniqueKeysWithValues: windows)
        let groupByHandle = Dictionary(uniqueKeysWithValues: dwindleGroups.enumerated().flatMap { index, group in
            group.windowHandles.map { ($0, index) }
        })
        var emittedGroups: Set<Int> = []

        for (handle, windowData) in orderedWindows {
            if let groupIndex = groupByHandle[handle] {
                guard emittedGroups.insert(groupIndex).inserted else { continue }
                let group = dwindleGroups[groupIndex]
                let members = group.windowHandles.compactMap { member -> OverviewWindowItem? in
                    guard let data = windowsByHandle[member] else { return nil }
                    return makeGenericWindowItem(
                        handle: member, data: data, visibleFrame: visibleFrame, searchQuery: searchQuery
                    )
                }
                let displayed = members.first { !searchQuery.isEmpty && $0.matchesSearch }?.handle
                    ?? members.first { $0.handle == group.activeHandle }?.handle ?? members.first?.handle
                for var member in members {
                    member.isDisplayed = member.handle == displayed
                    windowItems.append(member)
                }
            } else {
                windowItems.append(makeGenericWindowItem(
                    handle: handle, data: windowData, visibleFrame: visibleFrame, searchQuery: searchQuery
                ))
            }
        }

        return makeWorkspaceSection(
            workspace: workspace,
            windows: windowItems,
            labelFrame: labelFrame,
            visibleFrame: visibleFrame,
            currentY: &currentY
        )
    }

    private func makeGenericWindowItem(
        handle: WindowHandle,
        data: OverviewWindowLayoutData,
        visibleFrame: CGRect,
        searchQuery: String
    ) -> OverviewWindowItem {
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

    private func compareWindowsForPreview(
        _ lhs: OverviewWindowLayoutData,
        _ rhs: OverviewWindowLayoutData
    ) -> Bool {
        let lhsFrame = normalizedSourceFrame(lhs.floatingPreviewFrame ?? lhs.frame)
        let rhsFrame = normalizedSourceFrame(rhs.floatingPreviewFrame ?? rhs.frame)
        if abs(lhsFrame.maxY - rhsFrame.maxY) > 1 {
            return lhsFrame.maxY > rhsFrame.maxY
        }
        if abs(lhsFrame.minX - rhsFrame.minX) > 1 {
            return lhsFrame.minX < rhsFrame.minX
        }
        return lhs.title < rhs.title
    }

    func normalizedSourceFrame(_ frame: CGRect) -> CGRect {
        let standardized = frame.standardized
        return CGRect(
            x: standardized.minX,
            y: standardized.minY,
            width: max(standardized.width, 1),
            height: max(standardized.height, 1)
        )
    }
}
