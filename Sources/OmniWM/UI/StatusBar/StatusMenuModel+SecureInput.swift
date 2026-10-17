// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

extension StatusMenuModel {
    var isSecureInputIndicated: Bool {
        controller?.isSecureInputIndicated ?? false
    }

    func showSecureInputExplanation() {
        controller?.showSecureInputExplanation()
    }
}
