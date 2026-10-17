// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import TOML

public enum AppLanguagePreference {
    private static let key = "AppleLanguages"

    static let availableLanguages: [String] = {
        let languages = Bundle.module.localizations.filter { $0 != "Base" && $0 != "en" }
        return ["en"] + languages.sorted {
            nativeName(for: $0).localizedStandardCompare(nativeName(for: $1)) == .orderedAscending
        }
    }()

    static func nativeName(for language: String) -> String {
        Locale(identifier: language).localizedString(forIdentifier: language) ?? language
    }

    public static func applyConfiguredLanguage() {
        let defaults = UserDefaults.standard
        guard let arguments = launchArguments(
            defaults.volatileDomain(forName: UserDefaults.argumentDomain),
            selecting: configuredLanguage(in: SettingsFilePersistence.fileURL)
        ) else { return }
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    static func configuredLanguage(in fileURL: URL) -> String? {
        guard let targetURL = try? SettingsFileAccess.settingsTarget(for: fileURL),
              let data = try? SettingsFileAccess.existingData(at: targetURL),
              let settings = try? TOMLDecoder().decode([String: TOMLNode].self, from: data),
              case let .table(general)? = settings["general"],
              case let .string(language)? = general["language"]
        else { return nil }
        return language
    }

    static func launchArguments(_ arguments: [String: Any], selecting language: String?) -> [String: Any]? {
        guard let language, arguments[key] == nil else { return nil }
        var arguments = arguments
        arguments[key] = [language]
        return arguments
    }
}
