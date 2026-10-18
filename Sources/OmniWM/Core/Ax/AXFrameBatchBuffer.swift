// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class AXFrameBatchBuffer {
    private var framesByPidBuffer: [pid_t: [AXFrameApplicationRequest]] = [:]
    private var frameApplicationBufferInUse = false
    private var pidBufferMetricsActive = false
    private var pidBufferMetrics = AXManagerPIDBufferRuntimeSnapshot()

    func withBuffer(targetCount: Int, _ apply: (inout [pid_t: [AXFrameApplicationRequest]]) -> Void) {
        if frameApplicationBufferInUse {
            var framesByPid: [pid_t: [AXFrameApplicationRequest]] = [:]
            framesByPid.reserveCapacity(min(targetCount, 8))
            apply(&framesByPid)
            return
        }
        frameApplicationBufferInUse = true
        defer {
            recordPIDBufferRuntimeState()
            if framesByPidBuffer.count > 8 {
                framesByPidBuffer.removeAll(keepingCapacity: true)
            } else {
                var index = framesByPidBuffer.startIndex
                while index != framesByPidBuffer.endIndex {
                    framesByPidBuffer.values[index].removeAll(keepingCapacity: true)
                    framesByPidBuffer.formIndex(after: &index)
                }
            }
            recordPIDBufferRuntimeState()
            frameApplicationBufferInUse = false
        }
        apply(&framesByPidBuffer)
    }

    func clear() {
        framesByPidBuffer.removeAll(keepingCapacity: false)
        recordPIDBufferRuntimeState()
    }

    func beginPIDBufferRuntimeCapture() {
        pidBufferMetrics = AXManagerPIDBufferRuntimeSnapshot(
            currentSize: framesByPidBuffer.count,
            highWater: framesByPidBuffer.count,
            retainedCapacity: framesByPidBuffer.capacity
        )
        pidBufferMetricsActive = true
    }

    func endPIDBufferRuntimeCapture() {
        recordPIDBufferRuntimeState()
        pidBufferMetricsActive = false
    }

    func pidBufferRuntimeSnapshot() -> AXManagerPIDBufferRuntimeSnapshot {
        var snapshot = pidBufferMetrics
        snapshot.currentSize = framesByPidBuffer.count
        snapshot.highWater = max(snapshot.highWater, snapshot.currentSize)
        snapshot.retainedCapacity = framesByPidBuffer.capacity
        return snapshot
    }

    private func recordPIDBufferRuntimeState() {
        guard pidBufferMetricsActive else { return }
        pidBufferMetrics.currentSize = framesByPidBuffer.count
        pidBufferMetrics.highWater = max(pidBufferMetrics.highWater, framesByPidBuffer.count)
        pidBufferMetrics.retainedCapacity = framesByPidBuffer.capacity
    }
}
