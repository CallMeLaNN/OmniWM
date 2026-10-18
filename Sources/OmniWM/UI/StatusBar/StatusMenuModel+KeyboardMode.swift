// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import OmniWMIPC

extension StatusMenuModel {
    var keyboardModeKind: KeyboardModeKind {
        controller?.keyboardModeKind ?? .normal
    }

    var leaveKeyboardModeTitle: String? {
        switch keyboardModeKind {
        case .normal: nil
        case .paused: String(localized: "Resume Shortcuts")
        case .prefix: String(localized: "Cancel Prefix")
        case .window: String(localized: "Leave Window Mode")
        }
    }

    func leaveKeyboardMode() {
        _ = controller?.performKeyboardModeCommand(.exit)
    }
}
