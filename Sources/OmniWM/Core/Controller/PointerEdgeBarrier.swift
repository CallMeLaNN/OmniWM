// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import CoreGraphics
import Foundation
import Synchronization

struct PointerEdgeTopology: Sendable {
    struct EdgeKey: Hashable, Sendable {
        let monitorId: Monitor.ID
        let direction: Direction
    }

    struct Edge: Sendable {
        let target: Monitor?
        let finSpan: CGRect?
    }

    static let pushDistance: CGFloat = 96

    var isEnabled = false
    var margin: CGFloat = 1
    var flipY: CGFloat = 0
    var monitors: [Monitor] = []
    var edges: [EdgeKey: Edge] = [:]

    func monitor(_ id: Monitor.ID) -> Monitor? {
        monitors.first { $0.id == id }
    }

    func monitor(containing point: CGPoint) -> Monitor? {
        monitors.first { $0.frame.contains(point) }
    }
}

struct PointerEdgeRecognizer: Sendable {
    struct Hold: Equatable, Sendable {
        let key: PointerEdgeTopology.EdgeKey
        let token: UInt64
        var pressure: CGFloat
        var outward: CGFloat
    }

    enum Decision: Equatable {
        case pass
        case clamp(CGPoint)
        case cross(source: Monitor.ID, target: Monitor, destination: CGPoint)
    }

    enum Event: Equatable, Sendable {
        case started(token: UInt64, key: PointerEdgeTopology.EdgeKey)
        case ended(token: UInt64, crossedTo: Monitor.ID?)
    }

    private(set) var hold: Hold?
    private var lastLocation: CGPoint?
    private var lastMonitorId: Monitor.ID?
    private var nextToken: UInt64 = 0
    private var events: [Event] = []

    mutating func takeEvents() -> [Event] {
        guard !events.isEmpty else { return [] }
        let taken = events
        events = []
        return taken
    }

    mutating func reset() {
        endHold(crossedTo: nil)
        lastLocation = nil
        lastMonitorId = nil
    }

    mutating func didCross(to target: Monitor, at destination: CGPoint) {
        endHold(crossedTo: target.id)
        lastMonitorId = target.id
        lastLocation = destination
    }

    mutating func crossFailed() {
        hold?.pressure = 0
    }

    mutating func handle(location: CGPoint, motion: CGVector, topology: PointerEdgeTopology) -> Decision {
        guard topology.isEnabled else {
            reset()
            return .pass
        }
        if let last = lastLocation {
            let moved = hypot(motion.dx, motion.dy)
            if hypot(location.x - last.x, location.y - last.y) > moved + max(3, moved * 0.3) {
                reset()
            }
        }
        guard let source = lastMonitorId.flatMap(topology.monitor) ?? topology.monitor(containing: location) else {
            lastLocation = location
            return .pass
        }
        let inside = source.frame.contains(location)
        let direction = inside
            ? MouseWarpGeometry.crossing(location: location, frame: source.frame, margin: topology.margin)?.direction
            : Self.exitDirection(of: location, from: source.frame)
        let key = direction.map { PointerEdgeTopology.EdgeKey(monitorId: source.id, direction: $0) }
        let edge = key.flatMap { topology.edges[$0] }
        let continuing = hold != nil && hold?.key == key && edge?.target != nil
        let starting = !continuing && edge?.target != nil
            && edge?.finSpan.map { Self.spans($0, location, direction) } == true
        guard let key, let direction, continuing || starting else {
            endHold(crossedTo: nil)
            lastMonitorId = topology.monitor(containing: location)?.id ?? source.id
            lastLocation = location
            return .pass
        }

        let accepted = inside ? location : Self.edgePoint(location, in: source.frame, direction: direction)
        let outward = Self.outward(accepted, direction)
        lastMonitorId = source.id
        lastLocation = accepted
        if starting {
            endHold(crossedTo: nil)
            nextToken &+= 1
            hold = Hold(key: key, token: nextToken, pressure: 0, outward: outward)
            events.append(.started(token: nextToken, key: key))
        } else if var current = hold {
            let push = Self.outward(motion, direction) - max(0, outward - current.outward)
            current.pressure = max(0, current.pressure + push)
            current.outward = outward
            hold = current
            if current.pressure >= PointerEdgeTopology.pushDistance,
               let target = edge?.target,
               let crossing = MouseWarpGeometry.crossing(
                   location: accepted,
                   frame: source.frame,
                   margin: topology.margin
               )
            {
                let destination = MouseWarpGeometry.destinationPoint(
                    on: target.frame,
                    entryEdge: crossing.entryEdge,
                    ratio: crossing.ratio,
                    margin: topology.margin
                )
                return .cross(source: source.id, target: target, destination: destination)
            }
        }
        return accepted == location ? .pass : .clamp(accepted)
    }

