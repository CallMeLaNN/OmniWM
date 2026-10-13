// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

struct ShellComponentReloadPlan {
    struct Module {
        let path: String
        let source: String?
    }

    let widgets: [String]
    let modules: [Module]

    static func make(
        source: ShellWidgetSource,
        loadedChunk: String,
        loadedMain: String,
        loadedModules: Set<String>,
        previousDescriptors: [ShellComponentDescriptor],
        matches: (ShellWidgetSource.Module) -> Bool
    ) -> ShellComponentReloadPlan? {
        guard source.chunk == loadedChunk, source.main == loadedMain else { return nil }
        let parts = source.chunk.dropFirst().split(separator: "/")
        guard source.chunk.hasPrefix("@"), parts.count >= 3 else {
            return source.modules.isEmpty && loadedModules.isEmpty
                ? ShellComponentReloadPlan(widgets: [], modules: []) : nil
        }
        let root = String(parts[parts.count - 2])
        let layer = parts.dropLast(3).joined(separator: "/")
        let prefix = (layer.isEmpty ? "" : layer + "/") + "widgets/"
        func widget(for path: String) -> String? {
            guard path.hasPrefix(prefix) else { return nil }
            let relative = path.dropFirst(prefix.count)
            guard let end = relative.firstIndex(of: "/") else { return nil }
            let widget = String(relative[..<end])
            return widget == root ? nil : widget
        }
        let paths = Set(source.modules.map(\.path))
        var modules: [Module] = []
        var widgets: Set<String> = []
        for module in source.modules where !loadedModules.contains(module.path) || !matches(module) {
            guard let owner = widget(for: module.path) else { return nil }
            widgets.insert(owner)
            modules.append(Module(path: module.path, source: module.source))
        }
        for path in loadedModules where !paths.contains(path) {
            guard let owner = widget(for: path) else { return nil }
            widgets.insert(owner)
            modules.append(Module(path: path, source: nil))
        }
        let previous = Dictionary(uniqueKeysWithValues: previousDescriptors.map { ($0.widget, $0.uses) })
        for descriptor in source.componentDescriptors {
            if let uses = previous[descriptor.widget], Set(uses) != Set(descriptor.uses) {
                widgets.insert(descriptor.widget)
            }
        }
        let dependencies = previousDescriptors + source.componentDescriptors
        var expanded = true
        while expanded {
            expanded = false
            for descriptor in dependencies where !widgets.contains(descriptor.widget) {
                if descriptor.uses.contains(where: widgets.contains) {
                    widgets.insert(descriptor.widget)
                    expanded = true
                }
            }
        }
        return ShellComponentReloadPlan(widgets: widgets.sorted(), modules: modules.sorted { $0.path < $1.path })
    }
}
