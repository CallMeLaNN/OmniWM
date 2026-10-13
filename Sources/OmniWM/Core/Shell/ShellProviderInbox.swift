// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import Synchronization

final class ShellProviderInbox: Sendable {
    static let topicLimit = 64
    static let stateByteLimit = 1_048_576
    static let eventLimit = 256
    static let batchLimit = 16
    static let stateInterval: UInt64 = 33_333_334

    struct Capture: Equatable, Sendable {
        var id: UInt64 = 0
        var receivedStates: UInt64 = 0
        var coalescedStates: UInt64 = 0
        var consumedTopics: UInt64 = 0
        var consumedSnapshots: UInt64 = 0
        var actionsBegin = 0
        var actionsEnd = 0
        var actionsPeak = 0
        var eventsBegin = 0
        var eventsEnd = 0
        var eventsPeak = 0
        var wakes = ShellCaptureWakeCounters()

        var detail: String {
            "utility=provider_inbox states_received=\(receivedStates) states_coalesced=\(coalescedStates)"
                + " topics_consumed=\(consumedTopics) snapshots_consumed=\(consumedSnapshots)"
                + " action_begin=\(actionsBegin) action_end=\(actionsEnd) action_peak=\(actionsPeak)"
                + " event_begin=\(eventsBegin) event_end=\(eventsEnd) event_peak=\(eventsPeak) " + wakes.detail
        }
    }

    enum Status: Equatable, Sendable {
        case starting
        case running
        case exited(Int32)
        case failed(String)
    }

    enum Outcome: Equatable, Sendable {
        case provider(ok: Bool, value: Data, attachments: Data?)
        case failure(String)
        case resources(value: Data, ids: [ShellResourceID])
    }

    enum Work: Equatable, Sendable {
        case decodeResult(ShellResourceLeaseKey, Data)
        case importResult(ShellResourceLeaseKey, ShellPreparedProviderOutputs)
        case finishAction(ShellResourceLeaseKey)
    }

    enum Control: Equatable, Sendable {
        case event(name: String, value: Data)
        case result(id: ShellServiceID, outcome: Outcome)
    }

    struct Topic: Equatable, Sendable {
        let name: String
        let value: Data?
    }

    struct Snapshot: Equatable, Sendable {
        let topics: [Topic]
        let status: Status?
    }

    struct Delivery: Equatable, Sendable {
        let identity: ShellProviderIdentity
        let snapshot: Snapshot?
        let control: Control?
        var work: Work? = nil
    }

    enum Admission: Equatable, Sendable {
        case accepted
        case unchanged
        case ignored
        case failed(String)
    }

    enum Continuation: Equatable, Sendable {
        case idle
        case waking
        case deadline(UInt64)
    }

    struct Binding: Sendable {
        let identity: ShellProviderIdentity
        let configuration: ShellProviderConfiguration?
        let accepting: Bool
        let terminal: Bool
    }

    struct Counters: Equatable, Sendable {
        var coalescedStates: UInt64 = 0
        var ignoredResults: UInt64 = 0
    }

    private struct Slot {
        var value: Data
        var changed: Bool
    }

    private struct Entry {
        let identity: ShellProviderIdentity
        let configuration: ShellProviderConfiguration?
        var accepting = true
        var topics: [String: Slot] = [:]
        var deliveredTopics: Set<String> = []
        var byteCount = 0
        var lastConsumption: UInt64?
        var status: Status = .starting
        var statusPending = true
        var terminal = false

        var hasChanges: Bool {
            topics.values.contains { $0.changed } || deliveredTopics.contains { topics[$0] == nil }
        }

        var deadline: UInt64 {
            guard let lastConsumption else { return 0 }
            let result = lastConsumption.addingReportingOverflow(ShellProviderInbox.stateInterval)
            return result.overflow ? .max : result.partialValue
        }
    }

