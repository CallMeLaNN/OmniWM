// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class WindowServerSubscriptionLiveTests: XCTestCase {
    private struct NativeWindowFixture: Decodable {
        let pid: Int32
        let windowIds: [UInt32]
    }

    private final class Sink: EventIntakeSink {
        var frameChangedWindowIds: Set<UInt32> = []

        func handleIntakeEvent(_ stamped: StampedIntakeEvent) {
            if case let .cgs(.frameChanged(windowId)) = stamped.event {
                frameChangedWindowIds.insert(windowId)
            }
        }
    }

    func testLiveSubscriptionCallReplacesThePriorCompleteSet() async throws {
        guard ProcessInfo.processInfo.environment["OMNIWM_RUN_WINDOW_SUBSCRIPTION_LIVE_TESTS"] == "1" else {
            throw XCTSkip(
                "Set OMNIWM_RUN_WINDOW_SUBSCRIPTION_LIVE_TESTS=1 to run private subscription semantics"
            )
        }

        let sky = SkyLight.shared
        let candidates = try await ownedForeignWindows()
        let (first, firstOrigin) = candidates[0]
        let (second, secondOrigin) = candidates[1]
        defer {
            _ = sky.moveWindow(first, to: firstOrigin)
            _ = sky.moveWindow(second, to: secondOrigin)
        }

        let intake = EventIntake()
        let sink = Sink()
        intake.open(sink: sink)
        defer { intake.close() }
        CGSEventObserver.shared.start()
        defer { CGSEventObserver.shared.stop() }

        XCTAssertTrue(CGSEventObserver.shared.subscribeToWindows([first, second]))
        guard sky.moveWindow(first, to: CGPoint(x: firstOrigin.x + 4, y: firstOrigin.y + 4)),
              sky.moveWindow(second, to: CGPoint(x: secondOrigin.x + 4, y: secondOrigin.y + 4))
        else {
            throw XCTSkip("SkyLight could not move both foreign test windows")
        }
        let observedCompleteSet = await waitUntil {
            sink.frameChangedWindowIds.contains(first)
                && sink.frameChangedWindowIds.contains(second)
        }
        guard observedCompleteSet else {
            throw XCTSkip("The test host did not deliver baseline WindowServer movement events")
        }

        try await Task.sleep(for: .milliseconds(50))
        intake.drainNow()
        sink.frameChangedWindowIds.removeAll()

        XCTAssertTrue(CGSEventObserver.shared.subscribeToWindows([second]))
        XCTAssertTrue(sky.moveWindow(first, to: CGPoint(x: firstOrigin.x + 8, y: firstOrigin.y + 8)))
        XCTAssertTrue(sky.moveWindow(second, to: CGPoint(x: secondOrigin.x + 8, y: secondOrigin.y + 8)))
        let observedReplacementSet = await waitUntil { sink.frameChangedWindowIds.contains(second) }
        XCTAssertTrue(observedReplacementSet)
        try await Task.sleep(for: .milliseconds(100))
        intake.drainNow()

        XCTAssertFalse(sink.frameChangedWindowIds.contains(first))
    }

    private func ownedForeignWindows() async throws -> [(UInt32, CGPoint)] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMNativeWindows-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let source = try XCTUnwrap(Bundle.module.url(
            forResource: "NativeWindowHost", withExtension: "swift", subdirectory: "Fixtures"
        ))
        let executable = directory.appendingPathComponent("native-window-host")
        let readyURL = directory.appendingPathComponent("ready.json")
        let logURL = directory.appendingPathComponent("host.log")
        try Data().write(to: logURL)
        let log = try FileHandle(forWritingTo: logURL)
        addTeardownBlock { try log.close() }

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = [
            "swiftc", "-swift-version", "6", "-warnings-as-errors", "-parse-as-library",
            source.path, "-o", executable.path
        ]
        compiler.standardOutput = FileHandle.nullDevice
        compiler.standardError = log
        let compiled = XCTestExpectation(description: "native fixture compilation finished")
        compiler.terminationHandler = { _ in compiled.fulfill() }
        try compiler.run()
        let compilation = await XCTWaiter.fulfillment(of: [compiled], timeout: 60)
        if compiler.isRunning {
            compiler.terminate()
            compiler.waitUntilExit()
        }
        let compilerLog = try String(contentsOf: logURL, encoding: .utf8)
        _ = try XCTUnwrap(
            compilation == .completed && compiler.terminationReason == .exit && compiler.terminationStatus == 0
                ? true : nil,
            "Native fixture compilation failed: \(compilerLog)"
        )

        let host = Process()
        let input = Pipe()
        let exited = XCTestExpectation(description: "owned native fixture exited")
        host.executableURL = executable
        host.arguments = [readyURL.path]
        host.standardInput = input
        host.standardOutput = FileHandle.nullDevice
        host.standardError = log
        host.terminationHandler = { _ in exited.fulfill() }
        do {
            try host.run()
        } catch {
            try input.fileHandleForWriting.close()
            throw error
        }
        addTeardownBlock { @MainActor in
            do { try input.fileHandleForWriting.close() }
            catch { XCTFail("Closing native fixture input failed: \(error)") }
            let completion = await XCTWaiter.fulfillment(of: [exited], timeout: 5)
            if host.isRunning {
                host.terminate()
                host.waitUntilExit()
            }
            XCTAssertEqual(completion, .completed, "Native fixture must exit after stdin EOF")
            XCTAssertEqual(host.terminationStatus, 0, "Native fixture must exit normally")
        }
        let sky = SkyLight.shared
        var ownedFixture: (pid: Int32, ids: [UInt32])?
        var candidates: [(UInt32, CGPoint)]?
        let ready = try await waitUntil(timeout: .seconds(5)) {
            guard host.isRunning else { return true }
            if ownedFixture == nil {
                guard FileManager.default.fileExists(atPath: readyURL.path) else { return false }
                let fixture = try JSONDecoder().decode(NativeWindowFixture.self, from: Data(contentsOf: readyURL))
                let fixturePID = try XCTUnwrap(
                    fixture.pid == host.processIdentifier && fixture.pid > 0 && fixture.pid != getpid() ? fixture
                        .pid : nil
                )
                let ids = try XCTUnwrap(
                    fixture.windowIds.count == 2 && Set(fixture.windowIds).count == 2 && !fixture.windowIds.contains(0)
                        ? fixture.windowIds : nil
                )
                ownedFixture = (fixturePID, ids)
            }
            guard let ownedFixture else { return false }
            let visible = sky.queryAllVisibleWindows()
            var observed: [(UInt32, CGPoint)] = []
            for id in ownedFixture.ids {
                guard let info = visible.first(where: {
                    $0.id == id && $0.pid == ownedFixture.pid && $0.level == 0 && $0.parentId == 0
                        && $0.frame.width >= 200 && $0.frame.height >= 120
                }), let origin = sky.getWindowBounds(info.id)?.origin else { return false }
                observed.append((info.id, origin))
            }
            candidates = observed
            return true
        }
        let hostLog = try String(contentsOf: logURL, encoding: .utf8)
        _ = try XCTUnwrap(
            ready && host.isRunning ? true : nil,
            "Owned native fixture did not become ready: \(hostLog)"
        )
        return try XCTUnwrap(candidates, "Only the exact owned foreign fixture windows may move")
    }

    private func waitUntil(
        timeout: Duration = .milliseconds(500),
        condition: @escaping @MainActor () throws -> Bool
    ) async rethrows -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if try condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return try condition()
    }
}
