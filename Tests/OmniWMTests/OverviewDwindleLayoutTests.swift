// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import XCTest

@MainActor
final class OverviewDwindleLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testGroupsKeepSpatialOrderAndEngineMemberOrder() throws {
        let fixture = makeFixture()
        let layout = makeLayout(fixture)
        let section = try XCTUnwrap(layout.workspaceSections.first)

        XCTAssertEqual(section.windows.map(\.handle), fixture.handles)
        XCTAssertEqual(section.windows.filter(\.isDisplayed).map(\.handle), [
            fixture.handles[0], fixture.handles[3], fixture.handles[5]
        ])
        XCTAssertEqual(layout.searchResultCount, 6)
        XCTAssertEqual(layout.tabMembers(for: fixture.handles[0]).map(\.handle), Array(fixture.handles.prefix(3)))
        XCTAssertTrue(layout.niriColumnsByWorkspace.isEmpty)
        XCTAssertTrue(layout.niriColumnDropZonesByWorkspace.isEmpty)
        XCTAssertTrue(section.windows.allSatisfy { !$0.isTiled })
    }

    func testInactiveTitleMatchUsesGroupGeometryAndHitTarget() throws {
        let fixture = makeFixture()
        let original = makeLayout(fixture)
        let layout = makeLayout(fixture, query: "bUdGeT")
        let matching = try XCTUnwrap(layout.window(for: fixture.handles[1]))

        XCTAssertTrue(matching.matchesSearch)
        XCTAssertTrue(matching.isDisplayed)
        XCTAssertEqual(layout.window(for: fixture.handles[0])?.isDisplayed, false)
        XCTAssertEqual(matching.overviewFrame, original.window(for: fixture.handles[0])?.overviewFrame)
        XCTAssertEqual(matching.originalFrame, fixture.windows[fixture.handles[0]]?.frame)
        XCTAssertEqual(layout.searchFeedback(query: "bUdGeT"), "1 result")
        XCTAssertEqual(
            layout.windowAt(point: CGPoint(x: matching.overviewFrame.midX, y: matching.overviewFrame.midY))?
                .handle,
            fixture.handles[1]
        )
        XCTAssertEqual(OverviewSearchFilter.firstMatchingWindow(in: layout)?.handle, fixture.handles[1])
        XCTAssertEqual(layout.tabMembers(for: fixture.handles[1]).map(\.handle), [fixture.handles[1]])
    }

    func testAppMatchesCountEveryMemberAndPickerPreservesGroupOrder() {
        let fixture = makeFixture()
        let layout = makeLayout(fixture, query: "sAfArI")

        XCTAssertEqual(layout.searchResultCount, 3)
        XCTAssertEqual(layout.tabMembers(for: fixture.handles[0]).map(\.title), [
            "Zeta plan", "Budget 2026", "Alpha notes"
        ])
        XCTAssertEqual(
            layout.allWindows.filter { $0.matchesSearch && $0.isDisplayed }.map(\.handle),
            [fixture.handles[0]]
        )
    }

    func testMultipleMatchesRevealIndividuallyWithoutChangingTileGeometry() throws {
        let fixture = makeFixture()
        var layout = makeLayout(fixture, query: "log")
        let firstFrame = try XCTUnwrap(layout.window(for: fixture.handles[3])?.overviewFrame)

        layout.revealTab(fixture.handles[4])

        XCTAssertEqual(layout.searchResultCount, 2)
        XCTAssertEqual(layout.window(for: fixture.handles[3])?.isDisplayed, false)
        XCTAssertEqual(layout.window(for: fixture.handles[4])?.isDisplayed, true)
        XCTAssertEqual(layout.window(for: fixture.handles[4])?.overviewFrame, firstFrame)
        XCTAssertEqual(layout.window(for: fixture.handles[0])?.isDisplayed, true)
        XCTAssertEqual(layout.stripPanByWorkspace, [:])
    }

    func testNoMatchesRetainsWorkspaceGeometryWithoutSelectableResults() throws {
        let fixture = makeFixture()
        let original = makeLayout(fixture)
        let layout = makeLayout(fixture, query: "No such window")

        XCTAssertEqual(layout.searchResultCount, 0)
        XCTAssertNil(OverviewSearchFilter.firstMatchingWindow(in: layout))
        XCTAssertTrue(OverviewNavigation.selections(in: layout, searching: true).isEmpty)
        XCTAssertEqual(layout.allWindows.map(\.overviewFrame), original.allWindows.map(\.overviewFrame))
        XCTAssertEqual(layout.workspaceSections.first?.ribbonFrame, original.workspaceSections.first?.ribbonFrame)
        XCTAssertTrue(layout.tabControls(for: try XCTUnwrap(layout.workspaceSections.first)).isEmpty)
    }

    func testTabTraversalRevealsEveryMemberAndStopsAtEndpoints() {
        let fixture = makeFixture()
        var layout = makeLayout(fixture)
        var selection: OverviewSelection? = .window(fixture.handles[0])

        for handle in fixture.handles.dropFirst() {
            selection = OverviewNavigation.cycledSelection(in: layout, from: selection, forward: true, searching: false)
            XCTAssertEqual(selection, .window(handle))
            layout.revealTab(handle)
            XCTAssertEqual(layout.window(for: handle)?.isDisplayed, true)
        }
        XCTAssertEqual(
            OverviewNavigation.cycledSelection(in: layout, from: selection, forward: true, searching: false),
            selection
        )
        for handle in fixture.handles.dropLast().reversed() {
            selection = OverviewNavigation.cycledSelection(
                in: layout,
                from: selection,
                forward: false,
                searching: false
            )
            XCTAssertEqual(selection, .window(handle))
        }
        XCTAssertEqual(
            OverviewNavigation.cycledSelection(in: layout, from: selection, forward: false, searching: false),
            selection
        )
    }

    func testDirectionalNavigationUsesDisplayedTilesInsteadOfHiddenMembers() {
        let fixture = makeFixture()
        var layout = makeLayout(fixture)
        layout.revealTab(fixture.handles[4])

        XCTAssertEqual(
            OverviewNavigation.findNextWindow(in: layout, from: fixture.handles[0], direction: .right),
            fixture.handles[4]
        )
        XCTAssertEqual(
            OverviewNavigation.findNextWindow(in: layout, from: fixture.handles[4], direction: .down),
            fixture.handles[5]
        )
    }

    func testMissingActiveMemberShowsFirstSurvivingMember() {
        var fixture = makeFixture()
        fixture.windows.removeValue(forKey: fixture.handles[0])
        let layout = makeLayout(fixture)

        XCTAssertEqual(layout.window(for: fixture.handles[1])?.isDisplayed, true)
        XCTAssertEqual(layout.window(for: fixture.handles[2])?.isDisplayed, false)
        XCTAssertEqual(layout.searchResultCount, 5)
        XCTAssertEqual(layout.tabMembers(for: fixture.handles[1]).map(\.handle), Array(fixture.handles[1 ... 2]))
    }

    func testOnlyDisplayedGroupMembersRequestPreviewCapture() {
        let fixture = makeFixture()
        var layout = makeLayout(fixture)
        layout.revealTab(fixture.handles[1])
        let requests = OverviewThumbnailSizing.captureRequests(projections: [OverviewPreviewProjection(
            layout: layout, viewportFrame: screen, backingScaleFactor: 2
        )])

        XCTAssertEqual(requests.map(\.handle), [fixture.handles[1], fixture.handles[3], fixture.handles[5]])
        XCTAssertEqual(layout.allWindows.count, 6)
    }

    private struct Fixture {
        let workspaceId: WorkspaceDescriptor.ID
        let handles: [WindowHandle]
        var windows: [WindowHandle: OverviewWindowLayoutData]
        let groups: [OverviewDwindleGroup]
    }

    private func makeFixture() -> Fixture {
        let workspaceId = WorkspaceDescriptor.ID()
        let handles = (1 ... 6).map { WindowHandle(id: WindowToken(pid: 2, windowId: $0)) }
        let titles = ["Zeta plan", "Budget 2026", "Alpha notes", "Build log", "Deploy log", "Weekend ideas"]
        let frames = Array(repeating: CGRect(x: 20, y: 40, width: 600, height: 720), count: 3)
            + Array(repeating: CGRect(x: 650, y: 400, width: 500, height: 360), count: 2)
            + [CGRect(x: 650, y: 40, width: 500, height: 340)]
        let windows = Dictionary(uniqueKeysWithValues: handles.enumerated().map { index, handle in
            (handle, OverviewWindowLayoutData(
                token: handle.id, workspaceId: workspaceId, title: titles[index],
                appName: index < 3 ? "Safari" : "Terminal", appIcon: nil, frame: frames[index]
            ))
        })
        return Fixture(
            workspaceId: workspaceId, handles: handles, windows: windows,
            groups: [
                OverviewDwindleGroup(
                    id: DwindleTileId(),
                    windowHandles: Array(handles.prefix(3)),
                    activeHandle: handles[0]
                ),
                OverviewDwindleGroup(
                    id: DwindleTileId(),
                    windowHandles: Array(handles[3 ... 4]),
                    activeHandle: handles[3]
                )
            ]
        )
    }

    private func makeLayout(_ fixture: Fixture, query: String = "") -> OverviewLayout {
        OverviewLayoutCalculator(screenFrame: screen, scale: 1).calculateLayout(
            workspaces: [OverviewWorkspaceLayoutItem(id: fixture.workspaceId, name: "Dwindle", isActive: true)],
            windows: fixture.windows,
            dwindleGroupsByWorkspace: [fixture.workspaceId: fixture.groups],
            searchQuery: query
        )
    }
}
