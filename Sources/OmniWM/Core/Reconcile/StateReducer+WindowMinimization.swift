// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

extension StateReducer {
    static func reduceNativeWindowSuppression(_ event: WMEvent, context: ReductionContext, plan: inout ActionPlan) {
        let token: WindowToken
        switch event {
        case let .windowMinimizedChanged(changedToken, _, true, _),
             let .windowNativeWithdrawalChanged(changedToken, _, true, _):
            token = changedToken
        default:
            return
        }
        var focus = context.currentSnapshot.focusSession
        if focus.pendingManagedFocus.token == token {
            focus.pendingManagedFocus = .empty
        }
        switch focus.nativeFocusOwner {
        case let .managed(focusedToken) where focusedToken == token:
            focus.nativeFocusOwner = .none
        case let .external(identity) where identity.exactToken == token:
            focus.nativeFocusOwner = .external(identity.downgradingToPIDOnly())
        case let .external(identity) where identity.verifiedManagedParentToken == token:
            focus.nativeFocusOwner = .external(identity.clearingVerifiedManagedParent())
        default:
            break
        }
        if focus.systemModalFocusToken == token {
            focus.systemModalFocusToken = nil
        }
        setFocusSession(focus, current: context.currentSnapshot.focusSession, plan: &plan)
    }
}
