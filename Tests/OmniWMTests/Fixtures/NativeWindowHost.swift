// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore

@MainActor
private final class NativeWindowHost {
    private struct Ready: Encodable {
        let pid: Int32
        let windowIds: [UInt32]
    }

    private var windows: [NSPanel] = []

    func publish(to url: URL) throws {
        guard let screen = NSScreen.main else { throw Failure.noScreen }
        for index in 0 ..< 2 {
            let panel = NSPanel(
                contentRect: CGRect(
                    x: screen.visibleFrame.midX + (index == 0 ? -310 : 10),
                    y: screen.visibleFrame.midY - 90,
                    width: 300, height: 180
                ),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.title = "OmniWM native subscription fixture \(index + 1)"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.level = .normal
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            windows.append(panel)
        }
        CATransaction.flush()
        let ids = windows.compactMap { UInt32(exactly: $0.windowNumber) }
        guard ids.count == 2, Set(ids).count == 2, !ids.contains(0) else { throw Failure.noWindows }
        try JSONEncoder().encode(Ready(pid: getpid(), windowIds: ids)).write(to: url, options: .atomic)
        FileHandle.standardInput.readabilityHandler = { [weak self] input in
            guard input.availableData.isEmpty else { return }
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    private func close() {
        FileHandle.standardInput.readabilityHandler = nil
        for window in windows { window.close() }
        NSApplication.shared.terminate(nil)
    }

    private enum Failure: Error { case noScreen, noWindows }
}

@main
private enum NativeWindowHostApp {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)
        let host = NativeWindowHost()
        try host.publish(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        withExtendedLifetime(host) { app.run() }
    }
}
