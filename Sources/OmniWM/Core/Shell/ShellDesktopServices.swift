// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation

@MainActor
final class ShellDesktopServices {
    @MainActor
    private final class Operation {
        let request: ShellDesktopRequest
        let ledger: ShellServiceLedger
        let bridge: ShellDesktopResourceBridge
        let fence: ShellResourceOperation
        var cancelPresentation: ShellDesktopPlatform.CancelPresentation?
        var pin: ShellResourceStore.Pin?
        var finishing = false

        init(
            request: ShellDesktopRequest,
            ledger: ShellServiceLedger,
            bridge: ShellDesktopResourceBridge,
            fence: ShellResourceOperation
        ) {
            self.request = request
            self.ledger = ledger
            self.bridge = bridge
            self.fence = fence
        }
    }

    private let resources: ShellResourceStore
    private let platform: ShellDesktopPlatform
    private var operations: [ShellServiceID: Operation] = [:]
    private var picker: ShellServiceID?
    private var preview: ShellServiceID?

    init(resources: ShellResourceStore, platform: ShellDesktopPlatform = .appKit) {
        self.resources = resources
        self.platform = platform
    }

    @discardableResult
    func perform(
        _ request: ShellDesktopRequest,
        ledger: ShellServiceLedger,
        bridge: ShellDesktopResourceBridge,
        source: ShellDesktopSource? = nil,
        anchor: ShellDesktopAnchor? = nil,
        resolveAnchor: (@MainActor () async throws -> ShellDesktopAnchor)? = nil,
        registered: Bool = false
    ) -> Bool {
        let fence = ShellResourceOperation()
        let cancel: @Sendable () -> Void = { [weak self] in
            fence.cancel()
            Task { @MainActor in self?.cancel(request.id) }
        }
        let discard: @Sendable (ShellServiceCompletion) -> Void = { [resources] completion in
            guard let ids = completion.desktopResources, !ids.isEmpty else { return }
            Task { await bridge.release(ids, owner: completion.id.owner, store: resources) }
        }
        let accepted = registered
            ? ledger.adopt(request.id, cancel: cancel, discard: discard)
            : ledger.register(request.id, cancel: cancel, discard: discard)
        guard accepted else { return false }
        var ownerCount = 0
        var generationCount = 0
        for id in operations.keys where id.owner.generation == request.id.owner.generation {
            generationCount += 1
            if id.owner == request.id.owner { ownerCount += 1 }
        }
        guard ownerCount < 32, generationCount < 256 else {
            ledger.complete(ShellServiceCompletion(
                id: request.id,
                payload: ShellDesktopResult(error: "desktop_busy").payload
            ))
            return true
        }
        let operation = Operation(request: request, ledger: ledger, bridge: bridge, fence: fence)
        operations[request.id] = operation
        guard current(operation) else {
            finish(operation, result: ShellDesktopResult(error: "cancelled"))
            return true
        }
        switch request.action {
        case let .pick(multiple):
            guard picker == nil else {
                finish(operation, result: ShellDesktopResult(error: "picker_busy"))
                return true
            }
            guard let source, source.isCurrent() else {
                finish(operation, result: ShellDesktopResult(error: "source_surface_unavailable"))
                return true
            }
            picker = request.id
            do {
                let cancel = try platform.pick(multiple, source) { [self] result in
                    picked(operation, result: result)
                }
                if picker == request.id {
                    operation.cancelPresentation = cancel
                    if !fence.isActive { cancel() }
                }
            } catch {
                picker = nil
                finish(operation, result: ShellDesktopResult(error: String(describing: error)))
            }
        case let .openURL(url):
            if let error = Self.urlError(url) { finish(operation, result: ShellDesktopResult(error: error)) }
            else { open(url, operation: operation) }
        case let .clipboardText(text):
            let copied = text.utf8.count <= 1 << 20 && platform.clipboardCopy(.text(text))
            finish(operation, result: ShellDesktopResult(error: copied ? nil : "clipboard_copy_failed"))
        case let .clipboardCopy(resource):
            Task { [self] in
                do {
                    let content = try await resources.clipboardContent(
                        resource,
                        owner: request.id.owner,
                        operation: fence
                    )
                    guard current(operation) else { throw ShellResourceFailure("cancelled") }
                    finish(
                        operation,
                        result: ShellDesktopResult(error: platform
                            .clipboardCopy(content) ? nil : "clipboard_copy_failed")
                    )
                } catch { finish(operation, result: ShellDesktopResult(error: String(describing: error))) }
            }
        case .clipboardRead:
            do { readClipboard(try platform.clipboardRead(), operation: operation) }
            catch { finish(operation, result: ShellDesktopResult(error: String(describing: error))) }
        case let .quicklook(ids, index):
            guard preview == nil else {
                finish(operation, result: ShellDesktopResult(error: "quicklook_busy"))
                return true
            }
            guard !ids.isEmpty, ids.count <= 32, index > 0, index <= ids.count else {
                finish(operation, result: ShellDesktopResult(error: "invalid_preview"))
                return true
            }
            preview = request.id
            present(operation, ids: ids, source: source, anchor: nil, resolveAnchor: nil)
        case let .share(ids, service):
            guard !ids.isEmpty, ids.count <= 32, service == nil || service == "airdrop" else {
                finish(operation, result: ShellDesktopResult(error: "unsupported_service"))
                return true
            }
            present(operation, ids: ids, source: source, anchor: anchor, resolveAnchor: resolveAnchor)
        case let .open(resource),
             let .reveal(resource):
            Task { [self] in
                do {
                    operation.pin = try await resources.retain([resource], owner: request.id.owner)
                    guard current(operation), let value = operation.pin?.values.first else {
                        finish(operation, result: ShellDesktopResult(error: "cancelled"))
                        return
                    }
                    switch (request.action, value) {
                    case let (.reveal, .file(url)):
                        finish(
                            operation,
                            result: ShellDesktopResult(error: platform.reveal(url) ? nil : "reveal_failed")
                        )
                    case let (.open, .file(url)):
                        open(url, operation: operation)
                    case let (.open, .url(url)):
                        if let error = Self
                            .urlError(url) { finish(operation, result: ShellDesktopResult(error: error)) }
                        else { open(url, operation: operation) }
                    default:
                        finish(operation, result: ShellDesktopResult(error: "unsupported_resource"))
                    }
                } catch {
                    finish(operation, result: ShellDesktopResult(error: String(describing: error)))
                }
            }
        }
        return true
    }

