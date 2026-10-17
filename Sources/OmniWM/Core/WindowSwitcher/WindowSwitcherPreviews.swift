// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@MainActor
struct WindowSwitcherPreviews {
    private var frames: [WindowHandle: OverviewPreviewFrame] = [:]

    func isReady(for handles: [WindowHandle]) -> Bool {
        handles.allSatisfy { frames[$0] != nil }
    }

    mutating func preview(for handle: WindowHandle, candidate: OverviewPreviewFrame?) -> OverviewPreviewFrame? {
        if let frame = frames[handle] { return frame }
        frames[handle] = candidate
        return candidate
    }

    mutating func removeAll() {
        frames.removeAll()
    }
}
