// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import CoreGraphics

enum OverviewScrollInput {
    static let axisEpsilon: CGFloat = 0.0001

    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    struct Event {
        let deltaX: CGFloat
        let deltaY: CGFloat
        let modifiers: NSEvent.ModifierFlags
        let isPrecise: Bool
        let location: CGPoint
        var phase: NSEvent.Phase = []
        var momentumPhase: NSEvent.Phase = []

        var dominantAxis: Axis {
            abs(deltaY) >= abs(deltaX) ? .vertical : .horizontal
        }

        var dominantDelta: CGFloat {
            OverviewScrollInput.dominantDelta(deltaX: deltaX, deltaY: deltaY)
        }
    }

    struct GestureScrollGate {
        var awaitingNewGesture = false

        mutating func consumes(_ event: Event, state: OverviewState) -> Bool {
            guard event.isPrecise, awaitingNewGesture else { return false }
            if state.isAnimating { return true }
            if event.phase.contains(.began), event.momentumPhase.isEmpty {
                awaitingNewGesture = false
            }
            return awaitingNewGesture
        }
    }

    static func dominantDelta(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat {
        let dominant = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
        return abs(dominant) <= axisEpsilon ? 0 : dominant
    }
}
