// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreFoundation
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class MainRunLoopActivityTraceTests: XCTestCase {
    func testCaptureRecordsBlockedMainRunLoopPassAndStopsAfterEnd() throws {
        let recorder = MainRunLoopActivityTrace.shared
        recorder.beginCapture()
        MainRunLoopActivityTrace.beginCapture()
        defer {
            MainRunLoopActivityTrace.endCapture()
            recorder.endCapture()
            recorder.releaseStorage()
        }

        runMainLoopPass(blockingMicroseconds: 3_000)
        MainRunLoopActivityTrace.endCapture()
        let captured = recorder.dump()
        runMainLoopPass(blockingMicroseconds: 3_000)

        let busy = captured.split(separator: "\n").filter {
            $0.contains("kind=busy") && $0.contains("mode=kCFRunLoopDefaultMode")
        }
        let longest = busy.compactMap { line in
            line.split(separator: " ").first { $0.hasPrefix("total_us=") }.flatMap { Double($0.dropFirst(9)) }
        }.max()
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(longest), 3_000)
        XCTAssertEqual(recorder.dump(), captured)
    }

    private func runMainLoopPass(blockingMicroseconds: UInt32) {
        let mainRunLoop = CFRunLoopGetMain()
        var ran = false
        CFRunLoopPerformBlock(mainRunLoop, CFRunLoopMode.defaultMode.rawValue) {
            usleep(blockingMicroseconds)
            ran = true
            CFRunLoopStop(mainRunLoop)
        }
        while !ran {
            _ = CFRunLoopRunInMode(.defaultMode, 1, true)
        }
    }
}
