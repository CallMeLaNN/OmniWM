// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import QuartzCore
import XCTest

@MainActor
final class OverviewDwindleControlsTests: XCTestCase {
    func testDwindleControlThresholdsPreserveNiriGeometry() throws {
        let fixture = Fixture()
        for (size, style) in [
            (CGSize(width: 100, height: 92), OverviewTabControl.Style.segmented),
            (CGSize(width: 99, height: 92), .pickerOnly),
            (CGSize(width: 100, height: 91), .pickerOnly),
            (CGSize(width: 74, height: 68), .pickerOnly)
        ] {
            let layout = fixture.layout(size: size)
            let control = try XCTUnwrap(layout.tabControls(for: layout.workspaceSections[0]).first)
            XCTAssertEqual(control.style, style)
            XCTAssertEqual(control.frame.height, 22)
            XCTAssertEqual(control.frame.minX, 108)
            XCTAssertEqual(control.frame.minY, style == .segmented ? 140 : 100 + size.height - 30)
        }
        for size in [CGSize(width: 73, height: 92), CGSize(width: 100, height: 67)] {
            let layout = fixture.layout(size: size)
            XCTAssertTrue(layout.tabControls(for: layout.workspaceSections[0]).isEmpty)
            XCTAssertEqual(layout.tabMembers(for: fixture.handles[1]).count, 3)
        }
        let niri = fixture.layout(size: CGSize(width: 100, height: 60), niri: true)
        let control = try XCTUnwrap(niri.tabControls(for: niri.workspaceSections[0]).first)
        XCTAssertEqual(control.style, .segmented)
        XCTAssertEqual(control.frame, CGRect(x: 108, y: 136, width: 84, height: 22))
        let narrowNiri = fixture.layout(size: CGSize(width: 99, height: 92), niri: true)
        XCTAssertTrue(narrowNiri.tabControls(for: narrowNiri.workspaceSections[0]).isEmpty)
    }