    private struct ResourceAction {
        enum Input: Equatable { case preparing, ready(Data), submitted, finished }
        enum Delivery { case active, consuming, done }
        enum Utility { case none, decoding, importing }
        let operation: ShellResourceOperation
        var input: Input = .preparing
        var delivery: Delivery = .active
        var utility: Utility = .none
        var cleanupStarted = false

        var canClean: Bool {
            delivery == .done && input != .submitted && utility == .none && !cleanupStarted
        }
    }

    private struct Registered {
        let identity: ShellProviderIdentity
        var queued = false
        var resource: ResourceAction?
    }

    private struct Queued {
        enum Preparation { case raw(Data), decoding, decoded(ShellPreparedProviderOutputs), importing }
        let identity: ShellProviderIdentity
        var control: Control
        var preparation: Preparation?

        var runnable: Bool {
            switch preparation {
            case .decoding?,
                 .importing?: false
            default: true
            }
        }
    }

    private struct State {
        var entries: [ShellServiceOwner: Entry] = [:]
        var registered: [ShellServiceID: Registered] = [:]
        var controls: [Queued] = []
        var eventCount = 0
        var counters = Counters()
        var wake: (@Sendable () -> Void)?
        var waking = false
        var deadline: UInt64?
        var closed = false
        var capture = Capture()
    }

    private let state = Mutex(State())

    func captureBegin(_ id: UInt64) {
        state.withLock {
            guard id != 0, $0.capture.id != id else { return }
            $0.capture = Capture(
                id: id, actionsBegin: $0.registered.count, actionsPeak: $0.registered.count,
                eventsBegin: $0.eventCount, eventsPeak: $0.eventCount
            )
        }
    }

    func captureEnd(_ id: UInt64) -> Capture? {
        state.withLock {
            guard id != 0, $0.capture.id == id else { return nil }
            $0.capture.actionsEnd = $0.registered.count
            $0.capture.eventsEnd = $0.eventCount
            defer { $0.capture = Capture() }
            return $0.capture
        }
    }

    func captureWakeConsumed() {
        state.withLock { if $0.capture.id != 0 { $0.capture.wakes.consume() } }
    }

    var counters: Counters {
        state.withLock { $0.counters }
    }

    var pendingEvents: Int {
        state.withLock { $0.eventCount }
    }

    var pendingActions: Int {
        state.withLock { $0.registered.count }
    }

    func identity(for owner: ShellServiceOwner) -> ShellProviderIdentity? {
        state.withLock {
            guard let entry = $0.entries[owner], !entry.terminal, entry.accepting else { return nil }
            return entry.identity
        }
    }

    func binding(for owner: ShellServiceOwner) -> Binding? {
        state.withLock {
            $0.entries[owner].map {
                Binding(
                    identity: $0.identity,
                    configuration: $0.configuration,
                    accepting: $0.accepting && !$0.terminal,
                    terminal: $0.terminal
                )
            }
        }
    }

    func stopAccepting(_ identity: ShellProviderIdentity) {
        state.withLock {
            guard $0.entries[identity.owner]?.identity == identity else { return }
            $0.entries[identity.owner]?.accepting = false
        }
    }

    func failUndispatched(_ id: ShellServiceID, error: String) {
        let callback = state.withLock { state -> (@Sendable () -> Void)? in
            guard !state.closed, state.registered[id] == nil else { return nil }
            let identity = ShellProviderIdentity(owner: id.owner, incarnation: 0)
            state.registered[id] = Registered(identity: identity, queued: true)
            if state.capture.id != 0 {
                state.capture.actionsPeak = max(state.capture.actionsPeak, state.registered.count)
            }
            state.controls.append(Queued(
                identity: identity,
                control: .result(id: id, outcome: .failure(Self.bounded(error)))
            ))
            return Self.wakeIfNeeded(&state, immediate: true)
        }
        callback?()
    }

