// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics

enum WindowMoveGeometry {
    static func insertionDirection(at point: CGPoint, in frame: CGRect) -> Direction? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let horizontal = (point.x - frame.midX) / frame.width
        let vertical = (point.y - frame.midY) / frame.height
        guard max(abs(horizontal), abs(vertical)) > 0.2 else { return nil }
        return abs(horizontal) > abs(vertical)
            ? (horizontal < 0 ? .left : .right)
            : (vertical < 0 ? .down : .up)
    }

    static func targetFrame(in frame: CGRect, direction: Direction?) -> CGRect {
        switch direction {
        case .left:
            frame.divided(atDistance: frame.width / 2, from: .minXEdge).slice
        case .right:
            frame.divided(atDistance: frame.width / 2, from: .maxXEdge).slice
        case .up:
            frame.divided(atDistance: frame.height / 2, from: .maxYEdge).slice
        case .down:
            frame.divided(atDistance: frame.height / 2, from: .minYEdge).slice
        case nil:
            frame
        }
    }
}
