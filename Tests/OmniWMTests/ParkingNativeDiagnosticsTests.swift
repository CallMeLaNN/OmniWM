// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import ApplicationServices
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class ParkingNativeDiagnosticsTests: XCTestCase {
    func testFilteredParkIsNotReportedAsSubmitted() {
        let controller = WindowAdmissionTestSupport.controller()
        let token = WindowToken(pid: 999_991, windowId: 999_992)
        controller.axManager.setMacOSAppHidden(true, pid: token.pid, entries: [])
        defer { controller.axManager.cleanup() }
        FrameApplyTrace.shared.beginCapture()
        defer { FrameApplyTrace.shared.endCapture() }
        let result = controller.axManager.applyPositionsViaSkyLight(
            [.init(token: token, frame: CGRect(x: -1000, y: 0, width: 800, height: 600))],
            allowInactive: true, tracingPark: true
        )
        XCTAssertEqual(result, .submitted)
        let dump = FrameApplyTrace.shared.dump()
        XCTAssertTrue(dump.contains("event=outcome=sls-park-submission/filtered"), dump)
        XCTAssertTrue(dump.contains("win=999992 pid=999991"), dump)
        XCTAssertFalse(dump.contains("event=outcome=sls-park-submission/submitted"), dump)
    }

    func testSixteenHiddenSamplesKeepSeparateReadIntervalsAndParkOwnership() {
        FrameApplyTrace.shared.beginCapture()
        defer { FrameApplyTrace.shared.endCapture() }
        let frame = CGRect(x: -1000, y: 0, width: 800, height: 600)
        for index in 0 ..< 16 {
            FrameApplyTrace.recordEvent(
                pid: 999_991, windowId: 990_000 + index,
                outcome: "outcome=hidden-park-sample reason=layoutTransient(left) pending=true",
                target: frame, observed: frame, requestId: 77,
                lane: .park, uptimeNs: 20, readStartedNs: 10
            )
        }
        let dump = FrameApplyTrace.shared.dump()
        let lines = dump.components(separatedBy: "\n").filter { $0.contains("outcome=hidden-park-sample") }
        XCTAssertEqual(lines.count, 16)
        for index in 0 ..< 16 {
            XCTAssertTrue(lines[index].contains("win=\(990_000 + index)"), dump)
            XCTAssertTrue(lines[index].contains("t_ns=20"), dump)
            XCTAssertTrue(lines[index].contains("read_start_ns=10"), dump)
            XCTAssertTrue(lines[index].contains("observed=\(TraceFormat.rect(frame))"), dump)
            XCTAssertTrue(lines[index].contains("request=77"), dump)
            XCTAssertLessThan(lines[index].utf8.count, 4096)
        }
    }

    func testPreWriteReadTimingOnlyCoversAnUnhintedWholeFrameWrite() {
        let window = AXWindowRef(element: AXUIElementCreateApplication(999_991), windowId: 999_992)
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let hinted = AXWindowService.setFrameTraced(window, frame: frame, currentFrameHint: frame, verify: false)
        XCTAssertEqual(hinted.timing.preReadNs, 0)
        for component: AXFrameComponents in [.position, .size] {
            let partial = AXWindowService.setFrameTraced(window, frame: frame, components: component, verify: false)
            XCTAssertEqual(partial.timing.preReadNs, 0)
        }
        let unhinted = AXWindowService.setFrameTraced(window, frame: frame, verify: false)
        XCTAssertGreaterThan(unhinted.timing.preReadNs, 0)
        XCTAssertEqual(unhinted.result.writeOrder, .sizeThenPosition)
    }
}
