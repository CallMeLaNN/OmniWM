// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct CommandPaletteMarkActionsView: View {
    let controller: CommandPaletteController

    var body: some View {
        let setMarkShortcut = controller.markShortcut(for: .set)
        let removeMarkShortcut = controller.markShortcut(for: .remove)
        HStack(spacing: 10) {
            Button(action: { controller.setMarkOnSelectedWindow() }, label: {
                HStack(spacing: 6) {
                    Label("Mark selected window…", systemImage: "tag")
                    if let setMarkShortcut {
                        CommandPaletteShortcutBadge(text: setMarkShortcut)
                    }
                }
            })
            .accessibilityHint(
                setMarkShortcut == nil
                    ? String(localized: "Marks the selected window row.")
                    : String(localized: "Marks the selected window row. Shortcut Control-Option-Shift-M.")
            )
            .help(
                setMarkShortcut == nil
                    ? String(localized: "Mark the selected window")
                    : String(localized: "Mark the selected window (Control-Option-Shift-M)")
            )

            Button(action: { controller.removeMarkFromSelectedWindow() }, label: {
                HStack(spacing: 6) {
                    Label("Remove mark…", systemImage: "tag.slash")
                    if let removeMarkShortcut {
                        CommandPaletteShortcutBadge(text: removeMarkShortcut)
                    }
                }
            })
            .accessibilityHint(
                removeMarkShortcut == nil
                    ? String(localized: "Choose a mark to remove from the selected window.")
                    :
                    String(
                        localized: "Choose a mark to remove from the selected window. Shortcut Control-Option-Shift-R."
                    )
            )
            .help(
                removeMarkShortcut == nil
                    ? String(localized: "Choose a mark to remove from the selected window")
                    : String(localized: "Choose a mark to remove from the selected window (Control-Option-Shift-R)")
            )
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