    func testControlsClearRenderedCaptionsAndCloseTargets() throws {
        let fixture = Fixture()
        for size in [
            CGSize(width: 100, height: 92), CGSize(width: 140, height: 300),
            CGSize(width: 74, height: 68), CGSize(width: 90, height: 300)
        ] {
            let layout = fixture.layout(size: size)
            let renderer = fixture.renderer(layout)
            let control = try XCTUnwrap(layout.tabControls(for: layout.workspaceSections[0]).first)
            let item = try XCTUnwrap(layout.window(for: fixture.handles[1]))
            XCTAssertFalse(control.frame.intersects(item.closeButtonFrame))
            let card = try XCTUnwrap(renderer.windowLayers[item.handle])
            let caption = try XCTUnwrap(card.root.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
            for text in caption.sublayers?.compactMap({ $0 as? CATextLayer }) ?? [] where !text.isHidden {
                let frame = text.frame.offsetBy(
                    dx: item.overviewFrame.minX + caption.frame.minX,
                    dy: item.overviewFrame.minY + caption.frame.minY
                )
                XCTAssertFalse(control.frame.intersects(frame))
            }
            let layer = try XCTUnwrap(renderer.tabControlLayers[item.handle])
            let visibleLabels = layer.sublayers?.compactMap { $0 as? CATextLayer }.filter { !$0.isHidden }
            XCTAssertEqual(visibleLabels?.count, control.style == .pickerOnly ? 1 : 3)
        }
    }

    func testCompactCountExpandsOnlyWhenCloseClearanceFits() throws {
        let fixture = Fixture(count: 128)
        let layout = fixture.layout(size: CGSize(width: 90, height: 68))
        let control = try XCTUnwrap(layout.tabControls(for: layout.workspaceSections[0]).first)
        XCTAssertEqual(control.positionLabel, "128 ▾")
        XCTAssertGreaterThan(control.frame.width, 32)
        XCTAssertLessThanOrEqual(control.frame.maxX + 8, 100 + 90 - 26)
        let narrow = fixture.layout(size: CGSize(width: 74, height: 68))
        XCTAssertTrue(narrow.tabControls(for: narrow.workspaceSections[0]).isEmpty)
    }

    func testCompactPickerUsesMatchingMembersAndBoundedFullControls() throws {
        _ = NSApplication.shared
        let fixture = Fixture(count: 4)
        var layout = fixture.layout(size: CGSize(width: 74, height: 68), matchingIndices: [1, 3])
        let control = try XCTUnwrap(layout.tabControls(for: layout.workspaceSections[0]).first)
        XCTAssertEqual(control.positionLabel, "2 ▾")
        let point = CGPoint(x: control.frame.midX, y: control.frame.midY)
        XCTAssertNil(control.steppedHandle(at: point))
        XCTAssertEqual(control.frame(for: .picker), control.frame)
        var selected: [WindowHandle] = []
        let picker = OverviewTabPicker(handle: control.handle, members: layout.tabMembers(for: control.handle)) {
            selected.append($0)
        }
        XCTAssertEqual(picker.menu.items.map(\.title), ["Document 2", "Document 4"])
        XCTAssertEqual(picker.menu.items.map(\.state), [.on, .off])
        picker.menu.performActionForItem(at: 1)
        XCTAssertEqual(selected, [fixture.handles[3]])

        layout = fixture.layout(size: CGSize(width: 100, height: 92))
        layout.revealTab(fixture.handles[0])
        XCTAssertNil(layout.tabControls(for: layout.workspaceSections[0]).first?.previousHandle)
        layout.revealTab(fixture.handles[3])
        XCTAssertNil(layout.tabControls(for: layout.workspaceSections[0]).first?.nextHandle)
    }

    func testCompactHitsFollowRenderedControlDuringReflowAndFreeze() throws {
        let fixture = Fixture()
        var initial = fixture.layout(size: CGSize(width: 74, height: 68))
        initial.scrollOffset = 20
        let renderer = fixture.renderer(initial)
        let originalLayer = try XCTUnwrap(renderer.tabControlLayers[fixture.handles[1]])
        var destination = fixture.layout(size: CGSize(width: 90, height: 80), x: 300)
        destination.scrollOffset = 40
        renderer.updateLayout(destination, state: fixture.state, caretAnimated: false, update: .structural)
        XCTAssertTrue(renderer.tabControlLayers[fixture.handles[1]] === originalLayer)
        for _ in 0 ..< 2 {
            try assertPickerHits(renderer: renderer, layout: destination, handle: fixture.handles[1])
            destination = renderer.freezingReflow(in: destination)
            renderer.cancelAnimation()
            renderer.updatePresentation(destination, state: fixture.state)
        }
    }

    func testStyleChangesReplaceOnlyControlLayerAndKeepHitsAligned() throws {
        for compactDestination in [true, false] {
            let fixture = Fixture()
            let compact = CGSize(width: 74, height: 68)
            let full = CGSize(width: 140, height: 100)
            let initial = fixture.layout(size: compactDestination ? full : compact)
            let renderer = fixture.renderer(initial)
            let oldControl = try XCTUnwrap(renderer.tabControlLayers[fixture.handles[1]])
            let card = try XCTUnwrap(renderer.windowLayers[fixture.handles[1]])
            let destination = fixture.layout(size: compactDestination ? compact : full, x: 300)
            renderer.updateLayout(destination, state: fixture.state, caretAnimated: false, update: .structural)
            let control = try XCTUnwrap(renderer.tabControlLayers[fixture.handles[1]])
            XCTAssertFalse(control === oldControl)
            XCTAssertTrue(renderer.windowLayers[fixture.handles[1]] === card)
            XCTAssertNil(control.animation(forKey: "overview.bounds"))
            if compactDestination {
                try assertPickerHits(renderer: renderer, layout: destination, handle: fixture.handles[1])
            } else {
                let mask = try XCTUnwrap(control.mask)
                XCTAssertNotNil(mask.animation(forKey: "overview.bounds"))
                XCTAssertTrue(visibleFrame(control: control, card: card, renderer: renderer).isEmpty)
                renderer.cancelReflow()
                renderer.updatePresentation(destination, state: fixture.state)
                XCTAssertEqual(
                    visibleFrame(control: control, card: card, renderer: renderer),
                    displayedFrame(control: control, card: card, renderer: renderer)
                )
                for text in control.sublayers?.compactMap({ $0 as? CATextLayer }) ?? [] {
                    let frame = displayedFrame(control: control, card: card, renderer: renderer)
                    let point = CGPoint(x: frame.minX + text.frame.midX, y: frame.minY + text.frame.midY)
                    let hit = try XCTUnwrap(renderer.tabControl(at: point, layout: destination))
                    XCTAssertEqual(hit.style, .segmented)
                    if text.string as? String == "‹" {
                        XCTAssertEqual(hit.steppedHandle(at: point), fixture.handles[0])
                    } else if text.string as? String == "›" {
                        XCTAssertEqual(hit.steppedHandle(at: point), fixture.handles[2])
                    } else {
                        XCTAssertTrue(hit.frame(for: .picker).contains(point))
                    }
                }
            }
        }
    }

    func testGroupMembershipChangeInvalidatesChromeWithoutCardChanges() {
        let fixture = Fixture()
        let initial = fixture.layout(size: CGSize(width: 100, height: 92))
        let renderer = fixture.renderer(initial)
        XCTAssertFalse(renderer.workspaceChromeNeedsUpdate(initial))
        var reordered = initial
        reordered.dwindleGroupsByWorkspace[fixture.workspaceId] = [OverviewDwindleGroup(
            id: fixture.groupId, windowHandles: Array(fixture.handles.reversed()), activeHandle: fixture.handles[1]
        )]
        XCTAssertTrue(renderer.workspaceChromeNeedsUpdate(reordered))
    }

    func testResizingGroupControlDoesNotCoverDisplayedCloseButton() throws {
        for compactDestination in [true, false] {
            let fixture = Fixture()
            let compact = CGSize(width: 74, height: 68)
            let full = CGSize(width: 140, height: 100)
            let initial = fixture.layout(size: compactDestination ? full : compact)
            let renderer = fixture.renderer(initial)
            let destination = fixture.layout(size: compactDestination ? compact : full, x: 300)
            renderer.updateLayout(destination, state: fixture.state, caretAnimated: false, update: .structural)
            let card = try XCTUnwrap(renderer.windowLayers[fixture.handles[1]])
            let close = try XCTUnwrap(card.root.sublayers?.first { $0.sublayers?.first is CAShapeLayer })
            let closeFrame = displayedFrame(control: close, card: card, renderer: renderer)
            if let control = renderer.tabControlLayers[fixture.handles[1]] {
                XCTAssertFalse(visibleFrame(control: control, card: card, renderer: renderer).intersects(closeFrame))
            }
            let point = CGPoint(x: closeFrame.midX, y: closeFrame.midY)
            XCTAssertTrue(try XCTUnwrap(renderer.windowHit(at: point, layout: destination)).isCloseButton)
            XCTAssertNil(renderer.tabControl(at: point, layout: destination))
        }
    }

    private func assertPickerHits(
        renderer: OverviewLayerRenderer,
        layout: OverviewLayout,
        handle: WindowHandle
    ) throws {
        let control = try XCTUnwrap(renderer.tabControlLayers[handle])
        let card = try XCTUnwrap(renderer.windowLayers[handle])
        let frame = displayedFrame(control: control, card: card, renderer: renderer)
        for fraction: CGFloat in [0.1, 0.5, 0.9] {
            let point = CGPoint(x: frame.minX + frame.width * fraction, y: frame.midY)
            let hit = try XCTUnwrap(renderer.tabControl(at: point, layout: layout))
            XCTAssertEqual(hit.style, .pickerOnly)
            XCTAssertEqual(hit.frame(for: .picker), frame)
            XCTAssertTrue(hit.frame(for: .picker).contains(point))
            XCTAssertNil(hit.steppedHandle(at: point))
        }
    }

    private func displayedFrame(
        control: CALayer,
        card: OverviewWindowLayer,
        renderer: OverviewLayerRenderer
    ) -> CGRect {
        let content = OverviewLayerMotion.displayedFrame(of: renderer.content)
        return OverviewLayerMotion.displayedFrame(of: control).offsetBy(
            dx: card.displayedFrame.minX + content.minX,
            dy: card.displayedFrame.minY + content.minY
        )
    }

    private func visibleFrame(
        control: CALayer,
        card: OverviewWindowLayer,
        renderer: OverviewLayerRenderer
    ) -> CGRect {
        let frame = displayedFrame(control: control, card: card, renderer: renderer)
        guard let mask = control.mask else { return frame }
        return frame.intersection(OverviewLayerMotion.displayedFrame(of: mask).offsetBy(
            dx: frame.minX,
            dy: frame.minY
        ))
    }

    @MainActor
    private struct Fixture {
        let workspaceId = UUID()
        let groupId = UUID()
        let handles: [WindowHandle]
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)

        init(count: Int = 3) {
            handles = (0 ..< count).map { WindowHandle(id: WindowToken(pid: 1, windowId: $0 + 1)) }
        }

        var state: OverviewRenderState {
            OverviewRenderState(
                searchQuery: "", selectedWindowHandle: handles[1], hoveredWindowHandle: handles[1],
                closeButtonHovered: false, progress: 1, bounds: screen, palette: .default
            )
        }

        func layout(
            size: CGSize,
            x: CGFloat = 100,
            niri: Bool = false,
            matchingIndices: Set<Int>? = nil
        ) -> OverviewLayout {
            let frame = CGRect(x: x, y: 100, width: size.width, height: size.height)
            let windows = handles.enumerated().map { index, handle in
                var item = OverviewWindowItem(
                    handle: handle, windowId: handle.id.windowId, workspaceId: workspaceId,
                    title: "Document \(index + 1)", appName: "Editor", appIcon: nil,
                    originalFrame: frame, overviewFrame: frame,
                    matchesSearch: matchingIndices?.contains(index) ?? true
                )
                item.isDisplayed = index == 1
                item.isTiled = niri
                return item
            }
            var layout = OverviewLayout()
            layout.viewportFrame = screen
            layout.searchBarFrame = CGRect(x: 200, y: 540, width: 400, height: 44)
            layout.replaceWorkspaceSections([OverviewWorkspaceSection(
                workspaceId: workspaceId, name: "Workspace", windows: windows,
                sectionFrame: screen, labelFrame: .zero, gridFrame: screen, isActive: true,
                viewportFrame: screen, visibleFrame: screen, ribbonFrame: screen
            )])
            if niri {
                layout.niriColumnsByWorkspace[workspaceId] = [OverviewNiriColumn(
                    workspaceId: workspaceId, columnIndex: 0, frame: frame,
                    windowHandles: handles, isTabbed: true
                )]
            } else {
                layout.dwindleGroupsByWorkspace[workspaceId] = [OverviewDwindleGroup(
                    id: groupId, windowHandles: handles, activeHandle: handles[1]
                )]
            }
            return layout
        }

        func renderer(_ layout: OverviewLayout) -> OverviewLayerRenderer {
            let renderer = OverviewLayerRenderer()
            renderer.updateLayout(layout, state: state, caretAnimated: false)
            renderer.updatePresentation(layout, state: state)
            return renderer
        }
    }
}
