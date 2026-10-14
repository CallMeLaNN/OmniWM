// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import SwiftUI

struct ShellSettingsPreview: View {
    enum Surface: Equatable, Sendable {
        case bar
        case island(expanded: Bool)
    }

    struct Request: Equatable {
        let config: ShellConfig
        let surface: Surface
        let style: ShellBarStyle
        let scale: CGFloat
        let dark: Bool
        let fullWidth: Bool
        let revision: UInt64
    }

    let config: ShellConfig
    var surface = Surface.bar
    var style = ShellBarStyle()
    var fullWidth: Bool?
    var revision: UInt64 = 0
    var onRendered: ((CGImage) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var failure: String?

    private var request: Request {
        Request(
            config: config,
            surface: surface,
            style: style,
            scale: displayScale,
            dark: colorScheme == .dark,
            fullWidth: fullWidth ?? config.barOverride?.settings.fullWidth ?? false,
            revision: revision
        )
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            } else if let failure {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .task(id: request) {
            let value = request
            image = nil
            failure = nil
            do {
                let rendered = try await ShellSettingsPreviewCache.shared.image(for: value)
                try Task.checkCancellation()
                image = rendered
                onRendered?(rendered)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                failure = (error as? ShellScriptFailure)?.message ?? error.localizedDescription
            }
        }
    }

    @MainActor
    static func style(settings: WorkspaceBarSettings, config: ShellConfig, monitor: Monitor? = nil) -> ShellBarStyle {
        let isolated = WorkspaceBarSettings()
        let values = settings.export()
        isolated.applyIdentity(values)
        isolated.applyAppearance(values, monitorOverrides: settings.monitorOverrides)
        isolated.profileOverride = config.barOverride
        let monitor = monitor ?? Monitor(
            id: .init(displayId: 0),
            displayId: 0,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876),
            hasNotch: false,
            name: "Sample display"
        )
        let resolved = isolated.resolved(for: monitor)
        let snapshot = WorkspaceBarSnapshot(
            projection: .init(items: [], scratchpads: []), backgroundOpacity: resolved.backgroundOpacity,
            barHeight: resolved.height
        )
        return ShellBarStyle(resolved, settings: isolated, snapshot: snapshot)
    }

    @MainActor
    static func cachedImage(for request: Request) async throws -> CGImage {
        try await ShellSettingsPreviewCache.shared.image(for: request)
    }

    @MainActor
    static func render(_ request: Request) async throws -> CGImage {
        let config = request.config
        let names: [String]
        let islandSize: CGSize?
        let expanded: Bool?
        switch request.surface {
        case .bar:
            names = config.leading + config.center + config.trailing
            islandSize = nil
            expanded = nil
        case let .island(value):
            guard let island = config.island else {
                throw ShellScriptFailure(kind: .runtime, message: "This style does not include an island.")
            }
            names = [island.root]
            islandSize = island.size
            expanded = value
        }
        var seen: Set<String> = []
        let inputs = try names.filter { seen.insert($0).inserted }.map { name in
            guard let source = config.widget(name) ?? ShellConfig.bundledWidget(name) else {
                throw ShellScriptFailure(kind: .compile, message: "\(ShellBarLayout.title(of: name)) is not installed.")
            }
            return ShellWidgetSourceLoader.Input(
                name: name, shellDirectory: config.directories.first ?? source.deletingLastPathComponent(),
                sourceURL: source, directories: config.directories, profile: config.profile,
                components: islandSize == nil ? nil : config.island?.components
            )
        }
        let trees = try await ShellSettingsPreviewRenderer.shared.render(
            inputs: inputs, values: ShellSettingsPreviewSamples.values(
                style: request.style, islandSize: islandSize, dark: request.dark, scale: request.scale
            ), settings: config.widgetSettings, expanded: expanded
        )
        let images = try await ShellSettingsPreviewRaster.render(
            trees, theme: config.theme, dark: request.dark, scale: request.scale, limit: islandSize
        )
        try Task.checkCancellation()
        if let image = images.first, islandSize != nil { return image.image }
        return try await barImage(images, request: request)
    }