    private func present(
        _ operation: Operation,
        ids: [ShellResourceID],
        source: ShellDesktopSource?,
        anchor: ShellDesktopAnchor?,
        resolveAnchor: (@MainActor () async throws -> ShellDesktopAnchor)?
    ) {
        guard let source, source.isCurrent() else {
            finish(operation, result: ShellDesktopResult(error: "source_surface_unavailable"))
            return
        }
        Task { [self] in
            do {
                operation.pin = try await resources.retain(ids, owner: operation.request.id.owner)
                guard current(operation), source.isCurrent(), let pin = operation.pin else {
                    finish(operation, result: ShellDesktopResult(error: "cancelled"))
                    return
                }
                let completion: ShellDesktopPlatform.PresentationCompletion = { [self] error in
                    finish(operation, result: ShellDesktopResult(error: error))
                }
                let presentation: ShellDesktopPlatform.Presentation
                switch operation.request.action {
                case let .quicklook(_, index):
                    let urls = try pin.values.map { value -> URL in
                        guard case let .file(url) = value else { throw ShellResourceFailure("unsupported_resource") }
                        return url
                    }
                    presentation = try platform.quicklook(urls, index, source, completion)
                case let .share(_, service):
                    let resolved = try await resolveAnchor?() ?? anchor
                    guard current(operation), source.isCurrent(), let resolved, resolved.isCurrent() else {
                        throw ShellResourceFailure("anchor_unavailable")
                    }
                    presentation = try platform.share(pin.values, service, source, resolved, completion)
                default:
                    throw ShellResourceFailure("invalid_desktop_operation")
                }
                if operations[operation.request.id] === operation, !operation.finishing {
                    operation.cancelPresentation = presentation.cancel
                    guard current(operation), source.isCurrent() else {
                        finish(operation, result: ShellDesktopResult(error: "cancelled"))
                        return
                    }
                    try presentation.start()
                    if !operation.fence.isActive { presentation.cancel() }
                }
            } catch {
                finish(operation, result: ShellDesktopResult(error: String(describing: error)))
            }
        }
    }

