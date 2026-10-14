// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, styles, bar, island, widgets, menuBar
    case workspaces, layouts, monitors, appRules, overview
    case hotkeys, mouseTrackpad, quakeTerminal, diagnostics, reportIssue, advanced

    var id: String {
        rawValue
    }

    var displayName: String {
        presentation.title
    }

    var icon: String {
        presentation.icon
    }

    var subtitle: String {
        presentation.subtitle
    }

    private var presentation: (title: String, icon: String, subtitle: String) {
        switch self {
        case .general:
            (String(localized: "General"), "gearshape", String(localized: "Language, startup, and updates."))
        case .appearance:
            (String(localized: "Appearance"), "paintpalette", String(localized: "Choose how OmniWM looks and moves."))
        case .styles:
            (
                String(localized: "Styles"),
                "square.grid.2x2",
                String(localized: "Preview a desktop style and choose its color palette.")
            )
        case .bar:
            (
                String(localized: "Workspace Bar"),
                "menubar.rectangle",
                String(localized: "Arrange widgets and customize the bar on your displays.")
            )
        case .island:
            (
                String(localized: "Dynamic Island"),
                "capsule",
                String(localized: "Customize your island, with or without a workspace bar.")
            )
        case .widgets:
            (
                String(localized: "Widgets"),
                "puzzlepiece.extension",
                String(localized: "Discover widgets, choose where they appear, and edit their options.")
            )
        case .menuBar:
            (
                String(localized: "Menu Bar"),
                "menubar.arrow.up.rectangle",
                String(localized: "Manage OmniWM’s status item and hidden menu-bar apps.")
            )
        case .workspaces:
            (
                String(localized: "Workspaces"),
                "rectangle.3.group",
                String(localized: "Organize workspaces and choose their layouts and home displays.")
            )
        case .layouts:
            (
                String(localized: "Layouts"),
                "rectangle.split.3x1",
                String(localized: "Tune window spacing, scrolling columns, and split layouts.")
            )
        case .monitors:
            (
                String(localized: "Displays"),
                "display.2",
                String(localized: "Set display arrangement, routing, and cross-display behavior.")
            )
        case .appRules:
            (
                String(localized: "App Rules"),
                "app.badge.checkmark",
                String(localized: "Choose how particular apps and windows are managed.")
            )
        case .overview:
            (
                String(localized: "Overview"),
                "rectangle.grid.2x2",
                String(localized: "Customize the workspace overview and its controls.")
            )
        case .hotkeys:
            (
                String(localized: "Keyboard Shortcuts"),
                "keyboard",
                String(localized: "Find commands and assign keyboard or mouse shortcuts.")
            )
        case .mouseTrackpad:
            (
                String(localized: "Mouse & Trackpad"),
                "computermouse",
                String(localized: "Configure gestures, window manipulation, and pointer focus.")
            )
        case .quakeTerminal:
            (
                String(localized: "Quake Terminal"),
                "terminal",
                String(localized: "Configure your drop-down terminal’s placement and appearance.")
            )
        case .diagnostics:
            (
                String(localized: "Troubleshooting"),
                "stethoscope",
                String(localized: "Check app health and record a problem or performance capture.")
            )
        case .reportIssue:
            (
                String(localized: "Report an Issue"),
                "ladybug",
                String(localized: "Prepare a report and choose the evidence you want to share.")
            )
        case .advanced:
            (
                String(localized: "Advanced"),
                "slider.horizontal.3",
                String(localized: "Configuration files, scripting, and command-line tools.")
            )
        }
    }
}

enum SettingsSectionGroup: String, CaseIterable, Identifiable {
    case app, desktop, windows, input, tools, support
    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .app: String(localized: "App")
        case .desktop: String(localized: "Desktop")
        case .windows: String(localized: "Windows")
        case .input: String(localized: "Input")
        case .tools: String(localized: "Tools")
        case .support: String(localized: "Support")
        }
    }

    var sections: [SettingsSection] {
        switch self {
        case .app: [.general, .appearance]
        case .desktop: [.styles, .bar, .island, .widgets, .menuBar]
        case .windows: [.workspaces, .layouts, .monitors, .appRules, .overview]
        case .input: [.hotkeys, .mouseTrackpad]
        case .tools: [.quakeTerminal]
        case .support: [.diagnostics, .reportIssue, .advanced]
        }
    }
}
