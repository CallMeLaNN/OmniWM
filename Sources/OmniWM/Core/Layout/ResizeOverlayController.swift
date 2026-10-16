// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import QuartzCore
import ScreenCaptureKit

@MainActor
final class ResizeOverlayController {
    typealias ImageCapture = @MainActor (WindowToken, CGSize) async -> CGImage?

    private(set) var overlayWindow: ResizeOverlayWindow?
    private(set) var captureTask: Task<Void, Never>?
    private(set) var token: WindowToken?
    private(set) var isActive: Bool = false
    private let surfaceCoordinator: SurfaceCoordinator
    private let previews: PreviewCaptureCoordinator
    private let captureAccessAllowed: @MainActor () -> Bool
    private let captureImage: ImageCapture

    init(
        surfaceCoordinator: SurfaceCoordinator = .shared,
        previews: PreviewCaptureCoordinator = .shared,
        captureAccessAllowed: @escaping @MainActor () -> Bool = { ScreenCapturePermissionMonitor.shared.isGranted },
        captureImage: ImageCapture? = nil
    ) {
        self.surfaceCoordinator = surfaceCoordinator
        self.previews = previews
        self.captureAccessAllowed = captureAccessAllowed
        self.captureImage = captureImage ?? { token, pixelSize in
            await DragGhostController.captureWindowImage(token: token, pixelSize: pixelSize, previews: previews)
        }
    }

    isolated deinit {
        destroy()
    }

    func beginResize(
        token: WindowToken,
        initialFrame: CGRect,
        appIcon: NSImage?,
        style: ResizePreviewStyle
    ) {
        guard style != .live else { return }
        isActive = true
        self.token = token
        captureTask?.cancel()

        if overlayWindow == nil {
            overlayWindow = ResizeOverlayWindow(surfaceCoordinator: surfaceCoordinator)
        }
        overlayWindow?.setup(icon: appIcon, frame: initialFrame)
        overlayWindow?.show()

        guard style == .snapshot, captureAccessAllowed() else { return }

        if let shared = previews.sharedPreview(for: token)?.frame {
            overlayWindow?.setSnapshot(shared.surface, contentsRect: shared.contentsRect, holding: shared)
        }

        let scale = NSScreen.screen(containing: initialFrame)?.backingScaleFactor ?? 2
        let pixelSize = CGSize(
            width: (initialFrame.width * scale).rounded(),
            height: (initialFrame.height * scale).rounded()
        )

        captureTask = Task { [weak self, captureImage] in
            guard let image = await captureImage(token, pixelSize) else { return }
            guard let self, isActive, !Task.isCancelled else { return }
            overlayWindow?.setSnapshot(image)
        }
    }

    func updateFrame(_ frame: CGRect) {
        guard isActive else { return }
        overlayWindow?.updateFrame(frame)
    }

    func endResize() {
        isActive = false
        captureTask?.cancel()
        captureTask = nil
        token = nil
        overlayWindow?.hide()
    }

    func destroy() {
        endResize()
        overlayWindow?.destroy()
        overlayWindow = nil
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

    init(surfaceCoordinator: SurfaceCoordinator = .shared) {
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

    func setup(icon: NSImage?, frame: CGRect) {
        iconView.image = icon
        snapshotView.layer?.contents = nil
        snapshotView.isHidden = true
        preview = nil
        updateFrame(frame)
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

    func show() {
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
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
        hide()
        close()
    }
}
