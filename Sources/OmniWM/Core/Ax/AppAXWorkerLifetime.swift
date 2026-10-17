// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

@MainActor
final class AppAXWorkerLifetime {
    private struct Waiter {
        var workers: Set<UInt64>
        let completion: @MainActor @Sendable () -> Void
    }

    private var workers: Set<UInt64> = []
    private var waiters: [Waiter] = []

    func started(_ generation: UInt64) {
        workers.insert(generation)
    }

    func finished(_ generation: UInt64) {
        workers.remove(generation)
        var completions: [@MainActor @Sendable () -> Void] = []
        for index in waiters.indices {
            waiters[index].workers.remove(generation)
            if waiters[index].workers.isEmpty { completions.append(waiters[index].completion) }
        }
        waiters.removeAll { $0.workers.isEmpty }
        for completion in completions { completion() }
    }

    func whenFinished(_ completion: @escaping @MainActor @Sendable () -> Void) {
        if workers.isEmpty { completion() }
        else { waiters.append(Waiter(workers: workers, completion: completion)) }
    }
}
