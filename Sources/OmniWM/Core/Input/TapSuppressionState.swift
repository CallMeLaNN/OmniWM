// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
import os

final class TapSuppressionState: @unchecked Sendable {
    struct Snapshot: Sendable {
        var capturedInteractionButton: MouseEventHandler.MouseButton?
        var capturedOtherMouseButton: Int64?
        var claimedOtherMouseButtons: Set<Int64> = []
        var mouseResizeModifierFlags: CGEventFlags = []
        var scrollModifierFlags: CGEventFlags = []
        var isTrackpadSwipeActive: Bool = false
        var isTrackpadLatched: Bool = false
        var isInputSuppressed: Bool = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: Snapshot())

    var snapshot: Snapshot {
        lock.withLock { $0 }
    }

    func update(_ mutate: @Sendable (inout Snapshot) -> Void) {
        lock.withLock(mutate)
    }

    nonisolated func evaluateTapThreadSuppression(type: CGEventType, event: CGEvent) -> Bool {
        let snap = snapshot
        if snap.isInputSuppressed {
            return false
        }

        let location = event.location
        let screenLocation = ScreenCoordinateSpace.toAppKit(point: location)
        let modifiers = event.flags

        switch type {
        case .leftMouseDown:
            return evaluateLeftMouseDown(at: screenLocation, modifiers: modifiers)
        case .leftMouseDragged:
            return evaluateLeftMouseDragged(at: screenLocation, snap: snap)
        case .leftMouseUp:
            return evaluateLeftMouseUp(at: screenLocation, snap: snap)
        case .rightMouseDown:
            return evaluateRightMouseDown(at: screenLocation, modifiers: modifiers, snap: snap)
        case .rightMouseDragged:
            return evaluateRightMouseDragged(at: screenLocation, snap: snap)
        case .rightMouseUp:
            return evaluateRightMouseUp(at: screenLocation, snap: snap)
        case .otherMouseDown:
            return evaluateOtherMouseDown(event: event, modifiers: modifiers, snap: snap)
        case .otherMouseDragged:
            return evaluateOtherMouseDragged(event: event, snap: snap)
        case .otherMouseUp:
            return evaluateOtherMouseUp(event: event, modifiers: modifiers, snap: snap)
        case .scrollWheel:
            return evaluateScrollWheel(event: event, at: screenLocation, modifiers: modifiers, snap: snap)
        default:
            return false
        }
    }

    private nonisolated func evaluateLeftMouseDown(at location: CGPoint, modifiers: CGEventFlags) -> Bool {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = MouseEventHandler._instance?.receiveTapMouseDown(at: location, modifiers: modifiers)
            }
        }
        return false
    }

    private nonisolated func evaluateLeftMouseDragged(at location: CGPoint, snap: Snapshot) -> Bool {
        guard snap.capturedInteractionButton == .left else { return false }
        EventIntake.post(.mouseDragged(button: .left, location: location))
        return true
    }

    private nonisolated func evaluateLeftMouseUp(at location: CGPoint, snap: Snapshot) -> Bool {
        let wasCaptured = snap.capturedInteractionButton == .left
        if wasCaptured {
            update { $0.capturedInteractionButton = nil }
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                MouseEventHandler._instance?.receiveTapMouseUp(at: location)
            }
        }
        return wasCaptured
    }

    private nonisolated func evaluateRightMouseDown(
        at location: CGPoint, modifiers: CGEventFlags, snap: Snapshot
    ) -> Bool {
        guard !snap.mouseResizeModifierFlags.isEmpty,
              MouseEventHandler.modifierFlagsMatch(modifiers, required: snap.mouseResizeModifierFlags)
        else { return false }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = MouseEventHandler._instance?.receiveTapMouseDown(at: location, modifiers: modifiers, button: .right)
            }
        }
        return true
    }

    private nonisolated func evaluateRightMouseDragged(at location: CGPoint, snap: Snapshot) -> Bool {
        guard snap.capturedInteractionButton == .right else { return false }
        EventIntake.post(.mouseDragged(button: .right, location: location))
        return true
    }

    private nonisolated func evaluateRightMouseUp(at location: CGPoint, snap: Snapshot) -> Bool {
        guard snap.capturedInteractionButton == .right else { return false }
        update { $0.capturedInteractionButton = nil }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                MouseEventHandler._instance?.receiveTapMouseUp(at: location, button: .right)
            }
        }
        return true
    }

    private nonisolated func evaluateOtherMouseDown(
        event: CGEvent, modifiers: CGEventFlags, snap: Snapshot
    ) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard snap.capturedOtherMouseButton == button || snap.claimedOtherMouseButtons.contains(button) else {
            return false
        }
        update { $0.capturedOtherMouseButton = button }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = MouseEventHandler._instance?.receiveTapOtherMouseButton(
                    type: .otherMouseDown,
                    button: button,
                    modifiers: modifiers
                )
            }
        }
        return true
    }

    private nonisolated func evaluateOtherMouseDragged(event: CGEvent, snap: Snapshot) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        return snap.capturedOtherMouseButton == button
    }

    private nonisolated func evaluateOtherMouseUp(
        event: CGEvent, modifiers: CGEventFlags, snap: Snapshot
    ) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard snap.capturedOtherMouseButton == button else { return false }
        update { $0.capturedOtherMouseButton = nil }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = MouseEventHandler._instance?.receiveTapOtherMouseButton(
                    type: .otherMouseUp,
                    button: button,
                    modifiers: modifiers
                )
            }
        }
        return true
    }

    private nonisolated func evaluateScrollWheel(
        event: CGEvent, at location: CGPoint, modifiers: CGEventFlags, snap: Snapshot
    ) -> Bool {
        let momentumPhase = UInt32(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
        let phase = UInt32(event.getIntegerValueField(.scrollWheelEventScrollPhase))
        if momentumPhase != 0 || phase != 0 {
            return snap.isTrackpadSwipeActive || snap.isTrackpadLatched
        }
        guard !snap.scrollModifierFlags.isEmpty,
              MouseEventHandler.mouseWheelModifiersMatch(modifiers, required: snap.scrollModifierFlags)
        else { return false }

        let payload = MouseEventHandler.scrollPayload(event, at: location, modifiersRawValue: modifiers.rawValue)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = MouseEventHandler._instance?.receiveTapScrollWheel(
                    payload.payload,
                    traceMetadata: payload.traceMetadata
                )
            }
        }
        return true
    }
}
