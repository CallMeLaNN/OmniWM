// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import SwiftUI

struct WorkspaceBarWidgetsSection: View {
    let shellDirectory: URL
    let vertical: Bool?

    @State private var layout: ShellBarLayout?
    @State private var problem: String?
    @State private var selection: String?
    @State private var confirmingReset = false

    private static let rowHeight: CGFloat = 24
    private static let captionedRowHeight: CGFloat = 38
    private static let chromeHeight: CGFloat = 85
    private static let symbols: [String: String] = [
        "omniwm": "command",
        "workspaces": "rectangle.split.3x1",
        "scratchpads": "rectangle.stack",
        "system-stats": "cpu",
        "stats": "chart.bar",
        "clock": "clock",
        "battery": "battery.75percent",
        "volume": "speaker.wave.2",
        "media": "music.note",
        "calendar": "calendar",
        "weather": "cloud.sun"
    ]

    var body: some View {
        Section {
            if let layout {
                Text(layout.customized
                    ? String(localized: "Using your layout")
                    : String(localized: "Using the “\(layout.profile)” profile’s layout"))
                    .foregroundStyle(.secondary)
                List(selection: $selection) {
                    ForEach(ShellLane.allCases, id: \.self) { lane in
                        self.lane(lane, of: layout)
                    }
                }
                .listStyle(.bordered)
                .frame(height: height(of: layout))
                controls(layout)
            } else if let problem {
                Text("Fix shell.toml to edit the bar widgets: \(problem)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Bar Widgets")
        } footer: {
            Text("Drag widgets to reorder them. Changes are saved to shell.toml in your shell folder.")
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .shellConfigDidChange)) { _ in
            reload()
        }
        .confirmationDialog(
            String(localized: "Use the “\(layout?.profile ?? ShellDefaults.profile)” profile’s widget layout?"),
            isPresented: $confirmingReset
        ) {
            Button("Use Profile Layout", role: .destructive, action: reset)
        }
    }

    private func lane(_ lane: ShellLane, of layout: ShellBarLayout) -> some View {
        Section(side(lane)) {
            let names = layout.names(in: lane)
            if names.isEmpty {
                Text("No widgets")
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
            ForEach(names, id: \.self) { name in
                row(name, layout: layout)
                    .tag(name)
                    .contextMenu { menu(for: name, in: lane, of: layout) }
            }
            .onMove { offsets, destination in
                update(unlessChanged: (lane, names)) { $0.move(in: lane, from: offsets, to: destination) }
            }
        }
    }

    private func row(_ name: String, layout: ShellBarLayout) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(ShellBarLayout.title(of: name))
                if let caption = caption(of: name, layout: layout) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: layout.source(of: name) == nil
                ? "exclamationmark.triangle"
                : Self.symbols[name] ?? "puzzlepiece.extension")
        }
    }

    @ViewBuilder
    private func menu(for name: String, in lane: ShellLane, of layout: ShellBarLayout) -> some View {
        let names = layout.names(in: lane)
        Button("Move Up") { update { $0.shift(name, by: -1) } }
            .disabled(names.first == name)
        Button("Move Down") { update { $0.shift(name, by: 1) } }
            .disabled(names.last == name)
        ForEach(ShellLane.allCases.filter { $0 != lane }, id: \.self) { target in
            Button("Move to \(side(target))") { update { $0.move(name, to: target) } }
        }
        Divider()
        Button("Remove from Bar", role: .destructive) { remove(name) }
    }

    private func controls(_ layout: ShellBarLayout) -> some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(ShellLane.allCases, id: \.self) { lane in
                    Menu("Add to \(side(lane))") {
                        ForEach(layout.addable) { widget in
                            Button(ShellBarLayout.title(of: widget.name)) {
                                update { $0.add(widget.name, to: lane) }
                                selection = widget.name
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(layout.addable.isEmpty)
            .help("Add a widget")
            Button {
                if let selection {
                    remove(selection)
                }
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Remove the selected widget")
            Spacer()
            Button("Use Profile Layout") { confirmingReset = true }
                .disabled(!layout.customized)
        }
    }

    private func caption(of name: String, layout: ShellBarLayout) -> String? {
        switch layout.source(of: name) {
        case .none: String(localized: "Not found")
        case .yours: String(localized: "Your widget")
        case let .profile(profile): String(localized: "“\(profile)” profile")
        case .builtIn: nil
        }
    }

    private func side(_ lane: ShellLane) -> String {
        ShellBarLayout.side(lane, vertical: vertical)
    }

    private func height(of layout: ShellBarLayout) -> CGFloat {
        let rows = ShellLane.allCases.map(layout.names(in:)).map { names in
            names.isEmpty ? Self.rowHeight : names.reduce(0) { height, name in
                height + (caption(of: name, layout: layout) == nil ? Self.rowHeight : Self.captionedRowHeight)
            }
        }
        return rows.reduce(Self.chromeHeight, +)
    }

    private func remove(_ name: String) {
        update { $0.remove(name) }
        if selection == name {
            selection = nil
        }
    }

    private func update(
        unlessChanged expected: (lane: ShellLane, names: [String])? = nil,
        _ change: (inout ShellBarLayout) -> Void
    ) {
        do {
            try ShellBarLayout.edit(shellDirectory: shellDirectory, unlessChanged: expected, change)
        } catch {
            Log.shell.error("Failed to save the bar widget layout: \(error.localizedDescription)")
        }
        reload()
    }

    private func reset() {
        do {
            try ShellBarLayout.reset(shellDirectory: shellDirectory)
        } catch {
            Log.shell.error("Failed to reset the bar widget layout: \(error.localizedDescription)")
        }
        selection = nil
        reload()
    }

    private func reload() {
        switch ShellBarLayout.load(shellDirectory: shellDirectory) {
        case let .success(loaded):
            layout = loaded
            problem = nil
        case let .failure(unreadable):
            layout = nil
            problem = unreadable.problem
        }
    }
}
