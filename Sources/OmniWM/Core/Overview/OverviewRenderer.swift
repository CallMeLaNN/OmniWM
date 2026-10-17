// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import CoreGraphics
import QuartzCore

struct OverviewRenderState {
    let searchQuery: String
    let selection: OverviewSelection?
    var selectedWindowHandle: WindowHandle? {
        selection?.windowHandle
    }

    let hoveredWindowHandle: WindowHandle?
    let closeButtonHovered: Bool
    let progress: Double
    let bounds: CGRect
    let palette: OverviewRenderPalette

    init(
        searchQuery: String,
        selectedWindowHandle: WindowHandle?,
        hoveredWindowHandle: WindowHandle?,
        closeButtonHovered: Bool,
        progress: Double,
        bounds: CGRect,
        palette: OverviewRenderPalette,
        selection: OverviewSelection? = nil
    ) {
        self.searchQuery = searchQuery
        self.selection = selection ?? selectedWindowHandle.map(OverviewSelection.window)
        self.hoveredWindowHandle = hoveredWindowHandle
        self.closeButtonHovered = closeButtonHovered
        self.progress = progress
        self.bounds = bounds
        self.palette = palette
    }
}

enum OverviewRenderer {
    static func borderColor(
        isSelected: Bool,
        isHovered: Bool,
        palette: OverviewRenderPalette
    ) -> CGColor {
        if isSelected { return palette.selectedBorder }
        if isHovered { return palette.hoveredBorder }
        return palette.normalBorder
    }

    @MainActor
    static func textLayer(size: CGFloat, color: CGColor, alignment: CATextLayerAlignmentMode = .left) -> CATextLayer {
        let layer = CATextLayer()
        layer.font = NSFont.systemFont(ofSize: size)
        layer.fontSize = size
        layer.foregroundColor = color
        layer.alignmentMode = alignment
        layer.truncationMode = .end
        return layer
    }

    @MainActor
    static func withoutAnimation(_ update: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        update()
        CATransaction.commit()
    }
}
