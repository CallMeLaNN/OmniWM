// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreFoundation
import Foundation

enum MainRunLoopActivityTrace {
    struct Record: Sendable {
        let sleeping: Bool
        let from: CFRunLoopActivity
        let to: CFRunLoopActivity
        let startNs: UInt64
        let endNs: UInt64
        let mode: String
    }

    static let minimumNanoseconds: UInt64 = 1_000_000

    static let shared = SessionTraceRecorder<Record>(
        sectionTitle: "Main Run Loop Activity",
        capacity: 16_384
    ) { record in
        "scope=main-run-loop t_ns=\(record.endNs) kind=\(record.sleeping ? "sleep" : "busy")"
            + " from=\(name(record.from)) to=\(name(record.to))"
            + " start_ns=\(record.startNs) end_ns=\(record.endNs)"
            + " total_us=\(String(format: "%.1f", Double(record.endNs &- record.startNs) / 1_000))"
            + " mode=\(record.mode)"
    }

    @MainActor private static var observers: [CFRunLoopObserver] = []

    @MainActor static func beginCapture() {
        guard observers.isEmpty, let mainRunLoop = CFRunLoopGetMain() else { return }
        let state = ActivityState(runLoop: mainRunLoop)
        let early: CFRunLoopActivity = [.entry, .beforeTimers, .beforeSources, .afterWaiting]
        let late: CFRunLoopActivity = [.beforeWaiting, .exit]
        observers = [(early, CFIndex.min), (late, CFIndex.max)].compactMap { activities, order in
            CFRunLoopObserverCreateWithHandler(nil, activities.rawValue, true, order) { _, activity in
                state.note(activity)
            }
        }
        let modes = (CFRunLoopCopyAllModes(mainRunLoop) as? [String] ?? []).map { CFRunLoopMode($0 as CFString) }
        for observer in observers {
            CFRunLoopAddObserver(mainRunLoop, observer, .commonModes)
            for mode in modes {
                CFRunLoopAddObserver(mainRunLoop, observer, mode)
            }
        }
    }

    @MainActor static func endCapture() {
        observers.forEach(CFRunLoopObserverInvalidate)
        observers = []
    }

    private static func name(_ activity: CFRunLoopActivity) -> String {
        switch activity {
        case .entry: "entry"
        case .beforeTimers: "before-timers"
        case .beforeSources: "before-sources"
        case .beforeWaiting: "before-waiting"
        case .afterWaiting: "after-waiting"
        case .exit: "exit"
        default: "other"
        }
    }

    private final class ActivityState {
        private let runLoop: CFRunLoop
        private var lastActivity: CFRunLoopActivity?
        private var lastNs: UInt64 = 0

        init(runLoop: CFRunLoop) {
            self.runLoop = runLoop
        }

        func note(_ activity: CFRunLoopActivity) {
            let now = DispatchTime.now().uptimeNanoseconds
            if let lastActivity, now &- lastNs >= MainRunLoopActivityTrace.minimumNanoseconds {
                MainRunLoopActivityTrace.shared.record(
                    .init(
                        sleeping: lastActivity == .beforeWaiting && activity == .afterWaiting,
                        from: lastActivity,
                        to: activity,
                        startNs: lastNs,
                        endNs: now,
                        mode: CFRunLoopCopyCurrentMode(runLoop).map { $0.rawValue as String } ?? "none"
                    )
                )
            }
            lastActivity = activity
            lastNs = now
        }
    }
}
