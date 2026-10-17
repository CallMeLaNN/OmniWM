// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import QuartzCore

extension OverviewLayerRenderer {
    func addColumnChrome(
        _ section: OverviewWorkspaceSection,
        layout: OverviewLayout,
        to sectionLayer: CALayer
    ) {
        let clip = CALayer()
        clip.frame = section.ribbonFrame
        clip.masksToBounds = true
        sectionLayer.addSublayer(clip)
        var retained: [Int: CALayer] = [:]
        for column in layout.niriColumnsByWorkspace[section.workspaceId] ?? [] {
            let layer = columnLayers[section.workspaceId]?[column.columnIndex] ?? CALayer()
            layer.frame = column.frame.offsetBy(dx: -clip.frame.minX, dy: -clip.frame.minY)
            layer.backgroundColor = Colors.columnBackground
            layer.borderColor = Colors.columnBorder
            layer.borderWidth = 1
            layer.cornerRadius = Metrics.columnCornerRadius
            clip.addSublayer(layer)
            retained[column.columnIndex] = layer
            updateColumnDividers(layer, column: column, section: section, layout: layout)
        }
        columnLayers[section.workspaceId] = retained
    }

    private func updateColumnDividers(
        _ layer: CALayer,
        column: OverviewNiriColumn,
        section: OverviewWorkspaceSection,
        layout: OverviewLayout
    ) {
        let horizontal = section.orientation == .horizontal
        let frames = column.windowHandles.compactMap { layout.window(for: $0) }
            .filter(\.isDisplayed).map(\.overviewFrame)
            .sorted { horizontal ? $0.maxY > $1.maxY : $0.maxX > $1.maxX }
        let previous = layer.sublayers ?? []
        var dividers: [CALayer] = []
        for (index, pair) in zip(frames, frames.dropFirst()).enumerated() {
            let (first, second) = pair
            let divider = index < previous.count ? previous[index] : CALayer()
            divider.backgroundColor = Colors.columnDivider
            divider.frame = horizontal
                ? CGRect(
                    x: 8,
                    y: (first.minY + second.maxY - Metrics.dividerHeight) / 2 - column.frame.minY,
                    width: max(0, column.frame.width - 16),
                    height: Metrics.dividerHeight
                )
                : CGRect(
                    x: (first.minX + second.maxX - Metrics.dividerHeight) / 2 - column.frame.minX,
                    y: 8,
                    width: Metrics.dividerHeight,
                    height: max(0, column.frame.height - 16)
                )
            dividers.append(divider)
        }
        layer.sublayers = dividers
    }
}
