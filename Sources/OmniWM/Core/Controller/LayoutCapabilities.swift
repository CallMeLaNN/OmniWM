// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@MainActor protocol LayoutSizable: AnyObject {
    func cycleSize(forward: Bool)
    func balanceSizes()
}
