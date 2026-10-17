// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit

@MainActor
final class OverviewTabPicker: NSObject {
    let handle: WindowHandle
    let menu = NSMenu()
    private let select: (WindowHandle) -> Void

    init(handle: WindowHandle, members: [OverviewWindowItem], select: @escaping (WindowHandle) -> Void) {
        self.handle = handle
        self.select = select
        super.init()
        menu.autoenablesItems = false
        for member in members {
            let item = NSMenuItem(
                title: member.title.isEmpty ? member.appName : member.title,
                action: #selector(selectItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = member.handle
            item.state = member.handle == handle ? .on : .off
            if let icon = member.appIcon { item.image = NSImage(cgImage: icon, size: NSSize(width: 16, height: 16)) }
            menu.addItem(item)
        }
    }

    @objc private func selectItem(_ sender: NSMenuItem) {
        guard let handle = sender.representedObject as? WindowHandle else { return }
        select(handle)
    }

    func cancel() {
        menu.cancelTracking()
    }
}
