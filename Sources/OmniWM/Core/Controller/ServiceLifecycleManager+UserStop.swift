// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension ServiceLifecycleManager {
    enum UserStopPhase {
        case idle
        case restoring
        case tearingDown
    }

    func stopRestoringWindows(forQuit: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil) {
        quitRequested = quitRequested || forQuit
        if let completion { stopCompletions.append(completion) }
        if userStopPhase == .tearingDown, stopDeadlineTask == nil {
            finishStopCompletions()
            return
        }
        guard userStopPhase == .idle else { return }
        userStopPhase = .restoring
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        let targets = stopWindowTargets()
        stopServices(retainingAXWorkers: true)
        Task {
            await recoverStopWindows(targets, deadline: deadline)
            finishStopRestoration(deadline: deadline)
        }
    }

    func finishStopRestoration(deadline: TimeInterval) {
        guard userStopPhase == .restoring else { return }
        userStopPhase = .tearingDown
        stopDeadlineTask = Task {
            do { try await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime))) }
            catch { return }
            stopDeadlineTask = nil
            Log.ax.error("Stop worker teardown is still pending at the restoration deadline")
            finishStopCompletions()
        }
        if let controller {
            controller.axManager.cleanup { self.finishStopTeardown() }
        } else {
            finishStopTeardown()
        }
    }

    func finishStopTeardown() {
        guard userStopPhase == .tearingDown else { return }
        stopDeadlineTask?.cancel()
        stopDeadlineTask = nil
        userStopPhase = .idle
        finishStopCompletions()
        controller?.reconcileEnabledAndHotkeysState()
        if controller?.desiredEnabled == true, !quitRequested { start() }
    }

    private func finishStopCompletions() {
        let completions = stopCompletions
        stopCompletions.removeAll()
        for completion in completions { completion() }
    }
}
