// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

public enum IPCSocketPath {
    public static let environmentKey = "OMNIWM_SOCKET"
    public static let secretSuffix = ".secret"

    public static func resolvedPath() -> String {
        if let override = getenv(environmentKey).map({ String(cString: $0) }), !override.isEmpty {
            return override
        }

        return URL.applicationSupportDirectory
            .appendingPathComponent("com.barut.OmniWM", isDirectory: true)
            .appendingPathComponent("ipc.sock", isDirectory: false)
            .path
    }

    public static func secretPath(forSocketPath socketPath: String) -> String {
        socketPath + secretSuffix
    }
}
