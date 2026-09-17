// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import AppKit
import SwiftUI

// Companion-surface bookkeeping for ``Nook``: one hover state across the chrome and its
// companions, and a panel tall enough to show them.
//
// Hover is the subtle part. The chrome collapses when the pointer leaves it, and a companion
// is outside the chrome, so without this the nook would collapse the moment the pointer moved
// onto its own action pill. The chrome and each companion therefore report hover separately
// and the nook is hovered while any of them is. The rules that keep that stable:
//
// - Only the chrome itself expands the nook on hover. A companion shown in the compact state
//   only keeps the surface hovered; if hovering it expanded the nook, a compact-only companion
//   would vanish under the pointer, which would then collapse the nook and show it again.
// - While companions are on screen a hover exit waits a short grace before collapsing, so the
//   pointer can cross the gap between two surfaces. Each companion also carries a transparent
//   hover bridge across its gap to the chrome, so a direct move never leaves at all.
// - SwiftUI does not report a hover exit for a view that disappears or stops being
//   hit-testable, so hover held by a companion that is no longer shown is dropped here.

extension Nook {
    /// Whether `companion` is shown while the chrome is in `state`, after any restriction its
    /// content applied.
    func isCompanionPresented(_ companion: NookCompanionSurface, in state: NookState) -> Bool {
        let restriction = companionVisibilityRestrictions[companion.id] ?? .both
        return companion.visibility.intersection(restriction).includes(state)
    }

    /// Ids of the companions shown while the chrome is in `state`.
    func presentedCompanionIDs(in state: NookState) -> Set<String> {
        Set(companions.lazy.filter { self.isCompanionPresented($0, in: state) }.map(\.id))
    }

    // MARK: Hover

    /// Hover reported by the chrome's own shape. Entering expands the nook as it always has;
    /// leaving collapses it unless the pointer is on, or on its way to, a companion.
    func updateChromeHoverState(_ hovering: Bool) {
        isChromeHovered = hovering
        if hovering {
            cancelCompanionHoverExit()
            updateHoverState(true)
        } else {
            resolveHoverExit()
        }
    }

    /// Hover reported by the companion `id`, including its hover bridge.
    func updateCompanionHoverState(id: String, hovering: Bool) {
        if hovering {
            guard presentedCompanionIDs(in: state).contains(id) else { return }
            hoveredCompanionIDs.insert(id)
            cancelCompanionHoverExit()
            markHoveredWithoutTransition()
        } else {
            guard hoveredCompanionIDs.remove(id) != nil else { return }
            resolveHoverExit()
        }
    }

    /// Records the visibility companion `id`'s content narrowed itself to (`nil` for none).
    func noteCompanionVisibilityRestriction(id: String, restriction: NookCompanionVisibility?) {
        guard companionVisibilityRestrictions[id] != restriction else { return }
        companionVisibilityRestrictions[id] = restriction
        dropHoverOfHiddenCompanions(in: state, stateChanged: false)
    }

    /// Acts on a pointer that is now off the chrome and every companion.
    private func resolveHoverExit() {
        guard !isChromeHovered, hoveredCompanionIDs.isEmpty else { return }
        // No companion on screen means no gap to cross: exit exactly as the chrome always
        // has, so a host without companions sees no change in timing.
        guard !presentedCompanionIDs(in: state).isEmpty else {
            cancelCompanionHoverExit()
            updateHoverState(false)
            return
        }
        guard companionHoverExitTask == nil else { return }
        let grace = companionHoverExitGrace
        companionHoverExitTask = Task { [weak self] in
            try? await Task.sleep(for: grace)
            guard let self, !Task.isCancelled else { return }
            self.companionHoverExitTask = nil
            guard !self.isChromeHovered, self.hoveredCompanionIDs.isEmpty else { return }
            self.updateHoverState(false)
        }
    }

    private func cancelCompanionHoverExit() {
        companionHoverExitTask?.cancel()
        companionHoverExitTask = nil
    }