    func attachWake(_ wake: @escaping @Sendable () -> Void) {
        let callback = state.withLock { state -> (@Sendable () -> Void)? in
            guard !state.closed else { return nil }
            state.wake = wake
            guard Self.hasRunnableControls(state) || state.entries.values
                .contains(where: { $0.statusPending || $0.hasChanges })
            else {
                return nil
            }
            return Self.wakeIfNeeded(&state, immediate: true)
        }
        callback?()
    }

    @discardableResult
    func activate(_ identity: ShellProviderIdentity, configuration: ShellProviderConfiguration? = nil) -> Bool {
        let result = state.withLock { state -> (Bool, (@Sendable () -> Void)?) in
            guard !state.closed else { return (false, nil) }
            if let previous = state.entries[identity.owner] {
                guard previous.terminal,
                      identity.incarnation > previous.identity.incarnation else { return (false, nil) }
            }
            state.entries[identity.owner] = Entry(identity: identity, configuration: configuration)
            return (true, Self.wakeIfNeeded(&state, immediate: true))
        }
        result.1?()
        return result.0
    }

    @discardableResult
    func register(
        _ id: ShellServiceID,
        identity: ShellProviderIdentity,
        operation: ShellResourceOperation? = nil
    ) -> Bool {
        state.withLock { state in
            guard !state.closed, id.owner == identity.owner,
                  let entry = state.entries[identity.owner], entry.identity == identity, !entry.terminal,
                  entry.accepting,
                  state.registered[id] == nil
            else { return false }
            state.registered[id] = Registered(
                identity: identity,
                resource: operation.map { ResourceAction(operation: $0) }
            )
            if state.capture.id != 0 {
                state.capture.actionsPeak = max(state.capture.actionsPeak, state.registered.count)
            }
            return true
        }
    }

    func isPending(_ id: ShellServiceID, identity: ShellProviderIdentity) -> Bool {
        state.withLock {
            guard let registered = $0.registered[id] else { return false }
            return registered.identity == identity && !registered.queued &&
                (registered.resource.map { $0.delivery == .active && $0.input == .submitted } ?? true)
        }
    }

    func running(_ identity: ShellProviderIdentity) {
        let callback = state.withLock { state -> (@Sendable () -> Void)? in
            guard var entry = state.entries[identity.owner], entry.identity == identity,
                  !entry.terminal else { return nil }
            guard entry.status != .running else { return nil }
            entry.status = .running
            entry.statusPending = true
            state.entries[identity.owner] = entry
            return Self.wakeIfNeeded(&state, immediate: true)
        }
        callback?()
    }

