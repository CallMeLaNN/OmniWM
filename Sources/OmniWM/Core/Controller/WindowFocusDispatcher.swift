// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Dispatch
import Foundation

@MainActor
final class WindowFocusDispatcher {
    static let shared = WindowFocusDispatcher()

    private let queue: DispatchQueue
    private let focus: @Sendable (pid_t, UInt32) -> Void
    private var submittedCount: UInt64 = 0
    private var completedCount: UInt64 = 0
    private var waiters: [(sequence: UInt64, work: @MainActor () -> Void)] = []

    init(
        label: String = "OmniWM-WindowFocus",
        focus: @escaping @Sendable (pid_t, UInt32) -> Void = { OmniWM.focusWindow(pid: $0, windowId: $1) }
    ) {
        queue = DispatchQueue(label: label, qos: .userInteractive)
        self.focus = focus
    }

    func submit(pid: pid_t, windowId: UInt32) {
        submittedCount &+= 1
        let tracing = WindowFocusDispatchTrace.shared.isActive
        let enqueuedNs = tracing ? DispatchTime.now().uptimeNanoseconds : 0
        let focus = focus
        queue.async { [weak self] in
            let startedNs = tracing ? DispatchTime.now().uptimeNanoseconds : 0
            focus(pid, windowId)
            let endedNs = tracing ? DispatchTime.now().uptimeNanoseconds : 0
            scheduleOnMainRunLoop {
                if tracing {
                    WindowFocusDispatchTrace.shared.record(
                        .init(
                            pid: pid,
                            windowId: windowId,
                            enqueuedNs: enqueuedNs,
                            startedNs: startedNs,
                            endedNs: endedNs,
                            completedNs: DispatchTime.now().uptimeNanoseconds
                        )
                    )
                }
                self?.completeSubmission()
            }
        }
    }

    func afterSubmitted(_ work: @escaping @MainActor () -> Void) {
        guard completedCount != submittedCount else {
            work()
            return
        }
        waiters.append((submittedCount, work))
    }

    nonisolated func waitForSubmitted() {
        queue.sync {}
    }

    func drain() {
        guard completedCount != submittedCount else { return }
        queue.sync {}
    }

    private func completeSubmission() {
        completedCount &+= 1
        while let waiter = waiters.first, waiter.sequence <= completedCount {
            waiters.removeFirst()
            waiter.work()
        }
    }
}
