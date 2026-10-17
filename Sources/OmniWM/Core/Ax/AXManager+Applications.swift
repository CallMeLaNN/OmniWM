// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

extension AXManager {
    private static let systemUIBundleIds: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight"
    ]

    func windowsForApp(_ app: NSRunningApplication) async -> [AXWindowRef] {
        let pid = app.processIdentifier
        guard Self.shouldTrack(app, pid: pid) else { return [] }
        var callbackGeneration: UInt64?
        do {
            guard let context = try await AppAXContextRegistry.getOrCreate(app, pid: pid) else {
                WindowAdmissionTrace.record(
                    .init(
                        action: .enumerationFailed,
                        pid: pid,
                        bundleId: app.bundleIdentifier,
                        reason: "context_unavailable"
                    )
                )
                return []
            }
            callbackGeneration = context.callbackGeneration
            let windows = try await context.getWindowsAsync(timeoutSeconds: Self.perAppTimeout)
            return windows.map(\.axRef)
        } catch {
            WindowAdmissionTrace.record(
                .init(
                    action: .enumerationFailed,
                    pid: pid,
                    bundleId: app.bundleIdentifier,
                    reason: String(describing: error),
                    callbackGeneration: callbackGeneration
                )
            )
        }
        return []
    }

    func ensureContext(for app: NSRunningApplication, pid: pid_t) async -> Bool {
        guard Self.shouldTrack(app, pid: pid) else { return false }
        return (try? await AppAXContextRegistry.getOrCreate(app, pid: pid)) != nil
    }

    func requestPermission() -> Bool {
        if AccessibilityPermissionMonitor.shared.isGranted { return true }

        let options: NSDictionary = [axTrustedCheckOptionPrompt as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)

        return AccessibilityPermissionMonitor.shared.isGranted
    }

    static func shouldTrack(_ app: NSRunningApplication, pid: pid_t) -> Bool {
        guard !app.isTerminated, app.activationPolicy != .prohibited else { return false }
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return false }

        if let bundleId = app.bundleIdentifier, Self.systemUIBundleIds.contains(bundleId) {
            return false
        }

        return true
    }

    func hasContext(for pid: pid_t) -> Bool {
        AppAXContextRegistry.contexts[pid] != nil
    }
}