    @discardableResult
    func post(_ message: ShellProviderProtocol.Message, from identity: ShellProviderIdentity) -> Admission {
        let result = state.withLock { state -> (Admission, (@Sendable () -> Void)?) in
            if case let .result(token, _, _, _) = message, let request = ShellProviderProtocol.request(token) {
                let id = ShellServiceID(owner: identity.owner, request: request)
                if var registered = state.registered[id], registered.identity == identity,
                   registered.resource?.input == .submitted,
                   registered.resource?.delivery == .done || registered.queued
                {
                    registered.resource?.input = .finished
                    state.registered[id] = registered
                    return (.accepted, Self.wakeIfNeeded(&state, immediate: true))
                }
            }
            guard !state.closed, state.entries[identity.owner]?.identity == identity,
                  state.entries[identity.owner]?.terminal == false
            else {
                return (.ignored, nil)
            }
            switch message {
            case let .state(topic, value):
                if state.capture.id != 0 { state.capture.receivedStates &+= 1 }
                let change = Self.replaceState(&state.entries[identity.owner]!, topic: topic, value: value)
                if case let .failed(message) = change.admission {
                    Self.end(&state, identity: identity, status: .failed(message))
                    return (change.admission, Self.wakeIfNeeded(&state, immediate: true))
                }
                guard change.admission == .accepted else { return (change.admission, nil) }
                if change.coalesced {
                    Self.increment(&state.counters.coalescedStates)
                    if state.capture.id != 0 { state.capture.coalescedStates &+= 1 }
                }
                return (change.admission, Self.wakeIfNeeded(&state, immediate: false))
            case let .event(name, value):
                guard state.eventCount < Self.eventLimit else {
                    Self.end(&state, identity: identity, status: .failed("Provider event queue exceeded 256 entries"))
                    return (
                        .failed("Provider event queue exceeded 256 entries"),
                        Self.wakeIfNeeded(&state, immediate: true)
                    )
                }
                state.controls.append(Queued(identity: identity, control: .event(name: name, value: value)))
                state.eventCount += 1
                if state.capture.id != 0 { state.capture.eventsPeak = max(state.capture.eventsPeak, state.eventCount) }
            case let .result(token, ok, value, attachments):
                guard let request = ShellProviderProtocol.request(token) else {
                    Self.increment(&state.counters.ignoredResults)
                    return (.ignored, nil)
                }
                let id = ShellServiceID(owner: identity.owner, request: request)
                guard var registered = state.registered[id], registered.identity == identity, !registered.queued,
                      registered.resource.map({ $0.delivery == .active && $0.input == .submitted }) ?? true
                else {
                    Self.increment(&state.counters.ignoredResults)
                    return (.ignored, nil)
                }
                registered.queued = true
                registered.resource?.input = .finished
                state.registered[id] = registered
                let outputMetadata = ok ? attachments : nil
                let outcome: Outcome = outputMetadata == nil || registered.resource != nil
                    ? .provider(ok: ok, value: value, attachments: outputMetadata) :
                    .failure("unexpected_provider_files")
                state.controls.append(Queued(
                    identity: identity,
                    control: .result(id: id, outcome: outcome),
                    preparation: registered.resource != nil ? outputMetadata
                        .map(Queued.Preparation.raw) : nil
                ))
            }
            return (.accepted, Self.wakeIfNeeded(&state, immediate: true))
        }
        result.1?()
        return result.0
    }

    func failAction(_ id: ShellServiceID, identity: ShellProviderIdentity, error: String) {
        let callback = state.withLock { state -> (@Sendable () -> Void)? in
            guard var registered = state.registered[id], registered.identity == identity,
                  !registered.queued else { return nil }
            registered.queued = true
            state.registered[id] = registered
            state.controls.append(Queued(
                identity: identity,
                control: .result(id: id, outcome: .failure(Self.bounded(error)))
            ))
            return Self.wakeIfNeeded(&state, immediate: true)
        }
        callback?()
    }

    func end(_ identity: ShellProviderIdentity, status: Status) {
        let callback = state.withLock { state -> (@Sendable () -> Void)? in
            guard Self.end(&state, identity: identity, status: status) else { return nil }
            return Self.wakeIfNeeded(&state, immediate: true)
        }
        callback?()
    }

    func takeBatch(now: UInt64) -> [Delivery] {
        state.withLock { state in
            var result: [Delivery] = []
            result = Self.takeCleanup(&state, owner: nil)
            while result.count < Self.batchLimit, let queued = state.controls.first {
                guard queued.runnable else { break }
                if case let .result(id, _) = queued.control {
                    let key = ShellResourceLeaseKey(id: id, incarnation: queued.identity.incarnation)
                    switch queued.preparation {
                    case let .raw(bytes)?:
                        state.controls[0].preparation = .decoding
                        state.registered[id]?.resource?.utility = .decoding
                        result.append(Delivery(
                            identity: queued.identity,
                            snapshot: nil,
                            control: nil,
                            work: .decodeResult(key, bytes)
                        ))
                        return result
                    case let .decoded(outputs)?:
                        state.controls[0].preparation = .importing
                        state.registered[id]?.resource?.utility = .importing
                        result.append(Delivery(
                            identity: queued.identity,
                            snapshot: nil,
                            control: nil,
                            work: .importResult(key, outputs)
                        ))
                        return result
                    default: break
                    }
                    if state.registered[id]?.resource == nil { state.registered.removeValue(forKey: id) }
                } else { state.eventCount -= 1 }
                state.controls.removeFirst()
                result.append(Delivery(
                    identity: queued.identity,
                    snapshot: Self.consume(&state, identity: queued.identity, now: now),
                    control: queued.control
                ))
            }
            if result.count < Self.batchLimit {
                let identities = state.entries.values.compactMap { entry in
                    entry.statusPending || (entry.hasChanges && entry.deadline <= now) ? entry.identity : nil
                }
                for identity in identities.prefix(Self.batchLimit - result.count) {
                    if let snapshot = Self.consume(&state, identity: identity, now: now) {
                        result.append(Delivery(identity: identity, snapshot: snapshot, control: nil))
                    }
                }
            }
            return result
        }
    }

