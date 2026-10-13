// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import SwiftUI

struct ShellSettingsSection: View {
    private static let documentation = URL(string: "https://omniwm.app/features/luau-shell/")

    let shellDirectory: URL
    @State private var profiles: [String] = []
    @State private var profile = ShellDefaults.profile
    @State private var themes: [String] = []
    @State private var theme = "native"
    @State private var scheme = ShellWallpaperScheme.tonalSpot
    @State private var customizable: [String] = []

    var body: some View {
        Section {
            Picker("Profile", selection: $profile) {
                ForEach(profiles, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: profile) { _, name in
                do {
                    if try ShellProfiles.select(name, in: shellDirectory) {
                        NotificationCenter.default.post(name: .shellConfigDidChange, object: nil)
                    }
                } catch {
                    Log.shell.error("Failed to select shell profile \(name): \(error.localizedDescription)")
                }
                reload()
            }
            Picker("Theme", selection: $theme) {
                ForEach(themes, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: theme) { _, name in
                do {
                    _ = try ShellProfiles.selectTheme(name, in: shellDirectory)
                } catch {
                    Log.shell.error("Failed to select shell theme \(name): \(error.localizedDescription)")
                }
            }
            if theme == ShellWallpaperPalette.themeName {
                Picker("Scheme", selection: $scheme) {
                    ForEach(ShellWallpaperScheme.allCases, id: \.self) { Text(Self.title(of: $0)).tag($0) }
                }
                .onChange(of: scheme) { _, value in
                    do {
                        _ = try ShellProfiles.selectScheme(value, in: shellDirectory)
                    } catch {
                        Log.shell
                            .error("Failed to select wallpaper scheme \(value.rawValue): \(error.localizedDescription)")
                    }
                }
            }
            HStack {
                Button("Open Shell Folder…") {
                    ShellProfiles.openFolder(shellDirectory)
                }
                Menu("Customize Widget") {
                    ForEach(customizable, id: \.self) { name in
                        Button(name) { customize(name) }
                    }
                }
                .fixedSize()
                .disabled(customizable.isEmpty)
                Spacer()
                if let documentation = Self.documentation {
                    Link("Shell Documentation", destination: documentation)
                }
            }
        } header: {
            Text("Shell")
        } footer: {
            Text(
                "Customize widgets in the selected profile. Updates back up edits to bundled profiles; your own profiles are left alone."
            )
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .shellConfigDidChange)) { _ in
            reload()
        }
    }

    private func reload() {
        profiles = ShellProfiles.names(in: shellDirectory)
        let config = ShellConfig.resolve(shellDirectory: shellDirectory)
        profile = config.profile
        themes = ShellProfiles.themes(of: config)
        theme = config.themeName
        scheme = config.wallpaperScheme
        customizable = config.leading + config.center + config.trailing
    }

    private static func title(of scheme: ShellWallpaperScheme) -> LocalizedStringKey {
        switch scheme {
        case .tonalSpot: "Tonal Spot"
        case .content: "Content"
        case .vibrant: "Vibrant"
        case .expressive: "Expressive"
        case .fidelity: "Fidelity"
        case .fruitSalad: "Fruit Salad"
        case .rainbow: "Rainbow"
        case .neutral: "Neutral"
        case .monochrome: "Monochrome"
        }
    }

    private func customize(_ widget: String) {
        let config = ShellConfig.resolve(shellDirectory: shellDirectory)
        do {
            let target = try ShellProfiles.eject(widget, config: config, shellDirectory: shellDirectory)
                ?? shellDirectory.appendingPathComponent("\(config.profile)/widgets/\(widget)", isDirectory: true)
            NSWorkspace.shared.activateFileViewerSelecting([target.appendingPathComponent("init.luau")])
        } catch {
            Log.shell.error("Failed to customize widget \(widget): \(error.localizedDescription)")
        }
        reload()
    }
}
