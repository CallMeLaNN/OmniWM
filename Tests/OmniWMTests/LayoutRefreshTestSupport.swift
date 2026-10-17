// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

@MainActor
enum LayoutRefreshTestSupport {
    private enum Failure: Error {
        case refreshAlreadyActive
    }

    static func block(
        _ controller: WMController,
        in workspaceId: WorkspaceDescriptor.ID,
        reason: RefreshReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Task<Void, Never> {
        let refreshController = controller.layoutRefreshController
        guard refreshController.layoutState.activeRefreshTask == nil,
              refreshController.layoutState.activeRefresh == nil
        else {
            XCTFail("Cannot replace an active layout refresh", file: file, line: line)
            throw Failure.refreshAlreadyActive
        }
        let blocker = Task { @MainActor in }
        refreshController.layoutState.activeRefreshTask = blocker
        refreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: reason,
            affectedWorkspaceIds: [workspaceId]
        )
        return blocker
    }

    static func unblock(_ controller: WMController, blocker: Task<Void, Never>) {
        blocker.cancel()
        let refreshController = controller.layoutRefreshController
        refreshController.layoutState.activeRefreshTask = nil
        refreshController.layoutState.activeRefresh = nil
        refreshController.layoutState.pendingRefresh = nil
    }

    static func withBlocked<T>(
        _ controller: WMController,
        in workspaceId: WorkspaceDescriptor.ID,
        reason: RefreshReason,
        _ body: () throws -> T
    ) throws -> T {
        let blocker = try block(controller, in: workspaceId, reason: reason)
        defer { unblock(controller, blocker: blocker) }
        return try body()
    }
}
