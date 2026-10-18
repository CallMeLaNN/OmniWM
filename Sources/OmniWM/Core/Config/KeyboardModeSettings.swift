// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Observation

extension SettingsExport {
    struct KeyboardModes: Codable, Equatable {
        var pauseTimeoutSeconds: Double?

        var pauseTimeout: Duration? {
            guard let pauseTimeoutSeconds, pauseTimeoutSeconds > 0 else { return nil }
            let milliseconds = (pauseTimeoutSeconds * 1000).rounded()
            guard milliseconds < Double(Int64.max) else { return nil }
            return .milliseconds(Int64(milliseconds))
        }
    }
}

@MainActor @Observable
final class KeyboardModeSettings {
    @ObservationIgnored var onChange: (() -> Void)?

    var pauseTimeoutSeconds: Double? {
        didSet { onChange?() }
    }

    func export() -> SettingsExport.KeyboardModes {
        SettingsExport.KeyboardModes(pauseTimeoutSeconds: pauseTimeoutSeconds)
    }

    func apply(_ values: SettingsExport.KeyboardModes) {
        pauseTimeoutSeconds = values.pauseTimeoutSeconds
    }
}
