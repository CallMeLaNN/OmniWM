// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import QuartzCore
import XCTest

@MainActor
final class OverviewCaptionTests: XCTestCase {
    func testCaptionUsesGradientAndRevealsAppNameOnlyOnEmphasis() throws {
        let item = makeItem()
        let layers = OverviewWindowLayer()
        layers.updateContent(item, contentsScale: 2)
        layers.updateGeometry(item, frame: item.overviewFrame, state: state())
        let scrim = try XCTUnwrap(layers.root.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        let title = try textLayer("Document", in: scrim)
        let app = try textLayer("Editor", in: scrim)
        let colors = try XCTUnwrap(scrim.colors as? [CGColor])
        XCTAssertEqual(colors.last?.alpha, 0)
        XCTAssertLessThan(try XCTUnwrap(colors.first?.alpha), 0.9)
        XCTAssertFalse(title.isHidden)
        XCTAssertEqual(title.truncationMode, .end)
        XCTAssertTrue(app.isHidden)
        XCTAssertTrue(scrim.bounds.contains(title.frame))

        layers.updateEmphasis(item, state: state(hovered: item.handle))
        XCTAssertFalse(app.isHidden)
        XCTAssertTrue(scrim.bounds.contains(title.frame))
        layers.updateEmphasis(item, state: state(selected: item.handle))
        XCTAssertFalse(app.isHidden)
        layers.updateEmphasis(item, state: state())
        XCTAssertTrue(app.isHidden)
    }

    func testCaptionSizesStayReadableAcrossSmallAndLargeCards() throws {
        let layers = OverviewWindowLayer()
        for height: CGFloat in [64, 100, 500] {
            let item = makeItem(height: height)
            layers.updateContent(item, contentsScale: 2)
            layers.updateGeometry(item, frame: item.overviewFrame, state: state())
            let scrim = try XCTUnwrap(layers.root.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
            let title = try textLayer("Document", in: scrim)
            let icon = try XCTUnwrap(scrim.sublayers?.first { !($0 is CATextLayer) })
            XCTAssertGreaterThanOrEqual(title.fontSize, 10)
            XCTAssertLessThanOrEqual(title.fontSize, 13)
            XCTAssertGreaterThanOrEqual(icon.bounds.width, 14)
            XCTAssertLessThanOrEqual(icon.bounds.width, 24)
            XCTAssertTrue(scrim.bounds.contains(icon.frame))
            XCTAssertTrue(scrim.bounds.contains(title.frame))
        }
    }

    func testFullscreenStatusRemainsVisibleWithoutHover() throws {
        var item = makeItem()
        item.isNativeFullscreen = true
        let layers = OverviewWindowLayer()
        layers.updateContent(item, contentsScale: 2)
        layers.updateGeometry(item, frame: item.overviewFrame, state: state())
        let scrim = try XCTUnwrap(layers.root.sublayers?.compactMap { $0 as? CAGradientLayer }.first)
        let status = try textLayer("Full Screen", in: scrim)
        XCTAssertFalse(status.isHidden)
        layers.updateEmphasis(item, state: state(hovered: item.handle))
        XCTAssertEqual(status.string as? String, "Editor · Full Screen")
        layers.updateEmphasis(item, state: state())
        XCTAssertEqual(status.string as? String, "Full Screen")
        XCTAssertFalse(status.isHidden)
    }

    private func textLayer(_ text: String, in layer: CALayer) throws -> CATextLayer {
        try XCTUnwrap(layer.sublayers?.compactMap { $0 as? CATextLayer }.first { $0.string as? String == text })
    }

    private func makeItem(height: CGFloat = 100) -> OverviewWindowItem {
        OverviewWindowItem(
            handle: WindowHandle(id: WindowToken(pid: 1, windowId: 1)),
            windowId: 1,
            workspaceId: UUID(),
            title: "Document",
            appName: "Editor",
            appIcon: nil,
            originalFrame: CGRect(x: 0, y: 0, width: 400, height: height * 2),
            overviewFrame: CGRect(x: 20, y: 30, width: 200, height: height),
            matchesSearch: true
        )
    }

    private func state(selected: WindowHandle? = nil, hovered: WindowHandle? = nil) -> OverviewRenderState {
        OverviewRenderState(
            searchQuery: "",
            selectedWindowHandle: selected,
            hoveredWindowHandle: hovered,
            closeButtonHovered: false,
            progress: 1,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            palette: .default
        )
    }
}
