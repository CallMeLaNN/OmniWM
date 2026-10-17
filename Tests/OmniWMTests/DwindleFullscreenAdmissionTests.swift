// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class DwindleFullscreenAdmissionTests: XCTestCase {
    private let screen = CGRect(x: 8, y: 8, width: 1424, height: 854)
    private let first = WindowToken(pid: 1, windowId: 1)
    private let second = WindowToken(pid: 2, windowId: 2)
    private let third = WindowToken(pid: 3, windowId: 3)

    func testNewWindowExitsFullscreenAndSplitsTheTiledFrame() {
        for smartSplit in [false, true] {
            let (control, controlWorkspace) = makeEngine(smartSplit: smartSplit)
            _ = sync(control, [first], in: controlWorkspace)
            _ = sync(control, [first, second], in: controlWorkspace)
            let expected = sync(control, [first, second, third], in: controlWorkspace)

            let (engine, workspace) = makeEngine(smartSplit: smartSplit)
            _ = sync(engine, [first], in: workspace)
            _ = sync(engine, [first, second], in: workspace)
            XCTAssertEqual(engine.toggleFullscreen(in: workspace), first)
            XCTAssertEqual(sync(engine, [first, second], in: workspace)[first], screen)

            XCTAssertEqual(sync(engine, [first, second, third], in: workspace), expected, "smartSplit=\(smartSplit)")
            XCTAssertTrue(engine.fullscreenTokens(in: workspace).isEmpty, "smartSplit=\(smartSplit)")
        }
    }

    func testNewWindowExitsLoneWindowFullscreen() {
        let (control, controlWorkspace) = makeEngine(smartSplit: false)
        _ = sync(control, [first], in: controlWorkspace)
        let expected = sync(control, [first, second], in: controlWorkspace)

        let (engine, workspace) = makeEngine(smartSplit: false)
        _ = sync(engine, [first], in: workspace)
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), first)
        _ = sync(engine, [first], in: workspace)

        XCTAssertEqual(sync(engine, [first, second], in: workspace), expected)
        XCTAssertTrue(engine.fullscreenTokens(in: workspace).isEmpty)
    }

    func testRelayoutWithoutNewWindowsKeepsFullscreen() {
        let (engine, workspace) = makeEngine(smartSplit: false)
        _ = sync(engine, [first], in: workspace)
        _ = sync(engine, [first, second], in: workspace)
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), first)

        XCTAssertEqual(sync(engine, [first, second], in: workspace)[first], screen)
        XCTAssertEqual(sync(engine, [first], in: workspace)[first], screen)
        XCTAssertEqual(engine.fullscreenTokens(in: workspace), [first])
    }

    private func makeEngine(smartSplit: Bool) -> (DwindleLayoutEngine, WorkspaceDescriptor.ID) {
        let engine = DwindleLayoutEngine()
        engine.settings.smartSplit = smartSplit
        engine.settings.splitWidthMultiplier = 1.4
        return (engine, WorkspaceDescriptor.ID())
    }

    private func sync(
        _ engine: DwindleLayoutEngine,
        _ tokens: [WindowToken],
        in workspace: WorkspaceDescriptor.ID
    ) -> [WindowToken: CGRect] {
        _ = engine.syncWindows(
            tokens,
            in: workspace,
            focusedToken: first,
            bootstrapScreen: screen,
            bootstrapFullscreenScreen: screen
        )
        return engine.calculateLayout(for: workspace, screen: screen, fullscreenScreen: screen)
    }
}
