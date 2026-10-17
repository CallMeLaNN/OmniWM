// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWM
import XCTest

@MainActor
final class NativeAppUnhideTests: XCTestCase {
    func testActivationBeforeNativeUnhideRestoresWorkspaceAndFocusInBothLayouts() throws {
        for layout: LayoutType in [.niri, .dwindle] {
            let fixture = try Fixture(layout: layout)
            defer { fixture.stop() }

            fixture.send(.activated(pid: fixture.token.pid))
            XCTAssertTrue(fixture.requestedPIDs.isEmpty)
            fixture.assertInactive()

            fixture.send(.unhidden(pid: fixture.token.pid))
            fixture.controller.eventIntake.drainNow()

            fixture.assertRestored()
            XCTAssertEqual(fixture.requestedPIDs, [fixture.token.pid])
            XCTAssertEqual(fixture.requestedVisibilityGenerations, [2])
        }
    }

    func testNativeUnhideBeforeActivationRestoresWorkspaceAndFocusInBothLayouts() throws {
        for layout: LayoutType in [.niri, .dwindle] {
            let fixture = try Fixture(layout: layout)
            defer { fixture.stop() }

            XCTAssertTrue(fixture.controller.eventIntake.enqueue(.application(.unhidden(pid: fixture.token.pid))))
            XCTAssertTrue(fixture.controller.eventIntake.enqueue(.application(.activated(pid: fixture.token.pid))))
            fixture.controller.eventIntake.drainNow()
            fixture.controller.eventIntake.drainNow()

            fixture.assertRestored()
            XCTAssertEqual(fixture.requestedPIDs, [fixture.token.pid, fixture.token.pid])
            XCTAssertEqual(fixture.requestedVisibilityGenerations, [2, 2])
        }
    }

    func testBackgroundUnhidePreservesInactiveWorkspace() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.frontmostPID = fixture.token.pid + 1

        fixture.send(.unhidden(pid: fixture.token.pid))
        fixture.controller.eventIntake.drainNow()