    func takeCleanup(owner: ShellServiceOwner? = nil) -> [Delivery] {
        state.withLock { Self.takeCleanup(&$0, owner: owner) }
    }

    private static func takeCleanup(_ state: inout State, owner: ShellServiceOwner?) -> [Delivery] {
        var result: [Delivery] = []
        for id in state.registered.keys.sorted(by: { $0.request < $1.request }) where result.count < batchLimit {
            guard owner == nil || id.owner == owner,
                  let registered = state.registered[id], registered.resource?.canClean == true else { continue }
            state.registered[id]?.resource?.cleanupStarted = true
            let key = ShellResourceLeaseKey(id: id, incarnation: registered.identity.incarnation)
            result.append(Delivery(
                identity: registered.identity,
                snapshot: nil,
                control: nil,
                work: .finishAction(key)
            ))
        }
        return result
    }

    func takeState(_ identity: ShellProviderIdentity, now: UInt64) -> Snapshot? {
        state.withLock { Self.consume(&$0, identity: identity, now: now) }
    }

    @discardableResult
    func finishBatch(now: UInt64) -> Continuation {
        let result = state.withLock { state -> (Continuation, (@Sendable () -> Void)?) in
            guard !state.closed else { return (.idle, nil) }
            if Self.hasRunnableControls(state) || state.entries.values.contains(where: {
                $0.statusPending || ($0.hasChanges && $0.deadline <= now)
            }) {
                state.deadline = nil
                state.waking = state.wake != nil
                if state.capture.id != 0, state.wake != nil { state.capture.wakes.emit() }
                return (.waking, state.wake)
            }
            state.waking = false
            state.deadline = state.entries.values.filter { $0.hasChanges }.map(\.deadline).min()
            return (state.deadline.map(Continuation.deadline) ?? .idle, nil)
        }
        result.1?()
        return result.0
    }

    func deadlineFired(_ expected: UInt64, now: UInt64) {
        let callback = state.withLock { state -> (@Sendable () -> Void)? in
            guard !state.closed, state.deadline == expected, now >= expected else { return nil }
            state.deadline = nil
            return Self.wakeIfNeeded(&state, immediate: true)
        }
        callback?()
    }

    func actionPrepared(_ key: ShellResourceLeaseKey, result: Result<Data, ShellResourceFailure>) -> Bool {
        let changed = state.withLock { state -> (Bool, (@Sendable () -> Void)?) in
            guard var registered = Self.registration(state, key), registered.resource?.delivery == .active,
                  registered.resource?.input == .preparing, !registered.queued else { return (false, nil) }
            switch result {
            case let .success(frame): registered.resource?.input = .ready(frame)
            case let .failure(error):
                registered.resource?.input = .finished
                registered.queued = true
                state.controls.append(Queued(
                    identity: registered.identity,
                    control: .result(id: key.id, outcome: .failure(Self.bounded(error.description)))
                ))
            }
            state.registered[key.id] = registered
            return (true, Self.wakeIfNeeded(&state, immediate: true))
        }
        changed.1?()
        return changed.0
    }

