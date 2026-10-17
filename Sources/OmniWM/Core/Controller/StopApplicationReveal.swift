// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

@MainActor
final class StopApplicationReveal {
    let isHidden: () -> Bool?
    let requestUnhide: () -> Bool
    let observe: (@escaping @MainActor @Sendable () -> Void) -> (() -> Void)
    private var continuation: CheckedContinuation<Bool, Never>?
    private var removeObserver: (() -> Void)?
    private var deadlineTask: Task<Void, Never>?
    private var revealDeadline: TimeInterval = 0

    init(
        isHidden: @escaping () -> Bool?,
        requestUnhide: @escaping () -> Bool,
        observe: @escaping (@escaping @MainActor @Sendable () -> Void) -> (() -> Void)
    ) {
        self.isHidden = isHidden
        self.requestUnhide = requestUnhide
        self.observe = observe
    }

    convenience init(pid: pid_t) {
        let app = NSRunningApplication(processIdentifier: pid)
        self.init(
            isHidden: { guard let app, !app.isTerminated else { return nil }
                return app.isHidden
            },
            requestUnhide: { app?.unhide() == true },
            observe: { changed in
                let center = NSWorkspace.shared.notificationCenter
                let observer = center.addObserver(
                    forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main
                ) { notification in
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.processIdentifier == pid
                    else { return }
                    Task { @MainActor in changed() }
                }
                return { center.removeObserver(observer) }
            }
        )
    }

    func reveal(deadline: TimeInterval) async -> Bool {
        revealDeadline = deadline
        guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return false }
        guard let hidden = isHidden() else { return false }
        if !hidden { return true }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                removeObserver = observe { [weak self] in self?.visibilityChanged() }
                let sent = requestUnhide()
                if isHidden() == false { finish(true) }
                else if !sent { finish(false) }
                else { startDeadline(deadline) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(false) }
        }
    }

    func visibilityChanged() {
        guard let hidden = isHidden() else { finish(false)
            return
        }
        if !hidden { finish(true) }
    }

    private func startDeadline(_ deadline: TimeInterval) {
        deadlineTask = Task {
            do { try await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime))) }
            catch { return }
            finish(false)
        }
    }

    private func finish(_ revealed: Bool) {
        removeObserver?()
        removeObserver = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: revealed && ProcessInfo.processInfo.systemUptime < revealDeadline)
    }
}