    private mutating func endHold(crossedTo: Monitor.ID?) {
        guard let hold else { return }
        events.append(.ended(token: hold.token, crossedTo: crossedTo))
        self.hold = nil
    }

    static func exitDirection(of point: CGPoint, from frame: CGRect) -> Direction? {
        let overshoots: [(Direction, CGFloat)] = [
            (.right, point.x - frame.maxX),
            (.left, frame.minX - point.x),
            (.up, point.y - frame.maxY),
            (.down, frame.minY - point.y)
        ]
        return overshoots.filter { $0.1 >= 0 }.max { $0.1 < $1.1 }?.0
    }

    static func edgePoint(_ point: CGPoint, in frame: CGRect, direction: Direction) -> CGPoint {
        let x = min(max(point.x, frame.minX), frame.maxX - 0.5)
        let y = min(max(point.y, frame.minY + 0.5), frame.maxY - 0.5)
        switch direction {
        case .right: return CGPoint(x: frame.maxX - 0.5, y: y)
        case .left: return CGPoint(x: frame.minX, y: y)
        case .up: return CGPoint(x: x, y: frame.maxY - 0.5)
        case .down: return CGPoint(x: x, y: frame.minY + 0.5)
        }
    }

    static func outward(_ point: CGPoint, _ direction: Direction) -> CGFloat {
        switch direction {
        case .right: point.x
        case .left: -point.x
        case .up: point.y
        case .down: -point.y
        }
    }

    static func outward(_ vector: CGVector, _ direction: Direction) -> CGFloat {
        outward(CGPoint(x: vector.dx, y: vector.dy), direction)
    }

    private static func spans(_ span: CGRect, _ point: CGPoint, _ direction: Direction?) -> Bool {
        switch direction {
        case .left,
             .right: point.y >= span.minY && point.y <= span.maxY
        case .up,
             .down: point.x >= span.minX && point.x <= span.maxX
        case nil: false
        }
    }
}

final class PointerEdgeBarrier: Sendable {
    private struct State {
        var topology = PointerEdgeTopology()
        var recognizer = PointerEdgeRecognizer()
        var claims: [UInt64: PointerEdgeTopology.EdgeKey] = [:]
    }

    private struct TapState {
        var runLoop: CFRunLoop?
        var running = false
        var stopRequested = false
        var needsReenable = false
    }

    private let state = Mutex(State())
    private let tapState = Mutex(TapState())
    private let installsTap: Bool

    init(installsTap: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil) {
        self.installsTap = installsTap
    }

    func publish(_ topology: PointerEdgeTopology) {
        state.withLock { $0.topology = topology }
    }

    func isClaimed(_ monitorId: Monitor.ID, _ direction: Direction) -> Bool {
        let key = PointerEdgeTopology.EdgeKey(monitorId: monitorId, direction: direction)
        return state.withLock { $0.claims.values.contains(key) }
    }

    func acknowledge(token: UInt64) {
        state.withLock { _ = $0.claims.removeValue(forKey: token) }
    }

    func reset() {
        state.withLock { current in
            current.recognizer.reset()
            _ = current.recognizer.takeEvents()
            current.claims.removeAll()
        }
    }