    func preparedFrame(_ key: ShellResourceLeaseKey) -> Data? {
        state.withLock { state in
            guard let registered = Self.registration(state, key), registered.resource?.delivery == .active,
                  case let .ready(frame)? = registered.resource?.input else { return nil }
            return frame
        }
    }

    func preparingAction(_ key: ShellResourceLeaseKey) -> Bool {
        state.withLock { state in
            guard let registered = Self.registration(state, key) else { return false }
            return registered.resource?.delivery == .active && registered.resource?.input == .preparing && !registered
                .queued
        }
    }

    func markSubmitted(_ key: ShellResourceLeaseKey) -> Bool {
        state.withLock { state in
            guard let registered = Self.registration(state, key), registered.resource?.delivery == .active,
                  !registered.queued,
                  case .ready? = registered.resource?.input,
                  let entry = state.entries[key.id.owner], entry.identity == registered.identity,
                  entry.accepting, !entry.terminal else { return false }
            state.registered[key.id]?.resource?.input = .submitted
            return true
        }
    }

    func actionUnsent(_ key: ShellResourceLeaseKey) {
        let wake = state.withLock { state -> (@Sendable () -> Void)? in
            guard Self.registration(state, key)?.resource != nil else { return nil }
            state.registered[key.id]?.resource?.input = .finished
            return Self.wakeIfNeeded(&state, immediate: true)
        }
        wake?()
    }

    func incarnationDrained(_ identity: ShellProviderIdentity) {
        let wake = state.withLock { state -> (@Sendable () -> Void)? in
            var changed = false
            for id in state.registered.keys
                where state.registered[id]?.identity == identity && state.registered[id]?.resource != nil
            {
                state.registered[id]?.resource?.input = .finished
                changed = true
            }
            return changed ? Self.wakeIfNeeded(&state, immediate: true) : nil
        }
        wake?()
    }

    @discardableResult
    func prepareResultMetadata(
        _ key: ShellResourceLeaseKey,
        result: Result<ShellPreparedProviderOutputs, ShellResourceFailure>
    ) -> Bool {
        let prepared = state.withLock { state -> (Bool, (@Sendable () -> Void)?) in
            guard let registered = Self.registration(state, key),
                  registered.resource?.utility == .decoding
            else { return (
                false,
                nil
            ) }
            state.registered[key.id]?.resource?.utility = .none
            guard registered.resource?.delivery == .active,
                  let index = Self.resultIndex(state, key), case .decoding? = state.controls[index].preparation
            else {
                return (false, Self.wakeIfNeeded(&state, immediate: true))
            }
            switch result {
            case let .success(outputs): state.controls[index].preparation = .decoded(outputs)
            case let .failure(error):
                state.controls[index].preparation = nil
                state.controls[index].control = .result(id: key.id, outcome: .failure(Self.bounded(error.description)))
            }
            return (true, Self.wakeIfNeeded(&state, immediate: true))
        }
        prepared.1?()
        return prepared.0
    }

    @discardableResult
    func finishResultImport(
        _ key: ShellResourceLeaseKey,
        result: Result<[ShellResourceID], ShellResourceFailure>
    ) -> Bool {
        let imported = state.withLock { state -> (Bool, (@Sendable () -> Void)?) in
            guard let registered = Self.registration(state, key),
                  registered.resource?.utility == .importing
            else { return (
                false,
                nil
            ) }
            state.registered[key.id]?.resource?.utility = .none
            guard registered.resource?.delivery == .active,
                  let index = Self.resultIndex(state, key), case .importing? = state.controls[index].preparation,
                  case let .result(_, .provider(true, value, _)) = state.controls[index].control
            else {
                return (false, Self.wakeIfNeeded(&state, immediate: true))
            }
            state.controls[index].preparation = nil
            switch result {
            case let .success(ids): state.controls[index].control = .result(
                    id: key.id,
                    outcome: .resources(value: value, ids: ids)
                )
            case let .failure(error): state.controls[index].control = .result(
                    id: key.id,
                    outcome: .failure(Self.bounded(error.description))
                )
            }
            return (true, Self.wakeIfNeeded(&state, immediate: true))
        }
        imported.1?()
        return imported.0
    }

