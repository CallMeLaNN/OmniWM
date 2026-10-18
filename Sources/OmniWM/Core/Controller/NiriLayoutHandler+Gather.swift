// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum NiriGatherReach: Equatable {
    case workspace
    case monitor
    case all
}

struct NiriGatherDestination: Equatable {
    let workspaceId: WorkspaceDescriptor.ID
    let monitor: Monitor
}

enum NiriGatherWindowIssue: Equatable {
    case notFound
    case outsideReach
    case scratchpad
    case nativeFullscreen
    case appHidden
    case minimized
    case nativeWithdrawn
    case floating
    case unsupportedLayout
    case layoutConflict
    case layoutFullscreen
}

enum NiriGatherFailure: Equatable {
    case destinationUnavailable
    case unsupportedLayout
    case windows([WindowToken: NiriGatherWindowIssue])
    case doesNotFit
}

enum NiriGatherOutcome: Equatable {
    case gathered(NiriGatherPlan)
    case unchanged
    case refused(NiriGatherFailure)
}

extension NiriLayoutHandler {
    func gatherDestination() -> NiriGatherDestination? {
        guard let projection = controller?.interactionWorkspaceProjection(),
              let monitor = projection.monitor,
              let workspace = projection.workspace
        else {
            return nil
        }
        return NiriGatherDestination(workspaceId: workspace.id, monitor: monitor)
    }

    func gatherWindows(
        _ tokens: [WindowToken],
        from reach: NiriGatherReach,
        into destination: NiriGatherDestination
    ) -> NiriGatherOutcome {
        guard let controller else { return .refused(.destinationUnavailable) }
        let manager = controller.workspaceManager
        let destinationId = destination.workspaceId
        guard manager.descriptor(for: destinationId) != nil else { return .refused(.destinationUnavailable) }
        guard manager.activeLayoutKind(for: destinationId) == .niri,
              let engine = controller.niriEngine
        else {
            return .refused(.unsupportedLayout)
        }

        var issues = gatherEligibilityIssues(for: tokens, from: reach, into: destination)
        var sourceWorkspaceIds: [WindowToken: WorkspaceDescriptor.ID] = [:]
        for token in tokens where issues[token] == nil {
            sourceWorkspaceIds[token] = manager.workspace(for: token)
        }
        let geometry = controller.niriInteractionGeometry(for: destination.monitor)
        let request = NiriGatherRequest(
            tokens: tokens.filter { issues[$0] == nil },
            sourceWorkspaceIds: sourceWorkspaceIds,
            destinationWorkspaceId: destinationId,
            geometry: NiriSizingGeometry(
                workingFrame: geometry.workingFrame,
                gaps: geometry.innerGap,
                orientation: resolvedOrientation(for: destinationId, monitor: destination.monitor, engine: engine)
            ),
            nativeFocusToken: manager.nativeManagedFocusToken
        )

        switch manager.planNiriGather(request) {
        case .unchanged:
            return issues.isEmpty ? .unchanged : .refused(.windows(issues))
        case let .refused(.windows(engineIssues)):
            for (token, issue) in engineIssues {
                issues[token] = issue == .layoutFullscreen ? .layoutFullscreen : .layoutConflict
            }
            return .refused(.windows(issues))
        case .refused(.doesNotFit):
            return .refused(issues.isEmpty ? .doesNotFit : .windows(issues))
        case let .ready(plan):
            guard issues.isEmpty else { return .refused(.windows(issues)) }
            guard manager.commitNiriGather(plan) else {
                return .refused(.windows(plan.request.tokens.reduce(into: [:]) { $0[$1] = .layoutConflict }))
            }
            controller.layoutRefreshController.requestLayoutCommandRelayout(
                affectedWorkspaceIds: Set(plan.affectedWorkspaceIds)
            )
            return .gathered(plan)
        }
    }

    func gatherEligibilityIssues(
        for tokens: [WindowToken],
        from reach: NiriGatherReach,
        into destination: NiriGatherDestination
    ) -> [WindowToken: NiriGatherWindowIssue] {
        guard let manager = controller?.workspaceManager else { return [:] }
        var issues: [WindowToken: NiriGatherWindowIssue] = [:]
        for token in tokens {
            guard let entry = manager.entry(for: token), manager.handle(for: token) != nil else {
                issues[token] = .notFound
                continue
            }
            issues[token] = gatherReach(reach, includes: entry.workspaceId, destination: destination, manager: manager)
                ? gatherStateIssue(for: entry, manager: manager)
                : .outsideReach
        }
        return issues
    }

    private func gatherReach(
        _ reach: NiriGatherReach,
        includes workspaceId: WorkspaceDescriptor.ID,
        destination: NiriGatherDestination,
        manager: WorkspaceManager
    ) -> Bool {
        switch reach {
        case .workspace:
            workspaceId == destination.workspaceId
        case .monitor:
            manager.monitorId(for: workspaceId) == destination.monitor.id
        case .all:
            true
        }
    }

    private func gatherStateIssue(for entry: WindowState, manager: WorkspaceManager) -> NiriGatherWindowIssue? {
        if manager.scratchpadIndex(for: entry.token) != nil || entry.hiddenState?.isScratchpad == true {
            return .scratchpad
        }
        if entry.layoutReason == .nativeFullscreen || manager.nativeFullscreenRecord(for: entry.token) != nil {
            return .nativeFullscreen
        }
        if manager.isAppHidden(pid: entry.pid) { return .appHidden }
        if entry.observedState.isMinimized { return .minimized }
        if entry.observedState.isNativeWithdrawn { return .nativeWithdrawn }
        if entry.mode == .floating { return .floating }
        if manager.activeLayoutKind(for: entry.workspaceId) != .niri { return .unsupportedLayout }
        return nil
    }
}