    /// Marks the surface hovered without the hover-grow transition - see the rules above.
    /// The flag still matters: it is what counts the user as engaged and what defers a
    /// `.keepVisible` hide.
    private func markHoveredWithoutTransition() {
        guard state != .hidden, !isHovering else { return }
        setHoveringWithoutTransition(true)
        performHoverHapticIfEnabled()
    }

    /// Drops hover held by companions that are not shown in `state`.
    ///
    /// When the chrome itself just changed state, the pointer was over a companion that has
    /// now folded away, and the surface is simply no longer hovered: the flag is cleared
    /// directly, because a hover-exit transition here would race the one already running.
    /// When the companion vanished on its own - its content hid it, or it was removed - the
    /// pointer has been left over empty space, and that is a real hover exit.
    func dropHoverOfHiddenCompanions(in state: NookState, stateChanged: Bool) {
        let stale = hoveredCompanionIDs.subtracting(presentedCompanionIDs(in: state))
        guard !stale.isEmpty else { return }
        hoveredCompanionIDs.subtract(stale)
        guard !isChromeHovered, hoveredCompanionIDs.isEmpty else { return }
        if stateChanged {
            cancelCompanionHoverExit()
            if isHovering { setHoveringWithoutTransition(false) }
        } else {
            resolveHoverExit()
        }
    }

    /// Forgets every hover source. Used when the views that report hover are torn down.
    func resetHoverSources() {
        cancelCompanionHoverExit()
        isChromeHovered = false
        hoveredCompanionIDs.removeAll()
    }

    /// Keeps companion hover in step with chrome state changes. `$state` publishes before the
    /// new value is stored, so the new state is passed along rather than read back.
    func observeStateForCompanions() {
        $state
            .removeDuplicates()
            .sink { [weak self] newState in
                self?.dropHoverOfHiddenCompanions(in: newState, stateChanged: true)
            }
            .store(in: &cancellables)
    }

    /// Reconciles bookkeeping after ``companions`` is replaced.
    func companionsDidChange() {
        let ids = Set(companions.map(\.id))
        companionVisibilityRestrictions = companionVisibilityRestrictions.filter { ids.contains($0.key) }
        companionExtents = companionExtents.filter { ids.contains($0.key) }
        dropHoverOfHiddenCompanions(in: state, stateChanged: false)
    }

    // MARK: Panel size

    /// Records how far down the panel companion `id` reaches, and grows the panel if it no
    /// longer fits.
    func noteCompanionExtent(id: String, maxY: CGFloat) {
        guard companions.contains(where: { $0.id == id }) else { return }
        companionExtents[id] = maxY
        guard !isPanelGrowthScheduled else { return }
        isPanelGrowthScheduled = true
        // Extents arrive from inside a SwiftUI geometry pass, and resizing the window there
        // would re-enter layout. Resize on the next main-actor turn instead.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPanelGrowthScheduled = false
            self.growPanelToFitCompanions()
        }
    }

    /// Grows the panel downward, top edge pinned, until every companion fits.
    ///
    /// The panel starts as the top half of the screen, which fits the chrome but not always a
    /// companion hanging below a tall expanded surface. It only grows, never shrinks, for the
    /// life of the window - a panel rebuild starts from half height again - so a companion
    /// folding away never makes the window jump.
    func growPanelToFitCompanions() {
        guard let window = windowController?.window,
            let screen = window.screen ?? resolvedScreen,
            let extent = companionExtents.values.max()
        else { return }
        let height = Self.panelHeight(
            fitting: extent,
            currentHeight: window.frame.height,
            screenHeight: screen.frame.height
        )
        guard height > window.frame.height else { return }
        var frame = window.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }

    /// Room left below the lowest companion, so its fold-in blur and a spring's overshoot
    /// are not cut off by the window edge.
    static var panelGrowthMargin: CGFloat { 24 }

    /// The panel height that fits content reaching down to `extent`: never shorter than the
    /// panel already is, never taller than the screen.
    static func panelHeight(fitting extent: CGFloat, currentHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let needed = (extent + panelGrowthMargin).rounded(.up)
        return min(max(currentHeight, needed), max(currentHeight, screenHeight))
    }
}
