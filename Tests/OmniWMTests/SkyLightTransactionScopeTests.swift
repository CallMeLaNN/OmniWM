// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import XCTest

final class SkyLightTransactionScopeTests: XCTestCase {
    @MainActor
    func testScopeCreatesTransactionOnlyOnFirstUse() throws {
        let skyLight = SkyLight.shared
        var created = false
        skyLight.withTransactionScope {
            XCTAssertNil(skyLight.scopedTransaction)
            var first: CFTypeRef?
            skyLight.withTransaction { first = $0 }
            created = first != nil
            XCTAssertTrue(skyLight.scopedTransaction === first)
            skyLight.withTransaction { second in
                XCTAssertTrue(second === first)
            }
            skyLight.withTransactionScope {
                skyLight.withTransaction { nested in
                    XCTAssertTrue(nested === first)
                }
            }
            XCTAssertTrue(skyLight.scopedTransaction === first)
        }
        XCTAssertNil(skyLight.scopedTransaction)
        try XCTSkipUnless(created, "WindowServer transactions unavailable")
    }
}
