// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension IPCAutomationManifest {
    static let keyboardModeCommandDescriptors: [IPCCommandDescriptor] = [
        .init(
            name: .keyboardMode(.togglePause),
            summary: "Pause or resume OmniWM shortcuts so their keys reach the focused app."
        ),
        .init(
            name: .keyboardMode(.beginPrefix),
            summary: "Arm the prefix: the next mode key runs its OmniWM command."
        ),
        .init(
            name: .keyboardMode(.toggleWindowMode),
            summary: "Enter or leave Window mode, where mode keys run OmniWM commands until Escape."
        ),
        .init(
            name: .keyboardMode(.exit),
            summary: "Leave Pause, Prefix, or Window mode."
        )
    ]
}
