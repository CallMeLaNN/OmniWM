// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

enum ResizePreviewStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case live
    case glass
    case snapshot

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .live: "Live Window Resizing"
        case .glass: "Liquid Glass Placeholder"
        case .snapshot: "Live Snapshot Overlay"
        }
    }
}
