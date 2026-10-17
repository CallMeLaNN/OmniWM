// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct SponsorAutoScrollList<Content: View>: View {
    let animationsEnabled: Bool
    let speed: CGFloat
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var scrollPosition = ScrollPosition()
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var lastTick: TimeInterval?
    @State private var isUserScrolling = false
    @State private var resumeTask: Task<Void, Never>?

    private var canAutoScroll: Bool {
        animationsEnabled && contentHeight > viewportHeight && contentHeight > 1 && viewportHeight > 1
    }

    private var loopDistance: CGFloat {
        contentHeight + spacing
    }

    private var timelinePaused: Bool {
        !canAutoScroll || isUserScrolling
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: spacing) {
                measuredContent

                if canAutoScroll {
                    content()
                }
            }
        }
        .scrollIndicators(.visible)
        .scrollPosition($scrollPosition)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newValue in
            viewportHeight = newValue
            reconcileAutoScrollState()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            scrollOffsetChanged(newValue)
        }
        .onScrollPhaseChange { _, newPhase in
            scrollPhaseChanged(newPhase)
        }
        .overlay {
            timelineDriver
                .allowsHitTesting(false)
        }
        .onChange(of: animationsEnabled) { _, _ in
            reconcileAutoScrollState()
        }
        .onChange(of: canAutoScroll) { _, _ in
            reconcileAutoScrollState()
        }
        .onDisappear {
            resumeTask?.cancel()
            resumeTask = nil
            lastTick = nil
            isUserScrolling = false
        }
    }

    private var measuredContent: some View {
        content()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                contentHeight = newValue
                reconcileAutoScrollState()
            }
    }

    private var timelineDriver: some View {
        TimelineView(.animation(paused: timelinePaused)) { context in
            Color.clear
                .onAppear {
                    tick(context.date)
                }
                .onChange(of: context.date) { _, date in
                    tick(date)
                }
        }
    }

    private func scrollOffsetChanged(_ newValue: CGFloat) {
        guard newValue.isFinite else { return }
        scrollOffset = newValue
        guard canAutoScroll else { return }
        let wrappedOffset = wrapped(newValue)
        guard abs(wrappedOffset - newValue) > 0.5 else { return }
        scrollOffset = wrappedOffset
        scrollPosition.scrollTo(y: wrappedOffset)
        lastTick = nil
    }

    private func scrollPhaseChanged(_ phase: ScrollPhase) {
        guard canAutoScroll else { return }
        let manualPhase = phase == .tracking || phase == .interacting || phase == .decelerating
        if manualPhase {
            resumeTask?.cancel()
            resumeTask = nil
            isUserScrolling = true
            lastTick = nil
        } else if isUserScrolling {
            resumeTask?.cancel()
            resumeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                isUserScrolling = false
                lastTick = nil
            }
        }
    }

    private func tick(_ date: Date) {
        guard canAutoScroll, !isUserScrolling else {
            lastTick = nil
            return
        }

        let timestamp = date.timeIntervalSinceReferenceDate
        guard let lastTick else {
            self.lastTick = timestamp
            return
        }

        let delta = min(max(timestamp - lastTick, 0), 0.1)
        self.lastTick = timestamp
        guard delta > 0 else { return }
        let nextOffset = wrapped(scrollOffset + speed * CGFloat(delta))
        scrollOffset = nextOffset
        scrollPosition.scrollTo(y: nextOffset)
    }

    private func reconcileAutoScrollState() {
        lastTick = nil
        if canAutoScroll {
            let wrappedOffset = wrapped(scrollOffset)
            guard abs(wrappedOffset - scrollOffset) > 0.5 else { return }
            scrollOffset = wrappedOffset
            scrollPosition.scrollTo(y: wrappedOffset)
        } else {
            resumeTask?.cancel()
            resumeTask = nil
            isUserScrolling = false
            let clampedOffset = clamped(scrollOffset)
            guard abs(clampedOffset - scrollOffset) > 0.5 else { return }
            scrollOffset = clampedOffset
            scrollPosition.scrollTo(y: clampedOffset)
        }
    }

    private func wrapped(_ offset: CGFloat) -> CGFloat {
        guard loopDistance > 1 else { return max(0, offset) }
        let remainder = offset.truncatingRemainder(dividingBy: loopDistance)
        return remainder >= 0 ? remainder : remainder + loopDistance
    }

    private func clamped(_ offset: CGFloat) -> CGFloat {
        let maxOffset = max(0, contentHeight - viewportHeight)
        return min(max(offset, 0), maxOffset)
    }
}
