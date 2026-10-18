// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

enum DwindleGroupDrag: String, CaseIterable, Codable, Identifiable, Sendable {
    case group
    case window

    var id: String {
        rawValue
    }
}
