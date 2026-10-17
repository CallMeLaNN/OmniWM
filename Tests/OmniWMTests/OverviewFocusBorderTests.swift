// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
@testable import OmniWM
import QuartzCore
import XCTest

@MainActor
final class OverviewFocusBorderTests: XCTestCase {
    func testSelectedFocusBorderUsesScaledExternalWidthAndHonorsDisabledState() throws {
        let item = makeItem()
        let layers = OverviewWindowLayer()
        layers.updateContent(item, contentsScale: 2)
        var config = BorderConfig(enabled: true, width: 8)
        layers.updateGeometry(item, frame: item.overviewFrame, state: state(item, config: config))
        XCTAssertEqual(layers.border.borderWidth, 4)
        XCTAssertEqual(layers.border.frame, CGRect(x: -4, y: -4, width: 208, height: 108))
        XCTAssertEqual(layers.border.cornerRadius, 12)

        config.enabled = false
        layers.updateGeometry(item, frame: item.overviewFrame, state: state(item, config: config))
        XCTAssertEqual(layers.border.borderWidth, 0)
        XCTAssertEqual(layers.border.frame, layers.root.bounds)

        layers.updateGeometry(item, frame: item.overviewFrame, state: state(item, config: nil))
        XCTAssertEqual(layers.border.borderWidth, OverviewRenderStyle.Metrics.selectedBorderWidth)
        XCTAssertEqual(layers.border.frame, layers.root.bounds)
    }

    func testGradientGlowInheritsStopsAndRemainsVisibleWithoutSolidBorder() throws {
        let item = makeItem()
        let layers = OverviewWindowLayer()
        layers.updateContent(item, contentsScale: 2)
        let gradient = BorderGradient(
            enabled: true,
            start: SettingsColor(red: 1, green: 0, blue: 0, alpha: 1),
            end: SettingsColor(red: 0, green: 0, blue: 1, alpha: 1),
            direction: .topRightToBottomLeft,
            dark: nil
        )
        var config = BorderConfig(
            enabled: true,
            width: 8,
            gradient: gradient,
            glow: BorderGlow(enabled: true, radius: 12, opacity: 0.5)
        )
        layers.updateGeometry(item, frame: item.overviewFrame, state: state(item, config: config))
        let effects = try XCTUnwrap(layers.root.sublayers?.first {
            $0.sublayers?.contains { $0 is CAGradientLayer } == true
        })
        let colors = try XCTUnwrap(effects.sublayers?.compactMap { $0 as? CAGradientLayer })
        XCTAssertEqual(colors.count, 2)
        let glow = colors[0]
        let stroke = colors[1]
        XCTAssertFalse(effects.isHidden)
        XCTAssertFalse(glow.isHidden)
        XCTAssertFalse(stroke.isHidden)
        XCTAssertEqual(glow.colors as? [CGColor], stroke.colors as? [CGColor])
        XCTAssertEqual(glow.startPoint, CGPoint(x: 1, y: 1))
        XCTAssertEqual(glow.endPoint, CGPoint(x: 0, y: 0))
        XCTAssertEqual(layers.border.borderColor?.alpha, 0)
        XCTAssertEqual(effects.frame, CGRect(x: -13, y: -13, width: 226, height: 126))
        let bands = try XCTUnwrap(glow.mask?.sublayers?.compactMap { $0 as? CAShapeLayer })
        XCTAssertEqual(bands.count, 18)
        XCTAssertTrue(bands.contains { !$0.isHidden && ($0.strokeColor?.alpha ?? 0) > 0 })

        let explicit = SettingsColor(red: 0, green: 1, blue: 0, alpha: 1)
        config.glow?.color = explicit
        config.gradient = nil
        layers.updateGeometry(item, frame: item.overviewFrame, state: state(item, config: config))
        XCTAssertTrue(stroke.isHidden)
        XCTAssertEqual(
            glow.colors as? [CGColor],
            [BorderLayerPanel.cgColor(explicit), BorderLayerPanel.cgColor(explicit)]
        )
        XCTAssertEqual(layers.border.borderColor?.alpha, 1)

        config.enabled = false
        layers.updateGeometry(item, frame: item.overviewFrame, state: state(item, config: config))
        XCTAssertTrue(effects.isHidden)
        XCTAssertEqual(layers.border.borderWidth, 0)
    }

    private func makeItem() -> OverviewWindowItem {
        var item = OverviewWindowItem(
            handle: WindowHandle(id: WindowToken(pid: 1, windowId: 1)),
            windowId: 1,
            workspaceId: UUID(),
            title: "Window",
            appName: "App",
            appIcon: nil,
            originalFrame: CGRect(x: 0, y: 0, width: 400, height: 200),
            overviewFrame: CGRect(x: 20, y: 30, width: 200, height: 100),
            matchesSearch: true
        )
        item.contentScale = 0.5
        return item
    }

    private func state(_ item: OverviewWindowItem, config: BorderConfig?) -> OverviewRenderState {
        let color = config?.color ?? SettingsColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1)
        return OverviewRenderState(
            searchQuery: "",
            selectedWindowHandle: item.handle,
            hoveredWindowHandle: nil,
            closeButtonHovered: false,
            progress: 1,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            palette: OverviewRenderPalette(
                backdropColor: color,
                normalBorderColor: color,
                hoveredBorderColor: color,
                selectedBorderColor: color,
                focusBorder: config
            )
        )
    }
}
