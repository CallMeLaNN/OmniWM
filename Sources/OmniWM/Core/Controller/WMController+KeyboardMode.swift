// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import OmniWMIPC

extension WMController {
    func performKeyboardModeCommand(_ command: IPCKeyboardModeCommand) -> ExternalCommandResult {
        hotkeys.performKeyboardModeCommand(command) ? .executed : .noChange
    }

    func updateKeyboardModeSettings() {
        hotkeys.configureKeyboardModes(settings.keyboardModes.export())
    }

    func keyboardModeDidChange(_ kind: KeyboardModeKind) {
        keyboardModeKind = kind
        surfaceReconciler.noteBorderChanged()
        refreshStatusBar()
    }
}
