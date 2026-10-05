// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import AppKit
import SwiftUI

// MARK: - Peek

extension Nook {
    /// Grows the compact pill into its peek region, showing ``peekContent`` below the slots,
    /// and returns once it has arrived. The ``state`` stays ``NookState/compact``.
    ///
    /// A hidden nook shows its compact pill first. Does nothing while the nook is expanded
    /// (it already shows more), when there is no ``peekContent``, or when the nook has no
    /// compact content to peek from. A peek started here lasts until ``endPeek()``, a
    /// transition away from compact, or ``peekContent`` going `nil`; the pointer leaving
    /// does not end it. Pass `nil` (the default) to let the nook pick its screen.
    public func peek(on screen: NSScreen? = nil) async {
        await runPeek(on: screen, byHover: false)?.value
    }

    /// Shrinks a peeking pill back to its compact slots, and returns once it has. Does nothing
    /// when the pill is not peeking.
    public func endPeek() async {
        await runEndPeek()?.value
    }

    /// Starts a peek as a tracked transition toward compact, so a newer transition supersedes
    /// it and a display change re-drives the surface to compact. `byHover` marks a peek the
    /// pointer leaving should end. `nil` when there is nothing to peek.
    @discardableResult
    func runPeek(on screen: NSScreen?, byHover: Bool) -> Task<Void, Never>? {
        guard peekContent != nil, state != .expanded,
            !(disableCompactLeading && disableCompactTrailing),
            let target = screen ?? windowController?.window?.screen ?? resolvedScreen
        else { return nil }
        return runTransition(toward: .compact) { [weak self] generation in
            guard let self else { return }
            if self.state != .compact || self.windowController?.window?.screen != target {
                await self._compact(on: target, skipHide: true, generation: generation)
                guard self.isCurrent(generation), !Task.isCancelled, self.state == .compact else { return }
            }
            // A host peek over a pointer's peek takes it over, so leaving no longer ends it;
            // the pointer arriving on a host's peek leaves it the host's.
            if !self.isPeeking {
                self.peekStartedByHover = byHover
            } else if !byHover {
                self.peekStartedByHover = false
            }
            guard !self.isPeeking else { return }
            withAnimation(self.effectivePeekAnimation) { self.isPeeking = true }
            try? await Task.sleep(for: self.conversionSettleDuration)
            let arrival = self.transitionConfiguration.peekContentTransition.delay
            if arrival > 0 { try? await Task.sleep(for: .seconds(arrival)) }
        }
    }

    /// Ends the peek as a tracked transition. `nil` when the pill is not peeking.
    @discardableResult
    func runEndPeek() -> Task<Void, Never>? {
        guard state == .compact, isPeeking else { return nil }
        return runTransition(toward: .compact) { [weak self] _ in
            guard let self, self.isPeeking else { return }
            withAnimation(self.effectivePeekAnimation) { self.isPeeking = false }
            self.peekStartedByHover = false
            try? await Task.sleep(for: self.conversionSettleDuration)
        }
    }
}

// MARK: - Hover intent

extension Nook {
    /// The pointer arrived on the chrome under an intent other than
    /// ``NookHoverIntent/standard``. On chrome that is already open it keeps it open, as
    /// always; on the compact pill it waits out the intent's delay, then peeks, opens, or
    /// does nothing.
    func hoverEntered() {
        guard let screen = windowController?.window?.screen ?? resolvedScreen else { return }
        guard state == .compact else {
            hoverExpand(on: screen)
            return
        }
        let intent = hoverIntent
        let action: NookHoverIntent.Action = intent.action == .peek && peekContent == nil ? .expand : intent.action
        guard action != .none else { return }
        // Already peeking (a host's peek): only the dwell is left to wait for.
        if action == .peek, isPeeking {
            scheduleDwellExpand(intent, on: screen)
            return
        }
        let delay = intent.delay(onBuiltInDisplay: screen.isBuiltIn)
        guard delay > .zero else {
            performHoverAction(action, intent: intent, on: screen)
            return
        }
        hoverIntentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.isHovering, self.state == .compact else { return }
            self.performHoverAction(action, intent: intent, on: screen)
        }
    }

    private func performHoverAction(_ action: NookHoverIntent.Action, intent: NookHoverIntent, on screen: NSScreen) {
        switch action {
            case .expand:
                hoverExpand(on: screen)
            case .peek:
                runPeek(on: screen, byHover: true)
                scheduleDwellExpand(intent, on: screen)
            case .none:
                break
        }
    }

    /// Opens the full nook once the pointer has rested on the peek for the intent's dwell.
    private func scheduleDwellExpand(_ intent: NookHoverIntent, on screen: NSScreen) {
        guard let dwell = intent.dwellToExpand else { return }
        hoverIntentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: dwell)
            guard let self, !Task.isCancelled, self.isHovering, self.state == .compact else { return }
            self.hoverExpand(on: screen)
        }
    }

    /// Opens the nook the way the pointer always has: no intermediate hide.
    func hoverExpand(on screen: NSScreen) {
        runTransition(toward: .expanded) { [weak self] generation in
            await self?._expand(on: screen, skipHide: true, generation: generation)
        }
    }

    func cancelHoverIntent() {
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
    }

    /// `true` when a click on the compact pill opens the nook: while it peeks, and whenever
    /// the hover intent is not the standard one, so a pill that no longer opens on hover can
    /// always be opened. With the standard intent the pointer has already opened the nook by
    /// the time it could click, so the pill takes no clicks and its slots behave as before.
    var opensOnClick: Bool {
        state == .compact && (isPeeking || hoverIntent != .standard)
    }

    /// A click on the compact pill or its peek.
    func handleChromeClick() {
        guard opensOnClick, let screen = windowController?.window?.screen ?? resolvedScreen else { return }
        cancelHoverIntent()
        hoverExpand(on: screen)
    }
}
