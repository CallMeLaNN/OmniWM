// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore
import ScreenCaptureKit

@MainActor
final class ResizeOverlayController {
    typealias ImageCapture = @MainActor (WindowToken, CGSize) async -> CGImage?

    private enum Phase {
        case idle
        case tracking
        case settling
    }

    private(set) var workspaceId: WorkspaceDescriptor.ID?
    private(set) var panels: [WindowToken: ResizeOverlayWindow] = [:]
    private(set) var captureTasks: [WindowToken: Task<Void, Never>] = [:]
    private(set) var settlesOnLayout = false
    private var phase = Phase.idle
    private var style = ResizePreviewStyle.live
    private var pointerDriven = false
    private var watchdog: Task<Void, Never>?
    private let surfaceCoordinator: SurfaceCoordinator
    private let previews: PreviewCaptureCoordinator
    private let captureAccessAllowed: @MainActor () -> Bool
    private let captureImage: ImageCapture
    private let currentFrame: @MainActor (WindowToken) -> CGRect?
    private let icon: @MainActor (WindowToken) -> NSImage?
    private let requestRelayout: @MainActor (WorkspaceDescriptor.ID) -> Void

    init(
        surfaceCoordinator: SurfaceCoordinator = .shared,
        previews: PreviewCaptureCoordinator = .shared,
        captureAccessAllowed: @escaping @MainActor () -> Bool = { ScreenCapturePermissionMonitor.shared.isGranted },
        captureImage: ImageCapture? = nil,
        currentFrame: @escaping @MainActor (WindowToken) -> CGRect?,
        icon: @escaping @MainActor (WindowToken) -> NSImage? = { _ in nil },
        requestRelayout: @escaping @MainActor (WorkspaceDescriptor.ID) -> Void = { _ in }
    ) {
        self.surfaceCoordinator = surfaceCoordinator
        self.previews = previews
        self.captureAccessAllowed = captureAccessAllowed
        self.captureImage = captureImage ?? { token, pixelSize in
            await DragGhostController.captureWindowImage(token: token, pixelSize: pixelSize, previews: previews)
        }
        self.currentFrame = currentFrame
        self.icon = icon
        self.requestRelayout = requestRelayout
    }

    var isActive: Bool {
        phase != .idle
    }

    func isTracking(_ workspaceId: WorkspaceDescriptor.ID) -> Bool {
        phase == .tracking && self.workspaceId == workspaceId
    }

    /// Pointer-driven previews hold every plan until `settleOnLayout`; animation-driven ones
    /// also hold, but expire into a relayout if the animation stops without a settling plan.
    func begin(workspaceId: WorkspaceDescriptor.ID, style: ResizePreviewStyle, pointerDriven: Bool) {
        guard style != .live else { return }
        if self.workspaceId != workspaceId || self.style != style {
            reset()
        }
        self.workspaceId = workspaceId
        self.style = style
        self.pointerDriven = pointerDriven
        settlesOnLayout = false
        phase = .tracking
        armWatchdog()
    }

    /// The next non-tick plan for the tracked workspace writes real frames and ends the preview.
    func settleOnLayout(in workspaceId: WorkspaceDescriptor.ID? = nil) {
        guard phase == .tracking, workspaceId == nil || workspaceId == self.workspaceId else { return }
        settlesOnLayout = true
        armWatchdog()
    }

    /// Routes a plan's frame changes to the panels while a preview is tracking
    /// the workspace. Only the settling plan keeps its writes.
    func intercept(_ plan: WorkspaceLayoutPlan) -> WorkspaceLayoutPlan {
        guard isTracking(plan.workspaceId) else { return plan }
        update(plan.diff.frameChanges)
        if settlesOnLayout, !plan.isAnimationTick {
            finish()
            return plan
        }
        var plan = plan
        plan.diff.frameChanges.removeAll()
        return plan
    }

    func update(_ changes: [LayoutFrameChange]) {
        guard phase == .tracking else { return }
        for change in changes {
            if let panel = panels[change.token] {
                panel.updateFrame(change.frame)
            } else if let start = currentFrame(change.token),
                      !start.approximatelyEqual(to: change.frame, tolerance: FrameTolerance.frameWrite),
                      NSScreen.screens.contains(where: { $0.frame.intersects(start.union(change.frame)) })
            {
                addPanel(token: change.token, from: start, to: change.frame)
            }
        }
        armWatchdog()
    }

    func finish() {
        guard phase == .tracking else { return }
        phase = .settling
        for (token, panel) in panels
            where currentFrame(token)?.approximatelyEqual(to: panel.frame, tolerance: FrameTolerance.frameWrite) == true
        {
            retire(token)
        }
        if panels.isEmpty {
            reset()
        } else {
            armWatchdog()
        }
    }

