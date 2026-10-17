// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

final class ApplicationCatalogFilterTests: XCTestCase {
    private let home = "/Users/tester"

    func testCatalogPathMembership() {
        let cases: [(String, Bool)] = [
            ("/Applications/Safari.app", true),
            ("/Applications/Utilities/Terminal.app", true),
            ("/System/Applications/Calculator.app", true),
            ("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", true),
            ("/Users/tester/Applications/Chrome Apps.localized/Docs.app", true),
            ("/Users/Shared/Tool.app", true),
            ("/Users/tester/Downloads/Installer.app", true),
            ("/System/Library/CoreServices/Applications/Keychain Access.app", true),
            (ApplicationCatalogFilter.finderPath, true),
            ("/Applications/Xcode.app/Contents/Applications/Instruments.app", false),
            ("/Applications/Suite.app/Helper.app", false),
            ("/Applications/Vendor/Nested/Tool.app", false),
            ("/Users/tester/Downloads/Archive/Installer.app", false),
            ("/System/Library/CoreServices/Dock.app", false),
            ("/Applications/README.txt", false)
        ]
        for (path, expected) in cases {
            XCTAssertEqual(ApplicationCatalogFilter.isCatalogPath(path, home: home), expected, path)
        }
    }
}