    func beginResultDelivery(_ key: ShellResourceLeaseKey) -> Bool {
        state.withLock { state in
            guard let registered = Self.registration(state, key), registered.queued,
                  registered.resource?.delivery == .active,
                  registered.resource?.utility == ResourceAction.Utility.none else { return false }
            state.registered[key.id]?.resource?.delivery = .consuming
            return true
        }
    }

    func finishResultDelivery(_ key: ShellResourceLeaseKey) {
        let result = state.withLock { state -> (ShellResourceOperation?, (@Sendable () -> Void)?) in
            guard let registered = Self.registration(state, key),
                  registered.resource?.delivery == .consuming
            else { return (
                nil,
                nil
            ) }
            state.registered[key.id]?.resource?.delivery = .done
            return (registered.resource?.operation, Self.wakeIfNeeded(&state, immediate: true))
        }
        result.0?.cancel()
        result.1?()
    }

    func finishActionCleanup(_ key: ShellResourceLeaseKey) {
        state.withLock { state in
            guard Self.registration(state, key)?.resource?.cleanupStarted == true else { return }
            state.registered.removeValue(forKey: key.id)
        }
    }

    func cancel(_ id: ShellServiceID) {
        let result = state.withLock { state -> (ShellResourceOperation?, (@Sendable () -> Void)?) in
            guard var registered = state.registered[id] else { return (nil, nil) }
            if registered.resource?.delivery == .consuming { return (nil, nil) }
            state.controls.removeAll {
                if case let .result(resultID, _) = $0.control { return resultID == id }
                return false
            }
            guard registered.resource != nil else {
                state.registered.removeValue(forKey: id)
                return (nil, nil)
            }
            registered.resource?.delivery = .done
            state.registered[id] = registered
            return (registered.resource?.operation, Self.wakeIfNeeded(&state, immediate: true))
        }
        result.0?.cancel()
        result.1?()
    }

    func remove(owner: ShellServiceOwner) {
        let removed = state.withLock { state -> ([ShellResourceOperation], (@Sendable () -> Void)?) in
            var operations: [ShellResourceOperation] = []
            state.entries.removeValue(forKey: owner)
            for id in state.registered.keys where id.owner == owner {
                if let resource = state.registered[id]?.resource {
                    operations.append(resource.operation)
                    state.registered[id]?.resource?.delivery = .done
                } else { state.registered.removeValue(forKey: id) }
            }
            state.eventCount -= state.controls.reduce(0) { count, queued in
                guard queued.identity.owner == owner, case .event = queued.control else { return count }
                return count + 1
            }
            state.controls.removeAll { $0.identity.owner == owner }
            return (operations, operations.isEmpty ? nil : Self.wakeIfNeeded(&state, immediate: true))
        }
        for operation in removed.0 { operation.cancel() }
        removed.1?()
    }

    func close() {
        let ids = state.withLock { state -> [ShellServiceID] in
            state.closed = true
            state.entries.removeAll()
            state.controls.removeAll()
            state.eventCount = 0
            state.deadline = nil
            state.wake = nil
            state.waking = false
            return Array(state.registered.keys)
        }
        for id in ids { cancel(id) }
    }

    private static func registration(_ state: State, _ key: ShellResourceLeaseKey) -> Registered? {
        guard let registered = state.registered[key.id],
              registered.identity.incarnation == key.incarnation else { return nil }
        return registered
    }

    private static func resultIndex(_ state: State, _ key: ShellResourceLeaseKey) -> Int? {
        state.controls.firstIndex {
            guard $0.identity.incarnation == key.incarnation, case let .result(id, _) = $0.control else { return false }
            return id == key.id
        }
    }