    @MainActor
    private static func barImage(
        _ images: [ShellSettingsPreviewRaster.Image],
        request: Request
    ) async throws -> CGImage {
        guard !images.isEmpty else {
            throw ShellScriptFailure(kind: .runtime, message: "Add a widget to preview the bar.")
        }
        let vertical = request.style.vertical
        let sizes = images.map { vertical ? $0.size.height : $0.size.width }
        let natural = sizes.reduce(8, +) + CGFloat(max(0, images.count - 1)) * 8
        let length = request.fullWidth ? max(960, min(natural, 1800)) : min(natural, 1800)
        let thickness = max(
            CGFloat(request.style.height),
            images.map { vertical ? $0.size.width : $0.size.height }.max() ?? 0
        )
        let size = vertical ? CGSize(width: thickness, height: length) : CGSize(width: length, height: thickness)
        let scale = ShellSettingsPreviewResolution.scale(size: size, requested: request.scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: ShellSettingsPreviewResolution.width(size: size, scale: scale),
                  height: ShellSettingsPreviewResolution.height(size: size, scale: scale),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw ShellScriptFailure(kind: .memory, message: "The bar preview image could not be created.") }
        context.scaleBy(x: scale, y: scale)
        let backgroundStyle = WorkspaceBarSnapshot(
            projection: .init(items: [], scratchpads: []), backgroundOpacity: request.style.opacity,
            transparentBackground: request.style.transparent, solidBlackBackground: request.style.solidBlack,
            barHeight: thickness, barFill: request.config.barOverride?.barFill,
            barBorder: request.config.barOverride?.barBorder
        ).backgroundStyle
        let fill: NSColor? = switch backgroundStyle {
        case .transparent: nil
        case .solidBlack: .black
        case .material: (request.dark ? NSColor.white : .black).withAlphaComponent(
                CGFloat(request.style.opacity) * (request.dark ? 1 : 0.5)
            )
        case let .palette(color, _): color.color(dark: request.dark).withAlphaComponent(CGFloat(request.style.opacity))
        }
        if let fill {
            context.setFillColor(fill.cgColor)
            let radius: CGFloat = request.fullWidth || request.style.solidBlack ? 0 : WorkspaceBarGeometry.cornerRadius
            context.addPath(CGPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            ))
            context.fillPath()
        }
        if let shader = request.config.barShader {
            let resources = ShellResources(motion: MotionPolicy(animationsEnabled: false))
            resources.palette.refresh(
                theme: request.config.theme,
                appearance: NSAppearance(named: request.dark ? .darkAqua : .aqua) ?? NSApplication.shared
                    .effectiveAppearance
            )
            let program = resources.shaders.program(source: shader.source, directories: request.config.directories.map {
                $0.appendingPathComponent("shaders", isDirectory: true)
            })
            await ShellSettingsPreviewRaster.wait(for: [program], in: resources.shaders)
            guard let pipeline = program.pipeline else {
                throw ShellScriptFailure(kind: .runtime, message: program.failure ?? "The bar shader is unavailable.")
            }
            let background = try await ShellSettingsPreviewShader.shared.render(
                pipeline: pipeline, input: .init(
                    values: shader.values,
                    rate: 0,
                    colors: resources.palette.shaderColors
                ),
                size: size, scale: scale
            )
            context.draw(background, in: CGRect(origin: .zero, size: size))
        }
        let offsets: [CGFloat]
        if request.fullWidth {
            offsets = WorkspaceBarZoneLayout.offsets(
                of: images.map { (request.config.lane(of: $0.name).lane, vertical ? $0.size.height : $0.size.width) },
                length: length, zones: .init(notch: nil, mode: .moveBelowMenuBar), spacing: 8, inset: 4
            )
        } else {
            var cursor: CGFloat = 4
            offsets = sizes.map { extent in
                defer { cursor += extent + 8 }
                return cursor
            }
        }
        for (index, image) in images.enumerated() {
            context.draw(
                image.image,
                in: vertical
                    ? CGRect(
                        x: (size.width - image.size.width) / 2,
                        y: size.height - offsets[index] - image.size.height,
                        width: image.size.width,
                        height: image.size.height
                    )
                    : CGRect(
                        x: offsets[index],
                        y: (size.height - image.size.height) / 2,
                        width: image.size.width,
                        height: image.size.height
                    )
            )
        }
        guard let image = context.makeImage() else {
            throw ShellScriptFailure(kind: .memory, message: "The bar preview could not be rendered.")
        }
        return image
    }
}

@MainActor
final class ShellSettingsPreviewCache {
    static let shared = ShellSettingsPreviewCache()
    static let maximumBytes = 32 << 20
    private var entries: [(ShellSettingsPreview.Request, CGImage)] = []
    private(set) var retainedBytes = 0
    var count: Int {
        entries.count
    }

    func image(for request: ShellSettingsPreview.Request) async throws -> CGImage {
        if let index = entries.firstIndex(where: { $0.0 == request }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.1
        }
        let image = try await ShellSettingsPreview.render(request)
        try Task.checkCancellation()
        insert(image, for: request)
        return image
    }

    func insert(_ image: CGImage, for request: ShellSettingsPreview.Request) {
        if let index = entries.firstIndex(where: { $0.0 == request }) {
            let removed = entries.remove(at: index).1
            retainedBytes -= removed.bytesPerRow * removed.height
        }
        entries.append((request, image))
        retainedBytes += image.bytesPerRow * image.height
        while entries.count > 12 || retainedBytes > Self.maximumBytes {
            let removed = entries.removeFirst().1
            retainedBytes -= removed.bytesPerRow * removed.height
        }
    }
}
