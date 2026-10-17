// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

@MainActor
final class AXFrameSettlement {
    let tokens: Set<WindowToken>
    var onChange: (() -> Void)?
    private var nextSubmission: UInt64 = 0
    private var pending: Set<UInt64> = []
    private(set) var failed = false
    private(set) var sealed = false

    var isSettled: Bool {
        sealed && pending.isEmpty
    }

    init(tokens: Set<WindowToken>) {
        self.tokens = tokens
    }

    func observe(_ target: AXFrameApplicationTarget) -> AXFrameApplicationTerminalObserver? {
        guard tokens.contains(WindowToken(pid: target.pid, windowId: target.windowId)) else { return nil }
        nextSubmission &+= 1
        let submission = nextSubmission
        pending.insert(submission)
        return { [weak self] result in
            guard let self, pending.remove(submission) != nil else { return }
            if !result.writeResult.isVerifiedSuccess { failed = true }
            onChange?()
        }
    }

    func reject(_ target: AXFrameApplicationTarget) {
        guard tokens.contains(WindowToken(pid: target.pid, windowId: target.windowId)) else { return }
        failed = true
        onChange?()
    }

    func seal() {
        sealed = true
        onChange?()
    }
}