    func start() {
        guard installsTap else { return }
        let shouldStart = tapState.withLock { current -> Bool in
            current.stopRequested = false
            guard !current.running else { return false }
            current.running = true
            return true
        }
        guard shouldStart else { return }
        let thread = Thread { [self] in runTap() }
        thread.name = "OmniWM.PointerEdge"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        let runLoop = tapState.withLock { current -> CFRunLoop? in
            current.stopRequested = true
            return current.runLoop
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        reset()
    }

    private func runTap() {
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<PointerEdgeBarrier>.fromOpaque(info).takeUnretainedValue().handleTapEvent(type, event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.mouseMoved.rawValue,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else {
            MouseTrace.record("pointer-edge tap unavailable")
            tapState.withLock { $0 = TapState() }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tapState.withLock { $0.runLoop = CFRunLoopGetCurrent() }
        while true {
            let (stop, reenable) = tapState.withLock { current -> (Bool, Bool) in
                if current.stopRequested {
                    current = TapState()
                    return (true, false)
                }
                defer { current.needsReenable = false }
                return (false, current.needsReenable)
            }
            if stop { break }
            if reenable {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            CFRunLoopRun()
        }
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        CFMachPortInvalidate(port)
    }

    func handleTapEvent(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapState.withLock { $0.needsReenable = true }
            CFRunLoopStop(CFRunLoopGetCurrent())
            reset()
            return Unmanaged.passUnretained(event)
        }
        guard type == .mouseMoved else { return Unmanaged.passUnretained(event) }
        let cgLocation = event.location
        let cgDeltaX = event.getDoubleValueField(.mouseEventDeltaX)
        let cgDeltaY = event.getDoubleValueField(.mouseEventDeltaY)
        let (decision, flipY, endings) = state.withLock { current in
            let flipY = current.topology.flipY
            let decision = current.recognizer.handle(
                location: CGPoint(x: cgLocation.x, y: flipY - cgLocation.y),
                motion: CGVector(dx: cgDeltaX, dy: -cgDeltaY),
                topology: current.topology
            )
            return (decision, flipY, Self.applyEvents(current.recognizer.takeEvents(), to: &current))
        }
        post(endings)
        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case let .clamp(point):
            event.location = CGPoint(x: point.x, y: flipY - point.y)
            return Unmanaged.passUnretained(event)
        case let .cross(source, target, destination):
            let warpPoint = CGPoint(x: destination.x, y: flipY - destination.y)
            let error: CGError = CGDisplayIsActive(target.displayId) != 0
                && CGDisplayBounds(target.displayId).contains(warpPoint)
                ? CGWarpMouseCursorPosition(warpPoint) : .illegalArgument
            let crossed = state.withLock { current in
                if error == .success {
                    current.recognizer.didCross(to: target, at: destination)
                } else {
                    current.recognizer.crossFailed()
                }
                return Self.applyEvents(current.recognizer.takeEvents(), to: &current)
            }
            post(crossed)
            MouseTrace.record(
                "edge-warp pushed from=\(source) to=\(target.id) dest=\(TraceFormat.point(destination)) "
                    + "warp=\(TraceFormat.point(warpPoint)) result=\(error.rawValue)"
            )
            guard error == .success else { return Unmanaged.passUnretained(event) }
            DispatchQueue.global(qos: .userInteractive).async {
                CGEvent(
                    mouseEventSource: nil,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: warpPoint,
                    mouseButton: .left
                )?
                    .post(tap: .cghidEventTap)
            }
            return nil
        }
    }

    private static func applyEvents(
        _ events: [PointerEdgeRecognizer.Event],
        to state: inout State
    ) -> [(UInt64, Monitor.ID?)] {
        var endings: [(UInt64, Monitor.ID?)] = []
        for event in events {
            switch event {
            case let .started(token, key):
                state.claims[token] = key
            case let .ended(token, crossedTo):
                endings.append((token, crossedTo))
            }
        }
        return endings
    }

    private func post(_ endings: [(UInt64, Monitor.ID?)]) {
        for (token, crossedTo) in endings {
            if !EventIntake.post(.pointerEdgeHoldEnded(token: token, crossedTo: crossedTo)) {
                acknowledge(token: token)
            }
        }
    }
}
