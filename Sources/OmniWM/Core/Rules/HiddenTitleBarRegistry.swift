// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation

enum HiddenTitleBarRegistry {
    static let fullscreenButtonOptionalBundleIds: Set<String> = [
        "com.adobe.acc.adobecreativecloud",
        "com.adobe.acrobat.pro",
        "com.adobe.aftereffects",
        "com.adobe.illustrator",
        "com.adobe.indesign",
        "com.adobe.lightroomclassiccc7",
        "com.adobe.photoshop",
        "com.adobe.premierepro.25",
        "com.adobe.premierepro.26",
        "com.microsoft.vscode",
        "com.vscodium"
    ]

    static let nonStandardSubroleBundleIds: Set<String> = [
        "org.qutebrowser.qutebrowser"
    ]

    static func decision(
        for facts: AXWindowFacts,
        windowServer: WindowServerInfo?,
        fullscreenButtonOptionalBundleIds: Set<String>,
        nonStandardSubroleBundleIds: Set<String>
    ) -> Bool {
        guard facts.attributeFetchSucceeded,
              facts.role == (kAXWindowRole as String),
              let windowServer,
              windowServer.level == 0,
              !windowServer.hasParentWindow
        else {
            return false
        }

        let hasAnyButton = facts.hasCloseButton
            || facts.hasFullscreenButton
            || facts.hasZoomButton
            || facts.hasMinimizeButton
        let isStandardSubrole = facts.subrole == (kAXStandardWindowSubrole as String)

        if !hasAnyButton, isStandardSubrole, facts.appPolicy == .regular {
            return true
        }

        guard let bundleId = facts.bundleId?.lowercased() else { return false }

        if !facts.hasFullscreenButton, fullscreenButtonOptionalBundleIds.contains(bundleId) {
            return true
        }

        return !hasAnyButton
            && facts.subrole == (kAXDialogSubrole as String)
            && nonStandardSubroleBundleIds.contains(bundleId)
    }
}
