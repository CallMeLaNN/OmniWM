// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Darwin
import Foundation
import Synchronization

actor ShellProvider {
    struct Capture: Equatable, Sendable {
        let framing: ShellProviderLineFramer.Capture
        let wakes: ShellCaptureWakeCounters

        var id: UInt64 {
            framing.id
        }

        var detail: String {
            framing.detail + " " + wakes.detail
        }
    }

    struct Signal: OptionSet, Sendable {
        let rawValue: UInt8
        static let output = Signal(rawValue: 1)
        static let diagnostic = Signal(rawValue: 2)
        static let writable = Signal(rawValue: 4)
        static let exited = Signal(rawValue: 8)
        static let kill = Signal(rawValue: 16)
        static let inputClosed = Signal(rawValue: 32)
    }

    final class Signals: Sendable {
        private struct State {
            var identity: ShellProviderIdentity?
            var pending: Signal = []
            var waking = false
            var wake: (@Sendable () -> Void)?
            var captureID: UInt64 = 0
            var captureWakes = ShellCaptureWakeCounters()
        }

        private let state = Mutex(State())

        func captureBegin(_ id: UInt64) {
            state.withLock {
                guard id != 0, $0.captureID != id else { return }
                $0.captureID = id
                $0.captureWakes = ShellCaptureWakeCounters()
            }
        }

        func captureEnd(_ id: UInt64) -> ShellCaptureWakeCounters? {
            state.withLock {
                guard id != 0, $0.captureID == id else { return nil }
                $0.captureID = 0
                return $0.captureWakes
            }
        }

        func attach(_ wake: @escaping @Sendable () -> Void) {
            state.withLock { $0.wake = wake }
        }

        func arm(_ identity: ShellProviderIdentity?) {
            state.withLock {
                $0.identity = identity
                $0.pending = []
            }
        }

        func post(_ signal: Signal, identity: ShellProviderIdentity) {
            let wake = state.withLock { state -> (@Sendable () -> Void)? in
                guard state.identity == identity else { return nil }
                state.pending.formUnion(signal)
                guard !state.waking, let wake = state.wake else { return nil }
                state.waking = true
                if state.captureID != 0 { state.captureWakes.emit() }
                return wake
            }
            wake?()
        }

        func take() -> (ShellProviderIdentity, Signal)? {
            state.withLock {
                if $0.captureID != 0 { $0.captureWakes.consume() }
                guard let identity = $0.identity, !$0.pending.isEmpty else { return nil }
                let pending = $0.pending
                $0.pending = []
                return (identity, pending)
            }
        }

        func finish() {
            let wake = state.withLock { state -> (@Sendable () -> Void)? in
                if !state.pending.isEmpty {
                    if state.captureID != 0, state.wake != nil { state.captureWakes.emit() }
                    return state.wake
                }
                state.waking = false
                return nil
            }
            wake?()
        }
    }

    private struct Spawned {
        let process: Process
        let input: Int32
        let output: Int32
        let diagnostic: Int32
        let cleanupError: String?
    }

    private let queue = DispatchSerialQueue(label: "com.barut.OmniWM.shell.provider", qos: .utility)
    private let signals = Signals()
    private let actions = ShellProviderActions()
    private let inbox: ShellProviderInbox
    private let diagnostics: @Sendable (ShellProviderIdentity, ShellProviderDiagnostics.Line) -> Void
    private let environment: [String: String]
    private var lifecycle: ShellProviderLifecycle
    private var process: Process?
    private var inputFD: Int32?
    private var outputFD: Int32?
    private var diagnosticFD: Int32?
    private var inputSource: (any DispatchSourceWrite)?
    private var outputSource: (any DispatchSourceRead)?
    private var diagnosticSource: (any DispatchSourceRead)?
    private var inputResumed = false
    private var killSource: (any DispatchSourceTimer)?
    private var writer = ShellProviderWriteQueue()
    private var framer = ShellProviderLineFramer()
    private var diagnosticFramer = ShellProviderDiagnostics()
    private var outputFinished = false
    private var diagnosticFinished = false
    private var discardOutput = false
    private var readBuffer = [UInt8](repeating: 0, count: 16_384)
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    init(
        owner: ShellServiceOwner,
        inbox: ShellProviderInbox,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        diagnostics: @escaping @Sendable (ShellProviderIdentity, ShellProviderDiagnostics.Line) -> Void = { _, _ in }
    ) {
        lifecycle = ShellProviderLifecycle(owner: owner)
        self.inbox = inbox
        self.environment = environment
        self.diagnostics = diagnostics
        signals.attach { [weak self] in Task { await self?.consumeSignals() } }
    }

    func reconcile(_ configuration: ShellProviderConfiguration?) {
        perform(lifecycle.reconcile(configuration))
    }

    func captureBegin(_ id: UInt64) {
        framer.captureBegin(id)
        signals.captureBegin(id)
    }

    func captureEnd(_ id: UInt64) -> Capture? {
        guard let framing = framer.captureEnd(id), let wakes = signals.captureEnd(id) else { return nil }
        return Capture(framing: framing, wakes: wakes)
    }

    nonisolated func send(_ id: ShellServiceID, identity: ShellProviderIdentity, frame: Data) {
        guard inbox.isPending(id, identity: identity) else {
            inbox.actionUnsent(ShellResourceLeaseKey(id: id, incarnation: identity.incarnation))
            return
        }
        if let error = actions.append(frame, id: id, identity: identity) {
            inbox.actionUnsent(ShellResourceLeaseKey(id: id, incarnation: identity.incarnation))
            inbox.failAction(id, identity: identity, error: error)
        } else {
            signals.post(.writable, identity: identity)
        }
    }

    nonisolated func cancel(_ id: ShellServiceID, identity: ShellProviderIdentity) {
        inbox.cancel(id)
        if actions.cancel(id, identity: identity) {
            inbox.actionUnsent(ShellResourceLeaseKey(id: id, incarnation: identity.incarnation))
        }
        signals.post(.writable, identity: identity)
    }

    func close() async {
        perform(lifecycle.close())
        guard !lifecycle.isClosed else { return }
        await withCheckedContinuation { closeWaiters.append($0) }
    }

    private func consumeSignals() {
        defer { signals.finish() }
        guard let (identity, pending) = signals.take(), lifecycle.identity == identity else { return }
        if pending.contains(.exited), let process, !process.isRunning {
            perform(lifecycle.exited(identity, code: process.terminationStatus))
        }
        if pending.contains(.inputClosed) { perform(lifecycle.inputClosed(identity)) }
        if pending.contains(.kill) { perform(lifecycle.killDeadline(identity)) }
        if pending.contains(.writable) { flushInput(identity) }
        if pending.contains(.output) || lifecycle.phase == .draining { readOutput(identity) }
        if pending.contains(.diagnostic) || lifecycle.phase == .draining { readDiagnostics(identity) }
        finishDrain(identity)
    }

    private func perform(_ effects: [ShellProviderLifecycle.Effect]) {
        for effect in effects {
            switch effect {
            case let .launch(identity, configuration):
                launch(identity, configuration: configuration)
            case let .running(identity):
                inbox.running(identity)
            case let .closeInput(identity):
                guard lifecycle.identity == identity else { continue }
                closeInput(identity)
            case let .terminate(identity):
                if lifecycle.identity == identity, let process, process.isRunning { process.terminate() }
            case let .armKill(identity):
                guard lifecycle.identity == identity else { continue }
                killSource?.cancel()
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now() + 2)
                let signals = signals
                source.setEventHandler { signals.post(.kill, identity: identity) }
                killSource = source
                source.resume()
            case let .cancelKill(identity):
                guard lifecycle.identity == identity else { continue }
                killSource?.cancel()
                killSource = nil
            case let .kill(identity):
                guard lifecycle.identity == identity, let process, process.isRunning else { continue }
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                killSource?.cancel()
                killSource = nil
            case let .ended(identity, status):
                inbox.end(identity, status: status)
            }
        }
        if lifecycle.isClosed {
            let waiters = closeWaiters
            closeWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    private func launch(_ identity: ShellProviderIdentity, configuration: ShellProviderConfiguration) {
        signals.arm(identity)
        actions.activate(identity)
        guard inbox.activate(identity, configuration: configuration) else {
            actions.stop(identity)
            perform(lifecycle.launchFailed(identity, message: "Provider owner is no longer available"))
            inbox.incarnationDrained(identity)
            return
        }
        writer.removeAll()
        framer.reset()
        diagnosticFramer = ShellProviderDiagnostics()
        outputFinished = false
        diagnosticFinished = false
        discardOutput = false
        do {
            let spawned = try spawn(identity, configuration: configuration)
            process = spawned.process
            inputFD = spawned.input
            outputFD = spawned.output
            diagnosticFD = spawned.diagnostic
            let signals = signals
            let inputDescriptor = spawned.input
            let input = DispatchSource.makeWriteSource(fileDescriptor: spawned.input, queue: queue)
            input.setEventHandler { signals.post(.writable, identity: identity) }
            input.setCancelHandler {
                _ = Darwin.close(inputDescriptor)
                signals.post(.inputClosed, identity: identity)
            }
            inputSource = input
            inputResumed = false
            outputSource = readSource(fd: spawned.output, identity: identity, signal: .output)
            diagnosticSource = readSource(fd: spawned.diagnostic, identity: identity, signal: .diagnostic)
            if let cleanupError = spawned.cleanupError {
                fail(identity, message: cleanupError)
            } else {
                perform(lifecycle.launched(identity))
            }
        } catch {
            actions.stop(identity)
            perform(lifecycle.launchFailed(identity, message: error.localizedDescription))
            inbox.incarnationDrained(identity)
        }
    }

    private func spawn(_ identity: ShellProviderIdentity, configuration: ShellProviderConfiguration) throws -> Spawned {
        guard configuration.authorized
        else { throw failure("Provider execution is not enabled in the user configuration") }
        guard let executable = configuration.command.first, !executable.isEmpty,
              !executable.hasPrefix("/"), !executable.hasPrefix("~"), !executable.contains("\0"),
              !executable.split(separator: "/", omittingEmptySubsequences: false)
              .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              configuration.command.allSatisfy({ !$0.contains("\0") }),
              configuration.options.count <= 256 * 1024,
              let options = String(data: configuration.options, encoding: .utf8)
        else { throw failure("Invalid provider declaration or options") }
        let folder = configuration.folder.resolvingSymlinksInPath().standardizedFileURL
        let url = folder.appendingPathComponent(executable).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(folder.path + "/"), FileManager.default.isExecutableFile(atPath: url.path) else {
            throw failure("Provider executable must be an executable file inside its component folder")
        }
        let input = Pipe()
        let output = Pipe()
        let diagnostic = Pipe()
        let inputFD = try duplicate(input.fileHandleForWriting.fileDescriptor, write: true)
        var outputFD: Int32 = -1
        var diagnosticFD: Int32 = -1
        do {
            outputFD = try duplicate(output.fileHandleForReading.fileDescriptor, write: false)
            diagnosticFD = try duplicate(diagnostic.fileHandleForReading.fileDescriptor, write: false)
            var environment = environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" +
                (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            environment["OMNIWM_PROVIDER_PROTOCOL"] = "1"
            environment["OMNIWM_WIDGET"] = configuration.widget
            environment["OMNIWM_WIDGET_DIR"] = folder.path
            environment["OMNIWM_INSTANCE"] = configuration.instance
            environment["OMNIWM_PROVIDER_OPTIONS"] = options
            let process = Process()
            process.executableURL = url
            process.arguments = Array(configuration.command.dropFirst())
            process.currentDirectoryURL = folder
            process.environment = environment
            process.standardInput = input
            process.standardOutput = output
            process.standardError = diagnostic
            let signals = signals
            process.terminationHandler = { _ in signals.post(.exited, identity: identity) }
            try process.run()
            var cleanupError: String?
            for handle in [input.fileHandleForWriting, output.fileHandleForReading, diagnostic.fileHandleForReading] {
                do { try handle.close() }
                catch {
                    if cleanupError == nil {
                        cleanupError = "Could not close original provider pipe: \(error.localizedDescription)"
                    }
                }
            }
            return Spawned(
                process: process,
                input: inputFD,
                output: outputFD,
                diagnostic: diagnosticFD,
                cleanupError: cleanupError
            )
        } catch {
            _ = Darwin.close(inputFD)
            if outputFD >= 0 { _ = Darwin.close(outputFD) }
            if diagnosticFD >= 0 { _ = Darwin.close(diagnosticFD) }
            throw error
        }
    }

    private func duplicate(_ fd: Int32, write: Bool) throws -> Int32 {
        let copy = Darwin.dup(fd)
        guard copy >= 0 else { throw failure("Could not duplicate provider pipe: \(errno)") }
        let flags = fcntl(copy, F_GETFL)
        guard flags >= 0, fcntl(copy, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(copy, F_SETFD, FD_CLOEXEC) == 0,
              !write || fcntl(copy, F_SETNOSIGPIPE, 1) == 0
        else {
            let code = errno
            _ = Darwin.close(copy)
            throw failure("Could not configure nonblocking provider pipe: \(code)")
        }
        return copy
    }

    private func readSource(fd: Int32, identity: ShellProviderIdentity, signal: Signal) -> any DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let signals = signals
        source.setEventHandler { signals.post(signal, identity: identity) }
        source.setCancelHandler { _ = Darwin.close(fd) }
        source.resume()
        return source
    }

    private func flushInput(_ identity: ShellProviderIdentity) {
        guard lifecycle.identity == identity, let fd = inputFD, lifecycle.acceptsActions else { return }
        let discarded = writer.discardUnsent(where: { !inbox.isPending($0, identity: identity) }, onDiscard: {
            inbox.actionUnsent(ShellResourceLeaseKey(id: $0, incarnation: identity.incarnation))
        })
        actions.consumed(discarded, identity: identity)
        for action in actions.takeBatch() {
            guard inbox.isPending(action.id, identity: identity) else {
                actions.consumed(action.frame.count, identity: identity)
                inbox.actionUnsent(ShellResourceLeaseKey(id: action.id, incarnation: identity.incarnation))
                continue
            }
            do { try writer.append(action.frame, id: action.id) }
            catch {
                actions.consumed(action.frame.count, identity: identity)
                inbox.actionUnsent(ShellResourceLeaseKey(id: action.id, incarnation: identity.incarnation))
                inbox.failAction(action.id, identity: identity, error: error.localizedDescription)
            }
        }
        let before = writer.pendingBytes
        let progress = writer.drain { bytes in
            let count = Darwin.write(fd, bytes.baseAddress, bytes.count)
            if count > 0 { return .written(count) }
            if count < 0, errno == EINTR { return .interrupted }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return .wouldBlock }
            return .failed("Provider stdin write failed: \(errno)")
        }
        actions.consumed(before - writer.pendingBytes, identity: identity)
        switch progress {
        case .empty:
            suspendInput()
            if actions.hasPending { signals.post(.writable, identity: identity) }
        case .blocked:
            if !inputResumed { inputSource?.resume()
                inputResumed = inputSource != nil
            }
        case .yielded:
            signals.post(.writable, identity: identity)
        case let .failed(error):
            fail(identity, message: error)
        }
    }

    private func suspendInput() {
        if inputResumed { inputSource?.suspend()
            inputResumed = false
        }
    }

    private func closeInput(_ identity: ShellProviderIdentity) {
        inbox.stopAccepting(identity)
        for id in actions.stop(identity) { inbox.actionUnsent(ShellResourceLeaseKey(
            id: id,
            incarnation: identity.incarnation
        )) }
        _ = writer.discardUnsent(where: { _ in true }, onDiscard: {
            inbox.actionUnsent(ShellResourceLeaseKey(id: $0, incarnation: identity.incarnation))
        })
        inputFD = nil
        if let inputSource {
            inputSource.cancel()
            if !inputResumed { inputSource.resume() }
        } else {
            signals.post(.inputClosed, identity: identity)
        }
        inputSource = nil
        inputResumed = false
        writer.removeAll()
    }

    private func readOutput(_ identity: ShellProviderIdentity) {
        guard lifecycle.identity == identity, let fd = outputFD, !outputFinished else { return }
        let outcome = read(fd: fd) { [inbox] bytes in
            guard !discardOutput else { return }
            do {
                try framer.consume(bytes) { message in
                    if case let .failed(message) = inbox.post(message, from: identity) { throw failure(message) }
                }
            } catch { fail(identity, message: error.localizedDescription) }
        }
        switch outcome {
        case .more:
            signals.post(.output, identity: identity)
        case .blocked:
            if lifecycle.phase == .draining { finishOutput(identity) }
        case .end:
            finishOutput(identity)
            perform(lifecycle.outputClosed(identity))
        case let .failed(message):
            fail(identity, message: message)
            finishOutput(identity)
        }
    }

    private func finishOutput(_ identity: ShellProviderIdentity) {
        guard !outputFinished else { return }
        outputFinished = true
        if !discardOutput {
            do { try framer.finish() }
            catch { fail(identity, message: error.localizedDescription) }
        }
        outputFD = nil
        outputSource?.cancel()
        outputSource = nil
    }

    private func readDiagnostics(_ identity: ShellProviderIdentity) {
        guard lifecycle.identity == identity, let fd = diagnosticFD, !diagnosticFinished else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let report = diagnostics
        let outcome = read(fd: fd) { bytes in
            diagnosticFramer.consume(bytes, now: now) { report(identity, $0) }
        }
        switch outcome {
        case .more:
            signals.post(.diagnostic, identity: identity)
        case .blocked where lifecycle.phase != .draining:
            break
        case let .failed(message):
            fail(identity, message: message)
            finishDiagnostics(identity, now: now)
        case .blocked,
             .end:
            finishDiagnostics(identity, now: now)
        }
    }

    private func finishDiagnostics(_ identity: ShellProviderIdentity, now: UInt64) {
        guard !diagnosticFinished else { return }
        let report = diagnostics
        diagnosticFinished = true
        diagnosticFramer.finish(now: now) { report(identity, $0) }
        diagnosticFD = nil
        diagnosticSource?.cancel()
        diagnosticSource = nil
    }

    private enum ReadProgress {
        case more
        case blocked
        case end
        case failed(String)
    }

    private func read(fd: Int32, receive: (UnsafeRawBufferPointer) -> Void) -> ReadProgress {
        var remaining = 65_536
        var attempts = 32
        while remaining > 0, attempts > 0 {
            attempts -= 1
            let count = readBuffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, min(remaining, $0.count)) }
            if count > 0 {
                readBuffer.withUnsafeBytes { receive(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
                remaining -= count
            } else if count == 0 { return .end }
            else if errno == EINTR { continue }
            else if errno == EAGAIN || errno == EWOULDBLOCK { return .blocked }
            else { return .failed("Provider pipe read failed: \(errno)") }
        }
        return .more
    }

    private func fail(_ identity: ShellProviderIdentity, message: String) {
        discardOutput = true
        perform(lifecycle.failed(identity, message: message))
    }

    private func finishDrain(_ identity: ShellProviderIdentity) {
        guard lifecycle.identity == identity, lifecycle.phase == .draining, outputFinished,
              diagnosticFinished else { return }
        outputSource?.cancel()
        diagnosticSource?.cancel()
        outputSource = nil
        diagnosticSource = nil
        process = nil
        signals.arm(nil)
        inbox.incarnationDrained(identity)
        perform(lifecycle.drained(identity))
    }

    private func failure(_ message: String) -> ShellProviderProtocol.Failure {
        ShellProviderProtocol.Failure(message: message)
    }
}