        XCTAssertFalse(fixture.controller.workspaceManager.isAppHidden(fixture.token))
        XCTAssertTrue(fixture.requestedPIDs.isEmpty)
        fixture.assertInactive()
    }

    func testDuplicateNativeUnhideDoesNotRequestAdditionalFacts() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }

        fixture.send(.unhidden(pid: fixture.token.pid))
        fixture.controller.eventIntake.drainNow()
        fixture.send(.unhidden(pid: fixture.token.pid))
        fixture.controller.eventIntake.drainNow()

        fixture.assertRestored()
        XCTAssertEqual(fixture.requestedPIDs, [fixture.token.pid])
        XCTAssertEqual(fixture.controller.workspaceManager.appVisibilityGeneration(for: fixture.token.pid), 2)
    }

    func testExplicitRevealOwnsUnhideWithoutCompetingActivation() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        let controller = fixture.controller
        let handle = try XCTUnwrap(controller.workspaceManager.handle(for: fixture.token))
        let intent = controller.intentLedger.beginAppRevealFocus(
            token: fixture.token,
            workspaceId: fixture.targetWorkspace,
            handleIdentity: ObjectIdentifier(handle),
            pendingApps: [fixture.token.pid: controller.workspaceManager
                .appVisibilityGeneration(for: fixture.token.pid)],
            focusFingerprint: AppRevealActions.appRevealFocusFingerprint(controller: controller)
        )

        fixture.send(.unhidden(pid: fixture.token.pid))
        controller.eventIntake.drainNow()

        XCTAssertTrue(fixture.requestedPIDs.isEmpty)
        XCTAssertEqual(controller.intentLedger.intent(id: intent.id)?.phase, .pending)
        XCTAssertNil(controller.intentLedger.activeManagedRequest)
        fixture.assertInactive()
    }

    func testVisibilityOnlyUnhideDoesNotSynthesizeActivation() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }

        fixture.controller.axEventHandler.handleAppUnhidden(pid: fixture.token.pid, source: .service)
        fixture.controller.eventIntake.drainNow()

        XCTAssertFalse(fixture.controller.workspaceManager.isAppHidden(fixture.token))
        XCTAssertTrue(fixture.requestedPIDs.isEmpty)
        fixture.assertInactive()
    }

    func testDelayedUnhideFactsCannotStealFocusAfterFrontmostApplicationChanges() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }

        fixture.send(.unhidden(pid: fixture.token.pid))
        XCTAssertEqual(fixture.requestedPIDs, [fixture.token.pid])
        fixture.frontmostPID = fixture.token.pid + 1
        fixture.controller.eventIntake.drainNow()

        fixture.assertInactive()
    }

    func testDelayedUnhideFactsCannotRefocusApplicationHiddenAgain() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }

        fixture.send(.unhidden(pid: fixture.token.pid))
        XCTAssertEqual(fixture.requestedPIDs, [fixture.token.pid])
        fixture.controller.axEventHandler.handleAppHidden(pid: fixture.token.pid, source: .service)
        fixture.controller.eventIntake.drainNow()

        XCTAssertTrue(fixture.controller.workspaceManager.isAppHidden(fixture.token))
        fixture.assertInactive()
    }

    func testDelayedUnhideFactsPreserveNewerManagedFocusRequest() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        let controller = fixture.controller
        let otherToken = WindowToken(pid: fixture.token.pid + 1, windowId: fixture.token.windowId + 1)
        _ = WindowAdmissionTestSupport.track(otherToken, in: fixture.otherWorkspace, controller: controller)

        fixture.send(.unhidden(pid: fixture.token.pid))
        XCTAssertEqual(fixture.requestedPIDs, [fixture.token.pid])
        let request = controller.intentLedger.beginManagedRequest(
            token: otherToken,
            workspaceId: fixture.otherWorkspace
        )
        XCTAssertTrue(controller.workspaceManager.beginManagedFocusRequest(
            otherToken, in: fixture.otherWorkspace, requestId: request.requestId
        ))
        controller.eventIntake.drainNow()

        XCTAssertEqual(controller.intentLedger.activeManagedRequest, request)
        XCTAssertEqual(controller.workspaceManager.pendingFocusedToken, otherToken)
        fixture.assertInactive()
    }

    func testNativeMenuPolicyRejectsUnhideActivation() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.controller.focusPolicyEngine.beginLease(owner: .nativeMenu, reason: "native_menu", duration: nil)

        fixture.send(.unhidden(pid: fixture.token.pid))
        fixture.controller.eventIntake.drainNow()

        XCTAssertFalse(ActivationEventSource.workspaceDidUnhideApplication.isAuthoritative)
        XCTAssertFalse(fixture.controller.workspaceManager.isAppHidden(fixture.token))
        XCTAssertTrue(fixture.requestedPIDs.isEmpty)
        XCTAssertEqual(fixture.controller.focusPolicyEngine.activeLease?.owner, .nativeMenu)
        fixture.assertInactive()
    }

    @MainActor
    private final class Fixture {
        let controller = WindowAdmissionTestSupport.controller(prefix: "NativeAppUnhideTests")
        let token = WindowToken(pid: 970_401, windowId: 970_501)
        let monitor: Monitor
        let targetWorkspace: WorkspaceDescriptor.ID
        let otherWorkspace: WorkspaceDescriptor.ID
        var frontmostPID: pid_t? = 970_401
        var requestedPIDs: [pid_t] = []
        var requestedVisibilityGenerations: [UInt64] = []

        init(layout: LayoutType = .niri) throws {
            controller.settings.animationsEnabled = false
            controller.settings.focus.moveMouseToFocusedWindow = false
            monitor = Monitor(
                id: .init(displayId: 970_400),
                displayId: 970_400,
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 860),
                hasNotch: false,
                name: "Native App Unhide Test"
            )
            controller.workspaceManager.applyMonitorConfigurationChange([monitor])
            targetWorkspace = try XCTUnwrap(WindowAdmissionTestSupport.workspace(
                named: "91", layoutType: layout, controller: controller
            ))
            otherWorkspace = try XCTUnwrap(WindowAdmissionTestSupport.workspace(
                named: "92", layoutType: layout, controller: controller
            ))
            _ = controller.workspaceManager.focusWorkspace(id: targetWorkspace)
            controller.niriLayoutHandler.enableNiriLayout()
            controller.dwindleLayoutHandler.enableDwindleLayout()
            let axRef = WindowAdmissionTestSupport.track(token, in: targetWorkspace, controller: controller)
            controller.workspaceManager.withEngineMutationScope(in: targetWorkspace) {
                switch controller.workspaceManager.activeLayoutKind(for: targetWorkspace) {
                case .niri:
                    _ = controller.niriEngine?.addWindow(token: token, to: targetWorkspace, afterSelection: nil)
                case .dwindle:
                    _ = controller.dwindleEngine?.addWindow(token: token, to: targetWorkspace, activeWindowFrame: nil)
                }
            }
            controller.axEventHandler.handleAppHidden(pid: token.pid, source: .service)
            _ = controller.workspaceManager.focusWorkspace(id: otherWorkspace)
            controller.workspaceManager.setHiddenState(
                HiddenState(
                    proportionalPosition: CGPoint(x: 0.5, y: 0.5),
                    referenceMonitorId: monitor.id,
                    reason: .workspaceInactive
                ),
                for: token
            )
            controller.layoutRefreshController.resetState()
            controller.axEventHandler.frontmostApplicationPIDProvider = { [weak self] in self?.frontmostPID }
            controller.axEventHandler.windowInfoProvider = { _ in nil }
            controller.factResolver.factProvider = { [weak self] pid in
                self?.requestedPIDs.append(pid)
                if let self {
                    requestedVisibilityGenerations.append(controller.workspaceManager.appVisibilityGeneration(for: pid))
                }
                return FocusedWindowFact(axRef: axRef, isFullscreen: false, isSystemModalSurface: false)
            }
            controller.hasStartedServices = true
            controller.eventIntake.open(sink: controller.eventInterpreter)
        }

        func send(_ event: ApplicationIntakeEvent) {
            XCTAssertTrue(controller.eventIntake.enqueue(.application(event)))
            controller.eventIntake.drainNow()
        }

        func assertRestored(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertFalse(controller.workspaceManager.isAppHidden(token), file: file, line: line)
            XCTAssertEqual(
                controller.workspaceManager.activeWorkspace(on: monitor.id)?.id,
                targetWorkspace,
                file: file,
                line: line
            )
            XCTAssertEqual(controller.workspaceManager.nativeManagedFocusToken, token, file: file, line: line)
        }

        func assertInactive(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(
                controller.workspaceManager.activeWorkspace(on: monitor.id)?.id,
                otherWorkspace,
                file: file,
                line: line
            )
            XCTAssertNil(controller.workspaceManager.nativeManagedFocusToken, file: file, line: line)
            XCTAssertEqual(
                controller.workspaceManager.hiddenState(for: token)?.workspaceInactive,
                true,
                file: file,
                line: line
            )
        }

        func stop() {
            controller.eventIntake.close()
            controller.deadlineWheel.stop()
            controller.factResolver.stop()
            controller.layoutRefreshController.resetState()
        }
    }
}
