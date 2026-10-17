// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Observation

@MainActor @Observable
final class OverviewSettings {
    private nonisolated static let defaults = SettingsExport.Overview.defaults()
    @ObservationIgnored var onChange: (() -> Void)?

    var enabled = OverviewSettings.defaults.enabled ?? true {
        didSet { onChange?() }
    }

    var zoom = OverviewSettings.defaults.zoom {
        didSet { onChange?() }
    }

    var invertScrollDirection = false {
        didSet { onChange?() }
    }

    var mouseScrollSpeed = 1.0 {
        didSet { onChange?() }
    }

    var mouseButton: Int64? {
        didSet { onChange?() }
    }

    var backdropColor = OverviewSettings.defaults.backdrop {
        didSet { onChange?() }
    }

    var normalBorderColor = OverviewSettings.defaults.windowBorders.normal {
        didSet { onChange?() }
    }

    var hoveredBorderColor = OverviewSettings.defaults.windowBorders.hovered {
        didSet { onChange?() }
    }

    var selectedBorderColor = OverviewSettings.defaults.windowBorders.selected {
        didSet { onChange?() }
    }

    var matchFocusBorder = OverviewSettings.defaults.matchFocusBorder ?? true {
        didSet { onChange?() }
    }

    func export() -> SettingsExport.Overview {
        SettingsExport.Overview(
            enabled: enabled,
            zoom: zoom,
            backdrop: backdropColor,
            windowBorders: SettingsExport.OverviewWindowBorders(
                normal: normalBorderColor,
                hovered: hoveredBorderColor,
                selected: selectedBorderColor
            ),
            matchFocusBorder: matchFocusBorder,
            invertScrollDirection: invertScrollDirection,
            mouseScrollSpeed: mouseScrollSpeed,
            mouseButton: mouseButton
        )
    }

    func apply(_ values: SettingsExport.Overview, baseline: SettingsExport.Overview) {
        enabled = values.enabled ?? baseline.enabled ?? true
        zoom = Self.validatedZoom(values.zoom)
        invertScrollDirection = values.invertScrollDirection ?? false
        mouseScrollSpeed = Self.validatedMouseScrollSpeed(values.mouseScrollSpeed ?? 1)
        mouseButton = values.mouseButton
        backdropColor = Self.validatedColor(values.backdrop, default: baseline.backdrop)
        normalBorderColor = Self.validatedColor(
            values.windowBorders.normal,
            default: baseline.windowBorders.normal
        )
        hoveredBorderColor = Self.validatedColor(
            values.windowBorders.hovered,
            default: baseline.windowBorders.hovered
        )
        selectedBorderColor = Self.validatedColor(
            values.windowBorders.selected,
            default: baseline.windowBorders.selected
        )
        matchFocusBorder = values.matchFocusBorder ?? baseline.matchFocusBorder ?? true
    }

    private static func validatedZoom(_ value: Double) -> Double {
        guard value.isFinite else { return defaults.zoom }
        return min(1.5, max(0.5, value))
    }

    nonisolated static func validatedMouseScrollSpeed(_ value: Double) -> Double {
        value.isFinite ? min(2, max(0.05, value)) : 1
    }

    private static func validatedColor(_ color: SettingsColor, default defaultColor: SettingsColor) -> SettingsColor {
        SettingsColor(
            red: validatedColorComponent(color.red, default: defaultColor.red),
            green: validatedColorComponent(color.green, default: defaultColor.green),
            blue: validatedColorComponent(color.blue, default: defaultColor.blue),
            alpha: validatedColorComponent(color.alpha, default: defaultColor.alpha)
        )
    }

    private static func validatedColorComponent(_ value: Double, default defaultValue: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(1.0, max(0.0, value))
    }
}
