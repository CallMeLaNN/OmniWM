// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class TrackpadPhysicalTraceTests: XCTestCase {
    func testPhysicalFingerTransitionsSurviveMailboxCoalescing() {
        let mailbox = MultitouchFrameMailbox()
        mailbox.activate(generation: 7)
        beginTrace()
        defer { endTrace() }

        offer(mailbox, fingers: 3, timestamp: 1.00)
        offer(mailbox, fingers: 2, timestamp: 1.01)
        offer(mailbox, fingers: 2, timestamp: 1.02)
        offer(mailbox, fingers: 3, timestamp: 1.03)
        offer(mailbox, fingers: 0, timestamp: 1.04)

        let deliveries = mailbox.take().deliveries
        XCTAssertEqual(deliveries.map(\.kind), [.began, .changed, .changed, .ended])
        XCTAssertEqual(deliveries.map(\.frame.touches.count), [3, 2, 3, 0])
        XCTAssertEqual(traceDetails, [
            "physical generation=7 slot=0 session=1 timestamp=1.0 fingers=3",
            "physical generation=7 slot=0 session=1 timestamp=1.01 fingers=2",
            "physical generation=7 slot=0 session=1 timestamp=1.03 fingers=3",
            "physical generation=7 slot=0 session=1 timestamp=1.04 fingers=0"
        ])
    }

    func testNonOwnerPhysicalTransitionsAreRecordedBeforeRouting() {
        let mailbox = MultitouchFrameMailbox()
        mailbox.activate(generation: 7)
        beginTrace()
        defer { endTrace() }

        offer(mailbox, fingers: 3, timestamp: 1.00)
        offer(mailbox, fingers: 2, timestamp: 1.01, slot: 1)
        offer(mailbox, fingers: 1, timestamp: 1.02, slot: 1)
        offer(mailbox, fingers: 0, timestamp: 1.03, slot: 1)

        XCTAssertEqual(mailbox.take().deliveries.map(\.slot), [0])
        XCTAssertEqual(traceDetails, [
            "physical generation=7 slot=0 session=1 timestamp=1.0 fingers=3",
            "physical generation=7 slot=1 session=1 timestamp=1.01 fingers=2",
            "physical generation=7 slot=1 session=1 timestamp=1.02 fingers=1",
            "physical generation=7 slot=1 session=1 timestamp=1.03 fingers=0"
        ])
    }

    func testResetsAndLiftPreservePhysicalSessionIdentity() {
        let mailbox = MultitouchFrameMailbox()
        beginTrace()
        defer { endTrace() }

        mailbox.activate(generation: 7)
        offer(mailbox, fingers: 3, timestamp: 1.00)
        offer(mailbox, fingers: 3, timestamp: 1.20)
        offer(mailbox, fingers: 0, timestamp: 1.21)
        offer(mailbox, fingers: 2, timestamp: 1.22)
        mailbox.activate(generation: 8)
        offer(mailbox, fingers: 1, timestamp: 1.23)
        offer(mailbox, fingers: 2, timestamp: 1.24, generation: 8)
        mailbox.invalidate()
        offer(mailbox, fingers: 0, timestamp: 1.25, generation: 8)

        XCTAssertEqual(traceDetails, [
            "reset generation=7",
            "physical generation=7 slot=0 session=1 timestamp=1.0 fingers=3",
            "physical generation=7 slot=0 session=1 timestamp=1.21 fingers=0",
            "physical generation=7 slot=0 session=2 timestamp=1.22 fingers=2",
            "reset generation=8",
            "physical generation=8 slot=0 session=1 timestamp=1.24 fingers=2",
            "reset generation=0"
        ])
    }

    func testInactiveCaptureRecordsNothingAndMidContactCaptureSeedsCurrentCounts() {
        endTrace()
        let mailbox = MultitouchFrameMailbox()
        mailbox.activate(generation: 7)
        offer(mailbox, fingers: 3, timestamp: 1.00)
        offer(mailbox, fingers: 2, timestamp: 1.01)
        _ = mailbox.take()
        mailbox.recordTraceSnapshot(slotCount: 2)
        XCTAssertEqual(TrackpadScrollTrace.shared.dump(), "none")

        beginTrace()
        defer { endTrace() }
        mailbox.recordTraceSnapshot(slotCount: 2)
        offer(mailbox, fingers: 2, timestamp: 1.02)
        offer(mailbox, fingers: 0, timestamp: 1.03)

        XCTAssertEqual(traceDetails, [
            "physical generation=7 slot=0 session=1 timestamp=none fingers=2",
            "physical generation=7 slot=1 session=0 timestamp=none fingers=0",
            "physical generation=7 slot=0 session=1 timestamp=1.03 fingers=0"
        ])
    }

    func testNewCaptureSeedsUnchangedCountWithCurrentSession() {
        let mailbox = MultitouchFrameMailbox()
        mailbox.activate(generation: 7)
        beginTrace()
        offer(mailbox, fingers: 3, timestamp: 1.00)
        endTrace()

        offer(mailbox, fingers: 0, timestamp: 1.01)
        offer(mailbox, fingers: 3, timestamp: 1.02)
        beginTrace()
        defer { endTrace() }
        mailbox.recordTraceSnapshot(slotCount: 1)

        XCTAssertEqual(traceDetails, [
            "physical generation=7 slot=0 session=2 timestamp=none fingers=3"
        ])
    }

    func testSourceSnapshotSeedsDeviceMappingsAndCurrentRawContacts() async throws {
        endTrace()
        let backend = FakeMultitouchBackend()
        backend.enumerations = [FakeMultitouchBackend.enumeration([
            FakeMultitouchBackend.device(pointer: 0xA1, registryId: 101, senderId: 901),
            FakeMultitouchBackend.device(pointer: 0xB1, registryId: 202)
        ])]
        let sleeper = ManualMultitouchSleeper()
        let source = MultitouchGestureSource(operations: backend.operations(sleeper: sleeper))
        defer {
            endTrace()
            source.shutdown()
            await sleeper.resumeAll()
        }
        source.startLifecycle()
        try await sleeper.waitForScheduledSleep(of: source)
        try await sleeper.resumeNext()
        let generation = try XCTUnwrap(source.diagnosticsSnapshot().activeGeneration)
        backend.emitFrame(registryId: 101, touches: [(0.4, 0.5), (0.5, 0.5)], timestamp: 1.00)
        source.drainRawFrameMailbox(location: .zero)

        beginTrace()
        source.recordTraceSnapshot()

        XCTAssertEqual(traceDetails, [
            "source generation=\(generation) slot=0 registry=101 sender=901",
            "source generation=\(generation) slot=1 registry=202 sender=none",
            "physical generation=\(generation) slot=0 session=1 timestamp=none fingers=2",
            "physical generation=\(generation) slot=1 session=0 timestamp=none fingers=0"
        ])
    }

    func testRegistrationDuringCaptureEmitsMappingsAfterGenerationReset() async throws {
        beginTrace()
        let backend = FakeMultitouchBackend()
        backend.enumerations = [FakeMultitouchBackend.enumeration([
            FakeMultitouchBackend.device(pointer: 0xA1, registryId: 101, senderId: 901)
        ])]
        let sleeper = ManualMultitouchSleeper()
        let source = MultitouchGestureSource(operations: backend.operations(sleeper: sleeper))
        defer {
            endTrace()
            source.shutdown()
            await sleeper.resumeAll()
        }
        source.startLifecycle()
        try await sleeper.waitForScheduledSleep(of: source)
        try await sleeper.resumeNext()
        let generation = try XCTUnwrap(source.diagnosticsSnapshot().activeGeneration)

        XCTAssertEqual(traceDetails, [
            "reset generation=0",
            "reset generation=\(generation)",
            "source generation=\(generation) slot=0 registry=101 sender=901",
            "physical generation=\(generation) slot=0 session=0 timestamp=none fingers=0"
        ])
    }

    private var traceDetails: [String] {
        TrackpadScrollTrace.shared.dump().split(separator: "\n").map { line in
            String(line.split(separator: " ", maxSplits: 1).last ?? line)
        }
    }

    private func beginTrace() {
        TrackpadScrollTrace.shared.beginCapture()
    }

    private func endTrace() {
        TrackpadScrollTrace.shared.endCapture()
        TrackpadScrollTrace.shared.releaseStorage()
    }

    private func offer(
        _ mailbox: MultitouchFrameMailbox,
        fingers: Int,
        timestamp: Double,
        slot: Int = 0,
        generation: UInt = 7
    ) {
        let touches = Array(repeating: MultitouchGestureSource.RawTouch(x: 0.5, y: 0.5), count: fingers)
        _ = mailbox.offer(.init(touches: touches, timestamp: timestamp), generation: generation, slot: slot)
    }
}
