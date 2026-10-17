// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class DwindleWindowAdmissionTests: XCTestCase {
    private let landscape = CGRect(x: 80, y: 40, width: 1400, height: 860)
    private let portrait = CGRect(x: 80, y: 40, width: 707, height: 860)
    private let existing = WindowToken(pid: 1, windowId: 1)
    private let new = WindowToken(pid: 2, windowId: 2)

    func testDefaultAdmissionPlacesNewWindowRightOrBelow() throws {
        for smartSplit in [false, true] {
            for screen in [landscape, portrait] {
                let (engine, workspace) = makeEngine(smartSplit: smartSplit, screen: screen)

                _ = engine.syncWindows(
                    [existing, new],
                    in: workspace,
                    focusedToken: existing,
                    bootstrapScreen: screen
                )

                let direction: Direction = smartSplit || screen == portrait ? .down : .right
                try assertNewWindow(direction, engine: engine, workspace: workspace, screen: screen)
            }
        }
    }

    func testMissingActiveFramePlacesNewWindowRightOrBelow() throws {
        for smartSplit in [false, true] {
            for screen in [landscape, portrait] {
                let (engine, workspace) = makeEngine(smartSplit: smartSplit, screen: screen)

                engine.addWindow(token: new, to: workspace, activeWindowFrame: nil)

                let direction: Direction = screen == portrait ? .down : .right
                try assertNewWindow(direction, engine: engine, workspace: workspace, screen: screen)
            }
        }
    }

    func testPreselectionPreservesRequestedSide() throws {
        for smartSplit in [false, true] {
            for direction: Direction in [.left, .right, .up, .down] {
                let (engine, workspace) = makeEngine(smartSplit: smartSplit, screen: landscape)
                XCTAssertTrue(engine.setPreselection(direction, in: workspace))

                _ = engine.syncWindows(
                    [existing, new],
                    in: workspace,
                    focusedToken: existing,
                    bootstrapScreen: landscape
                )

                try assertNewWindow(direction, engine: engine, workspace: workspace, screen: landscape)
                XCTAssertNil(engine.existingState(for: workspace)?.preselection)
            }
        }
    }

    func testSmartSplitPreservesNonCenteredPlacement() throws {
        let placements: [(Direction, CGFloat, CGFloat)] = [
            (.left, -100, 0), (.right, 100, 0), (.up, 0, 100), (.down, 0, -100)
        ]
        for (direction, deltaX, deltaY) in placements {
            let (engine, workspace) = makeEngine(smartSplit: true, screen: landscape)
            let target = try XCTUnwrap(engine.findNode(for: existing, in: workspace)?.cachedFrame)

            engine.addWindow(
                token: new,
                to: workspace,
                activeWindowFrame: target.offsetBy(dx: deltaX, dy: deltaY)
            )

            try assertNewWindow(direction, engine: engine, workspace: workspace, screen: landscape)
        }
    }

    private func makeEngine(
        smartSplit: Bool,
        screen: CGRect
    ) -> (DwindleLayoutEngine, WorkspaceDescriptor.ID) {
        let engine = DwindleLayoutEngine()
        let workspace = WorkspaceDescriptor.ID()
        engine.settings.smartSplit = smartSplit
        _ = engine.syncWindows([existing], in: workspace, focusedToken: existing, bootstrapScreen: screen)
        _ = engine.calculateLayout(for: workspace, screen: screen)
        return (engine, workspace)
    }

    private func assertNewWindow(
        _ direction: Direction,
        engine: DwindleLayoutEngine,
        workspace: WorkspaceDescriptor.ID,
        screen: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let frames = engine.calculateLayout(for: workspace, screen: screen)
        let existingFrame = try XCTUnwrap(frames[existing], file: file, line: line)
        let newFrame = try XCTUnwrap(frames[new], file: file, line: line)
        switch direction {
        case .left:
            XCTAssertLessThanOrEqual(newFrame.maxX, existingFrame.minX, file: file, line: line)
        case .right:
            XCTAssertGreaterThanOrEqual(newFrame.minX, existingFrame.maxX, file: file, line: line)
        case .up:
            XCTAssertGreaterThanOrEqual(newFrame.minY, existingFrame.maxY, file: file, line: line)
        case .down:
            XCTAssertLessThanOrEqual(newFrame.maxY, existingFrame.minY, file: file, line: line)
        }
    }
}
