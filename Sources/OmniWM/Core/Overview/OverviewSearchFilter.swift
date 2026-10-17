// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct OverviewSearchFilter {
    static func firstMatchingWindow(in layout: OverviewLayout) -> OverviewWindowItem? {
        for section in layout.workspaceSections {
            for window in section.windows where window.matchesSearch && window.isDisplayed {
                return window
            }
        }
        return nil
    }
}
