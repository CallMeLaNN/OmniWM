// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

@testable import OmniWM
import QuartzCore
import XCTest

@MainActor
final class OverviewPreviewFadeTests: XCTestCase {
    func testFirstLiveFrameFadesOnceAndLaterFramesKeepTheSameAnimation() throws {
        let card = OverviewWindowLayer()
        let first = try makeOverviewPreviewFrame()
        card.updatePreview(first, animated: true)
        let animation = try XCTUnwrap(card.thumbnail.animation(forKey: "overview.previewReveal") as? CABasicAnimation)
        XCTAssertEqual(animation.keyPath, "opacity")
        XCTAssertEqual(animation.duration, 0.15)
        XCTAssertEqual(animation.fromValue as? Double, 0)
        XCTAssertEqual(animation.toValue as? Double, 1)
        XCTAssertEqual(animation.timingFunction, CAMediaTimingFunction(name: .easeOut))
        XCTAssertEqual(card.thumbnail.opacity, 1)
        XCTAssertNil(card.root.animation(forKey: "overview.previewReveal"))

        let marked = try XCTUnwrap(animation.copy() as? CABasicAnimation)
        marked.beginTime = 123
        card.thumbnail.add(marked, forKey: "overview.previewReveal")
        card.updatePreview(try makeOverviewPreviewFrame(), animated: true)
        XCTAssertEqual(card.thumbnail.animation(forKey: "overview.previewReveal")?.beginTime, 123)
        card.thumbnail.removeAnimation(forKey: "overview.previewReveal")
        card.updatePreview(try makeOverviewPreviewFrame(), animated: true)
        XCTAssertNil(card.thumbnail.animation(forKey: "overview.previewReveal"))
    }

    func testCachedPreviewSeedsWithoutFadeAndLiveReplacementStaysImmediate() throws {
        let card = OverviewWindowLayer()
        card.updatePreview(try makeOverviewPreviewFrame())
        XCTAssertNil(card.thumbnail.animation(forKey: "overview.previewReveal"))
        card.updatePreview(try makeOverviewPreviewFrame(), animated: true)
        XCTAssertNil(card.thumbnail.animation(forKey: "overview.previewReveal"))
    }

    func testRemovalAndDisabledMotionClearRevealWithoutAffectingGeometryMotion() throws {
        let card = OverviewWindowLayer()
        let frame = try makeOverviewPreviewFrame()
        let movement = CABasicAnimation(keyPath: "position")
        movement.fromValue = NSValue(point: .zero)
        movement.toValue = NSValue(point: CGPoint(x: 100, y: 0))
        movement.duration = 1
        card.root.add(movement, forKey: "overview.position")
        card.updatePreview(frame, animated: true)
        XCTAssertNotNil(card.thumbnail.animation(forKey: "overview.previewReveal"))
        XCTAssertNotNil(card.root.animation(forKey: "overview.position"))
        card.updatePreview(frame, animated: false)
        XCTAssertNil(card.thumbnail.animation(forKey: "overview.previewReveal"))
        XCTAssertNotNil(card.root.animation(forKey: "overview.position"))
        card.updatePreview(nil)
        card.updatePreview(frame, animated: true)
        XCTAssertNotNil(card.thumbnail.animation(forKey: "overview.previewReveal"))
        card.updatePreview(nil)
        XCTAssertNil(card.preview)
        XCTAssertNil(card.thumbnail.contents)
        XCTAssertNil(card.thumbnail.animation(forKey: "overview.previewReveal"))
    }
}