    private func picked(_ operation: Operation, result: Result<[URL], ShellResourceFailure>) {
        let id = operation.request.id
        guard operations[id] === operation, picker == id else { return }
        picker = nil
        operation.cancelPresentation = nil
        guard current(operation) else {
            finish(operation, result: ShellDesktopResult(error: "cancelled"))
            return
        }
        switch result {
        case let .failure(error):
            finish(operation, result: ShellDesktopResult(error: error.description))
        case let .success(urls):
            Task { [self] in
                var selection: ShellResourceStore.Selection?
                var ids: [ShellResourceID] = []
                do {
                    let prepared = try await resources.prepareSelection(
                        urls,
                        owner: id.owner,
                        operation: operation.fence
                    )
                    selection = prepared
                    guard current(operation) else { throw ShellResourceFailure("cancelled") }
                    ids = try await operation.bridge.admit(id, prepared.items)
                    guard current(operation) else { throw ShellResourceFailure("cancelled") }
                    try await resources.installSelection(
                        prepared,
                        ids: ids,
                        owner: id.owner,
                        operation: operation.fence
                    )
                    selection = nil
                    if !finish(operation, result: ShellDesktopResult(resources: ids)) {
                        await operation.bridge.release(ids, owner: id.owner, store: resources)
                    }
                } catch {
                    if let selection { await resources.discardSelection(selection) }
                    if !ids.isEmpty { await operation.bridge.release(ids, owner: id.owner, store: resources) }
                    finish(operation, result: ShellDesktopResult(error: String(describing: error)))
                }
            }
        }
    }

    private func readClipboard(_ items: [ShellDropItem], operation: Operation) {
        guard !items.isEmpty else {
            finish(operation, result: ShellDesktopResult(resources: []))
            return
        }
        Task { [self] in
            let id = operation.request.id
            var ids: [ShellResourceID] = []
            do {
                guard items.count <= ShellResourceStore.attachmentLimit,
                      current(operation) else { throw ShellResourceFailure("clipboard_unavailable") }
                ids = try await operation.bridge.admit(
                    id,
                    items.map { ShellPickedResource(name: $0.name, kind: $0.kind, uti: $0.uti) }
                )
                guard current(operation) else { throw ShellResourceFailure("cancelled") }
                try await resources.materialize(items.map(\.source), ids: ids, owner: id.owner)
                if !finish(operation, result: ShellDesktopResult(resources: ids)) {
                    await operation.bridge.release(ids, owner: id.owner, store: resources)
                }
            } catch {
                if !ids.isEmpty { await operation.bridge.release(ids, owner: id.owner, store: resources) }
                finish(operation, result: ShellDesktopResult(error: String(describing: error)))
            }
        }
    }

    private func open(_ url: URL, operation: Operation) {
        guard current(operation) else {
            finish(operation, result: ShellDesktopResult(error: "cancelled"))
            return
        }
        platform.open(url) { [self] error in
            Task { @MainActor in finish(operation, result: ShellDesktopResult(error: error)) }
        }
    }

    private func cancel(_ id: ShellServiceID) {
        operations[id]?.cancelPresentation?()
    }

    private func current(_ operation: Operation) -> Bool {
        operations[operation.request.id] === operation && operation.fence.isActive && resources.catalog
            .isActive(operation.request.id.owner)
    }

    @discardableResult
    private func finish(_ operation: Operation, result: ShellDesktopResult) -> Bool {
        let id = operation.request.id
        guard operations[id] === operation, !operation.finishing else { return false }
        let deliver = current(operation)
        operation.finishing = true
        operation.cancelPresentation = nil
        if let pin = operation.pin {
            operation.pin = nil
            Task { [self] in
                await resources.release(pin)
                retire(operation)
                if operation.fence.isActive {
                    let completion = deliver ? result : ShellDesktopResult(error: "cancelled")
                    operation.ledger.complete(ShellServiceCompletion(id: id, payload: completion.payload))
                }
            }
            return false
        }
        retire(operation)
        guard deliver else {
            if operation.fence.isActive {
                operation.ledger.complete(ShellServiceCompletion(
                    id: id,
                    payload: ShellDesktopResult(error: "cancelled").payload
                ))
            }
            return false
        }
        return operation.ledger.complete(ShellServiceCompletion(
            id: id,
            payload: result.payload,
            desktopResources: result.resources
        ))
    }

    private func retire(_ operation: Operation) {
        let id = operation.request.id
        guard operations[id] === operation else { return }
        operations.removeValue(forKey: id)
        if preview == id { preview = nil }
    }

    private static func urlError(_ url: URL) -> String? {
        if url.isFileURL { return "file_url_requires_resource" }
        guard let scheme = url.scheme, !scheme.isEmpty else { return "invalid_url" }
        return nil
    }
}
