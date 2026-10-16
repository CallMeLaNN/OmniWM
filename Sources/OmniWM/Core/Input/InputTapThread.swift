// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

final class InputTapThread: @unchecked Sendable {
    private var thread: Thread?
    private var runLoopRef: CFRunLoop?
    private let condition = NSCondition()
    private var started = false

    var runLoop: CFRunLoop? {
        condition.lock()
        defer { condition.unlock() }
        return runLoopRef
    }

    func startAndGetRunLoop() -> CFRunLoop {
        condition.lock()
        defer { condition.unlock() }
        if !started {
            started = true
            let tapThread = Thread { [weak self] in
                guard let self else { return }
                let currentRunLoop = CFRunLoopGetCurrent()
                self.condition.lock()
                self.runLoopRef = currentRunLoop
                self.condition.signal()
                self.condition.unlock()

                var context = CFRunLoopSourceContext()
                if let dummySource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
                    CFRunLoopAddSource(currentRunLoop, dummySource, .commonModes)
                }

                while !Thread.current.isCancelled {
                    let result = CFRunLoopRunInMode(.defaultMode, 1.0e10, false)
                    if result == .stopped || result == .finished {
                        break
                    }
                }
            }
            tapThread.name = "app.omniwm.input-tap"
            tapThread.qualityOfService = .userInteractive
            self.thread = tapThread
            tapThread.start()

            while runLoopRef == nil {
                condition.wait()
            }
        }
        return runLoopRef!
    }

    func stop() {
        condition.lock()
        let loop = runLoopRef
        let targetThread = thread
        condition.unlock()
        targetThread?.cancel()
        if let loop {
            CFRunLoopStop(loop)
        }
    }
}