    private static func hasRunnableControls(_ state: State) -> Bool {
        state.controls.first?.runnable == true || state.registered.values.contains { $0.resource?.canClean == true }
    }

    private static func wakeIfNeeded(_ state: inout State, immediate: Bool) -> (@Sendable () -> Void)? {
        guard !state.closed, !state.waking, let wake = state.wake,
              immediate || state.deadline == nil else { return nil }
        state.deadline = nil
        state.waking = true
        if state.capture.id != 0 { state.capture.wakes.emit() }
        return wake
    }

    private static func consume(_ state: inout State, identity: ShellProviderIdentity, now: UInt64) -> Snapshot? {
        guard var entry = state.entries[identity.owner], entry.identity == identity else { return nil }
        var topics: [Topic] = []
        for name in entry.topics.keys.sorted() where entry.topics[name]?.changed == true {
            if state.capture.id != 0 { state.capture.consumedTopics &+= 1 }
            topics.append(Topic(name: name, value: entry.topics[name]?.value))
            entry.topics[name]?.changed = false
        }
        for name in entry.deliveredTopics.sorted() where entry.topics[name] == nil {
            topics.append(Topic(name: name, value: nil))
        }
        let status = entry.statusPending ? entry.status : nil
        guard !topics.isEmpty || status != nil else { return nil }
        if state.capture.id != 0 { state.capture.consumedSnapshots &+= 1 }
        entry.statusPending = false
        if !topics.isEmpty {
            entry.deliveredTopics = Set(entry.topics.keys)
            entry.lastConsumption = now
        }
        state.entries[identity.owner] = entry
        return Snapshot(topics: topics, status: status)
    }

    private static func replaceState(
        _ entry: inout Entry,
        topic: String,
        value: Data
    ) -> (admission: Admission, coalesced: Bool) {
        let previous = entry.topics[topic]
        if value.elementsEqual([110, 117, 108, 108]) {
            guard let previous else { return (.unchanged, false) }
            entry.topics.removeValue(forKey: topic)
            entry.byteCount -= previous.value.count
        } else {
            guard previous?.value != value else { return (.unchanged, false) }
            let count = entry.byteCount - (previous?.value.count ?? 0) + value.count
            guard (previous != nil || entry.topics.count < topicLimit), count <= stateByteLimit else {
                return (.failed("Provider state limit exceeded"), false)
            }
            entry.topics[topic] = Slot(value: value, changed: true)
            entry.byteCount = count
        }
        return (.accepted, previous?.changed == true)
    }

    @discardableResult
    private static func end(_ state: inout State, identity: ShellProviderIdentity, status: Status) -> Bool {
        guard var entry = state.entries[identity.owner], entry.identity == identity,
              !entry.terminal else { return false }
        entry.terminal = true
        if case let .failed(error) = status { entry.status = .failed(bounded(error)) }
        else { entry.status = status }
        entry.statusPending = true
        state.entries[identity.owner] = entry
        state.eventCount -= state.controls.reduce(0) { count, queued in
            guard queued.identity == identity, case .event = queued.control else { return count }
            return count + 1
        }
        state.controls.removeAll {
            guard $0.identity == identity, case .event = $0.control else { return false }
            return true
        }
        let pending = state.registered.filter {
            $0.value.identity == identity && !$0.value
                .queued && ($0.value.resource?.delivery == .active || $0.value.resource == nil)
        }
        .map(\.key).sorted { $0.request < $1.request }
        for id in pending {
            state.registered[id]?.queued = true
            state.controls.append(Queued(
                identity: identity,
                control: .result(id: id, outcome: .failure("Provider disconnected"))
            ))
        }
        return true
    }

    private static func increment(_ count: inout UInt64) {
        if count != .max { count += 1 }
    }

    private static func bounded(_ message: String) -> String {
        String(message.prefix(1024))
    }
}
