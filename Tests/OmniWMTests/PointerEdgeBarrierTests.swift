// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class PointerEdgeBarrierTests: XCTestCase {
    private let main = monitor(1, CGRect(x: 0, y: 0, width: 2560, height: 1440))
    private let staircase = monitor(2, CGRect(x: 2560, y: 1440, width: 1920, height: 1080))
    private let adjoining = monitor(3, CGRect(x: 2560, y: 0, width: 1920, height: 1440))

    private static func monitor(_ id: CGDirectDisplayID, _ frame: CGRect) -> Monitor {
        Monitor(
            id: .init(displayId: id),
            displayId: id,
            frame: frame,
            visibleFrame: frame,
            hasNotch: false,
            name: "M\(id)"
        )
    }

    private func topology(_ other: Monitor, margin: CGFloat = 1, fin: Bool = true) -> PointerEdgeTopology {
        var topology = PointerEdgeTopology()
        topology.isEnabled = true
        topology.margin = margin
        topology.flipY = 1440
        topology.monitors = [main, other]
        topology.edges[.init(monitorId: main.id, direction: .right)] = .init(
            target: other,
            finSpan: fin ? CGRect(x: 2559, y: 0, width: 1, height: 1440) : nil
        )
        return topology
    }

    private func move(
        _ recognizer: inout PointerEdgeRecognizer,
        _ x: CGFloat,
        _ y: CGFloat,
        dx: CGFloat,
        dy: CGFloat = 0,
        _ topology: PointerEdgeTopology
    ) -> PointerEdgeRecognizer.Decision {
        recognizer.handle(location: CGPoint(x: x, y: y), motion: CGVector(dx: dx, dy: dy), topology: topology)
    }

    func testPinnedEdgeExcludesArrivalAndCrossesOnceAtNetPressure() throws {
        let topology = topology(staircase)
        var recognizer = PointerEdgeRecognizer()
        XCTAssertEqual(move(&recognizer, 2500, 700, dx: 10, topology), .pass)
        XCTAssertEqual(move(&recognizer, 2559.5, 700, dx: 80, topology), .pass)
        XCTAssertEqual(recognizer.hold?.pressure, 0)
        for _ in 0 ..< 9 {
            XCTAssertEqual(move(&recognizer, 2559.5, 700, dx: 10, topology), .pass)
        }
        guard case let .cross(source, target, destination) = move(&recognizer, 2559.5, 700, dx: 10, topology) else {
            return XCTFail("expected crossing at threshold")
        }
        XCTAssertEqual(source, main.id)
        XCTAssertEqual(target.id, staircase.id)
        recognizer.didCross(to: target, at: destination)
        XCTAssertNil(recognizer.hold)
        let key = PointerEdgeTopology.EdgeKey(monitorId: main.id, direction: .right)
        XCTAssertEqual(
            recognizer.takeEvents(),
            [.started(token: 1, key: key), .ended(token: 1, crossedTo: staircase.id)]
        )
    }

    func testAdjoiningEdgeClampsNativeCrossingAndCountsPushedDistance() {
        let topology = topology(adjoining)
        var recognizer = PointerEdgeRecognizer()
        XCTAssertEqual(move(&recognizer, 2555, 700, dx: 5, topology), .pass)
        XCTAssertEqual(move(&recognizer, 2565, 700, dx: 10, topology), .clamp(CGPoint(x: 2559.5, y: 700)))
        XCTAssertEqual(move(&recognizer, 2609.5, 700, dx: 50, topology), .clamp(CGPoint(x: 2559.5, y: 700)))
        XCTAssertEqual(recognizer.hold?.pressure, 50)
        guard case .cross = move(&recognizer, 2609.5, 700, dx: 50, topology) else {
            return XCTFail("expected crossing at threshold")
        }
    }

    func testWideMarginAdjustmentAddsNothingAndInwardMovementSubtracts() {
        let topology = topology(staircase, margin: 10)
        var recognizer = PointerEdgeRecognizer()
        _ = move(&recognizer, 2551, 700, dx: 1, topology)
        for (x, dx) in [(2555.0, 4.0), (2551, -4), (2555, 4), (2551, -4), (2559.5, 8.5)] {
            XCTAssertEqual(move(&recognizer, x, 700, dx: dx, topology), .pass)
        }
        XCTAssertEqual(recognizer.hold?.pressure, 0)
        _ = move(&recognizer, 2559.5, 700, dx: 40, topology)
        XCTAssertEqual(recognizer.hold?.pressure, 40)
        _ = move(&recognizer, 2554.5, 700, dx: -5, topology)
        XCTAssertEqual(recognizer.hold?.pressure, 35)
    }

    func testRetreatMissingFinStickyHoldAndJump() {
        let offered = topology(staircase)
        let withdrawn = topology(staircase, fin: false)
        var recognizer = PointerEdgeRecognizer()
        _ = move(&recognizer, 2559.5, 700, dx: 5, offered)
        _ = move(&recognizer, 2540, 700, dx: -19.5, offered)
        XCTAssertNil(recognizer.hold)
        let key = PointerEdgeTopology.EdgeKey(monitorId: main.id, direction: .right)
        XCTAssertEqual(recognizer.takeEvents(), [.started(token: 1, key: key), .ended(token: 1, crossedTo: nil)])

        var plain = PointerEdgeRecognizer()
        XCTAssertEqual(move(&plain, 2559.5, 700, dx: 5, withdrawn), .pass)
        XCTAssertNil(plain.hold)

        _ = move(&recognizer, 2559.5, 700, dx: 19.5, offered)
        _ = move(&recognizer, 2559.5, 1200, dx: 0, dy: 500, withdrawn)
        XCTAssertNotNil(recognizer.hold)
        _ = move(&recognizer, 1000, 300, dx: 1, offered)
        XCTAssertNil(recognizer.hold)
    }

    func testMouseWarpSkipsClaimedEdgeForMovesButNotDrags() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMPointerEdge-\(UUID().uuidString)")
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config"),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(directory: root.appendingPathComponent("state"), deferSaves: false),
            autosaveEnabled: false
        )
        settings.pointer.enabled = true
        settings.pointer.margin = 1
        settings.monitors.routingMode = .macOS
        let controller = WMController(settings: settings)
        controller.workspaceManager.applyMonitorConfigurationChange([main, staircase])
        let handler = controller.mouseWarpHandler
        var warps = 0
        handler.activeDisplayBounds = { _ in .infinite }
        handler.warpCursor = { _ in
            warps += 1
            return .success
        }
        handler.postMouseMovedEvent = { _ in }
        defer { handler.resetTransientState() }

        let barrier = controller.pointerEdgeBarrier
        barrier.publish(topology(staircase))
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 2559.5, y: 740), mouseButton: .left
        ))
        XCTAssertNotNil(barrier.handleTapEvent(.mouseMoved, event))
        XCTAssertTrue(barrier.isClaimed(main.id, .right))

        let edge = CGPoint(x: 2559.5, y: 700)
        handler.handleMouseWarpMoved(at: main.frame.center)
        handler.handleMouseWarpMoved(at: edge)
        XCTAssertEqual(warps, 0)

        handler.handleMouseWarpMoved(at: edge, respectsPointerEdgeClaims: false)
        XCTAssertEqual(warps, 1)
    }
}