    func frameApplied(windowId: Int) {
        guard phase == .settling, let token = panels.keys.first(where: { $0.windowId == windowId }) else { return }
        retire(token)
        if panels.isEmpty {
            reset()
        }
    }

    func reset() {
        watchdog?.cancel()
        watchdog = nil
        for token in Array(panels.keys) {
            retire(token)
        }
        workspaceId = nil
        settlesOnLayout = false
        phase = .idle
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = nil
        guard phase == .settling || settlesOnLayout || !pointerDriven else { return }
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            if phase == .tracking, let workspaceId {
                settlesOnLayout = true
                requestRelayout(workspaceId)
            } else {
                reset()
            }
        }
    }

    private func addPanel(token: WindowToken, from start: CGRect, to frame: CGRect) {
        let panel = ResizeOverlayWindow(icon: icon(token), frame: start, surfaceCoordinator: surfaceCoordinator)
        panel.updateFrame(frame)
        panels[token] = panel
        guard style == .snapshot, captureAccessAllowed() else {
            panel.orderFront(nil)
            return
        }
        if let shared = previews.sharedPreview(for: token)?.frame {
            panel.setSnapshot(shared.surface, contentsRect: shared.contentsRect, holding: shared)
            panel.orderFront(nil)
        }
        let scale = NSScreen.screen(containing: start)?.backingScaleFactor ?? 2
        let pixelSize = CGSize(width: (start.width * scale).rounded(), height: (start.height * scale).rounded())
        captureTasks[token] = Task { [weak self, captureImage] in
            let image = await captureImage(token, pixelSize)
            guard !Task.isCancelled, let panel = self?.panels[token] else { return }
            if let image {
                panel.setSnapshot(image)
            }
            panel.orderFront(nil)
        }
    }

    private func retire(_ token: WindowToken) {
        captureTasks.removeValue(forKey: token)?.cancel()
        panels.removeValue(forKey: token)?.destroy()
    }
}

@MainActor
final class ResizeOverlayWindow: NSPanel {
    private let glassView = NSGlassEffectView()
    private let iconView = NSImageView()
    private let snapshotView = NSView()
    private let surfaceCoordinator: SurfaceCoordinator
    private var surfaceId: String?
    private var preview: OverviewPreviewFrame?
    private var isDestroyed = false

    var showsSnapshot: Bool {
        !snapshotView.isHidden
    }

    init(icon: NSImage?, frame: CGRect, surfaceCoordinator: SurfaceCoordinator = .shared) {
        self.surfaceCoordinator = surfaceCoordinator

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        configureContentView()
        iconView.image = icon
        updateFrame(frame)

        let surfaceId = "resize-overlay-\(ObjectIdentifier(self).hashValue)"
        self.surfaceId = surfaceId
        surfaceCoordinator.register(
            window: self,
            id: surfaceId,
            policy: SurfacePolicy(
                kind: .dragGhost,
                hitTestPolicy: .passthrough,
                capturePolicy: .excluded,
                suppressesManagedFocusRecovery: false
            )
        )
    }

    isolated deinit {
        destroy()
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    private func configureContentView() {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor

        glassView.style = .regular
        glassView.cornerRadius = 10
        glassView.autoresizingMask = [.width, .height]
        container.addSubview(glassView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        container.addSubview(iconView)

        snapshotView.wantsLayer = true
        snapshotView.layer?.contentsGravity = .resize
        snapshotView.layer?.cornerRadius = 10
        snapshotView.layer?.masksToBounds = true
        snapshotView.autoresizingMask = [.width, .height]
        snapshotView.isHidden = true
        container.addSubview(snapshotView)

        contentView = container
    }

    func setSnapshot(
        _ contents: Any,
        contentsRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        holding retained: OverviewPreviewFrame? = nil
    ) {
        let previous = preview
        preview = retained
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { withExtendedLifetime(previous) {} }
        snapshotView.layer?.contents = contents
        snapshotView.layer?.contentsRect = contentsRect
        snapshotView.isHidden = false
        CATransaction.commit()
    }

    func updateFrame(_ frame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setFrame(frame, display: false)
        contentView?.frame = CGRect(origin: .zero, size: frame.size)
        glassView.frame = CGRect(origin: .zero, size: frame.size)
        snapshotView.frame = CGRect(origin: .zero, size: frame.size)
        let iconSize: CGFloat = min(96, min(frame.width, frame.height) * 0.4)
        iconView.frame = CGRect(
            x: (frame.width - iconSize) / 2,
            y: (frame.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        CATransaction.commit()
    }

    func destroy() {
        guard !isDestroyed else { return }
        isDestroyed = true
        if let surfaceId {
            surfaceCoordinator.unregister(id: surfaceId)
            self.surfaceId = nil
        }
        snapshotView.layer?.contents = nil
        preview = nil
        orderOut(nil)
        close()
    }
}
