// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

enum OverviewSelection: Equatable {
    case window(WindowHandle)
    case workspace(WorkspaceDescriptor.ID)
    case newWorkspace(Monitor.ID)

    var windowHandle: WindowHandle? {
        guard case let .window(handle) = self else { return nil }
        return handle
    }

    func frame(in layout: OverviewLayout) -> CGRect? {
        switch self {
        case let .window(handle):
            layout.window(for: handle)?.overviewFrame
        case let .workspace(id):
            layout.workspaceSections.first { $0.workspaceId == id && $0.isEmpty }?.visibleFrame
        case let .newWorkspace(id):
            layout.newWorkspaceTarget.flatMap { $0.monitorId == id ? $0.frame : nil }
        }
    }
}

extension OverviewNavigation {
    static func selections(in layout: OverviewLayout, searching: Bool) -> [OverviewSelection] {
        var selections: [OverviewSelection] = []
        for section in layout.workspaceSections {
            if section.isEmpty, !searching {
                selections.append(.workspace(section.workspaceId))
            } else {
                selections.append(contentsOf: section.windows.filter(\.matchesSearch).map { .window($0.handle) })
            }
        }
        if !searching, let target = layout.newWorkspaceTarget {
            selections.append(.newWorkspace(target.monitorId))
        }
        return selections
    }

    static func cycledSelection(
        in layout: OverviewLayout,
        from current: OverviewSelection?,
        forward: Bool,
        searching: Bool
    ) -> OverviewSelection? {
        let candidates = selections(in: layout, searching: searching)
        guard !candidates.isEmpty else { return nil }
        guard let current, let index = candidates.firstIndex(of: current) else { return candidates.first }
        let nextIndex = index + (forward ? 1 : -1)
        return candidates.indices.contains(nextIndex) ? candidates[nextIndex] : current
    }

    static func nextSelection(
        in layout: OverviewLayout,
        from current: OverviewSelection?,
        direction: Direction,
        searching: Bool
    ) -> OverviewSelection? {
        let candidates = selections(in: layout, searching: searching)
        guard let current, candidates.contains(current), let frame = current.frame(in: layout) else {
            return candidates.first
        }
        if direction == .left || direction == .right {
            guard let handle = current.windowHandle else { return current }
            return findNextWindow(in: layout, from: handle, direction: direction).map(OverviewSelection.window)
        }
        let movingUp = direction == .up
        let windowCandidate = current.windowHandle.flatMap {
            findNextWindow(in: layout, from: $0, direction: direction).map(OverviewSelection.window)
        }
        var best = windowCandidate
        var bestDistance = best?.frame(in: layout).map { abs($0.midY - frame.midY) } ?? .infinity
        var bestHorizontal = best?.frame(in: layout).map { abs($0.midX - frame.midX) } ?? .infinity
        for candidate in candidates where candidate != current {
            if let handle = candidate.windowHandle {
                if current.windowHandle != nil || layout.window(for: handle)?.isDisplayed != true { continue }
            }
            guard let candidateFrame = candidate.frame(in: layout) else { continue }
            let delta = candidateFrame.midY - frame.midY
            guard movingUp ? delta > 0 : delta < 0 else { continue }
            let distance = abs(delta)
            let horizontal = abs(candidateFrame.midX - frame.midX)
            if distance < bestDistance || (distance == bestDistance && horizontal < bestHorizontal) {
                best = candidate
                bestDistance = distance
                bestHorizontal = horizontal
            }
        }
        return best ?? current
    }
}
