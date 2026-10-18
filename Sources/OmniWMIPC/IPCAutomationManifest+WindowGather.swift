// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension IPCAutomationManifest {
    public static let windowGatherActionDescriptors: [IPCWindowGatherActionDescriptor] = [
        .init(
            path: "window gather [--from workspace|monitor|all] <window-id>...",
            summary: "Gather managed windows by opaque id, in order, into one Niri column on the active command workspace; --from sets where they may come from (default workspace).",
            arguments: ["window-id..."]
        )
    ]
}
