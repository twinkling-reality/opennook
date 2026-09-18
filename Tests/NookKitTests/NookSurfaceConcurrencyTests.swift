// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import AppKit
import SwiftUI
import XCTest

@testable import NookSurface

/// Coverage for the NookSurface concurrency fixes: the explicit drag-session state
/// machine (robust against AppKit's uncoordinated callbacks) and the hide-vs-expand
/// transition supersession (hide now runs fully inside the generation system).
///
/// These exercise `Nook`'s internal model without depending on a real display: the
/// drag-session and generation logic is pure state, and `nookPanelDraggingEntered`
/// only spawns a transition when a screen resolves - with no screen attached the
/// session bookkeeping still runs and is what we assert on.
@MainActor
final class NookSurfaceConcurrencyTests: XCTestCase {

    private func makeNook() -> Nook<Text, EmptyView, EmptyView> {
        Nook(expanded: { Text("x") })
    }

    /// Poll until `condition` is true. Fixed post-`Task.sleep` margins flake on CI when
    /// the full suite runs in parallel and the cooperative scheduler defers grace tasks.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: pollInterval)
        }
        XCTFail("condition not met within \(timeout)", file: file, line: line)
    }

    // MARK: - BUG 2: drag-session state machine

    /// A fresh enter snapshots the current state; the session reports active.
    func testFirstDragEnterSnapshotsStateAndGoesActive() {
        let nook = makeNook()
        XCTAssertEqual(nook.dragSession, .idle)
        XCTAssertFalse(nook.isDragInFlight)

        _ = nook.nookPanelDraggingEntered([URL(fileURLWithPath: "/tmp/a")])

        XCTAssertEqual(nook.dragSession, .active(stateBeforeEntry: .hidden))
        XCTAssertTrue(nook.isDragInFlight)
    }

    /// Every `draggingUpdated` forwards as another enter. Repeated enters must keep the
    /// *original* snapshot - they are idempotent no-ops on session state.
    func testRepeatedDragEntersPreserveOriginalSnapshot() {
        let nook = makeNook()
        let url = URL(fileURLWithPath: "/tmp/a")

        _ = nook.nookPanelDraggingEntered([url])
        let afterFirst = nook.dragSession
        _ = nook.nookPanelDraggingEntered([url])
        _ = nook.nookPanelDraggingEntered([url])

        XCTAssertEqual(nook.dragSession, afterFirst)
        XCTAssertEqual(nook.dragSession, .active(stateBeforeEntry: .hidden))
    }

    /// AppKit can deliver `draggingExited` *then* `draggingEnded` for one session - both
    /// route through `nookPanelDraggingExited`. The second call must be an idempotent
    /// no-op: the snapshot was consumed by the first, so the session stays idle and the
    /// prior state is not restored twice.
    func testDuplicateExitIsIdempotent() {
        let nook = makeNook()
        _ = nook.nookPanelDraggingEntered([URL(fileURLWithPath: "/tmp/a")])
        XCTAssertTrue(nook.isDragInFlight)

        nook.nookPanelDraggingExited()
        XCTAssertEqual(nook.dragSession, .idle)
        XCTAssertFalse(nook.isDragInFlight)

        // Out-of-order / duplicate end callback - must not corrupt state.
        nook.nookPanelDraggingExited()
        XCTAssertEqual(nook.dragSession, .idle)
        XCTAssertFalse(nook.isDragInFlight)
    }

    /// An exit with no preceding enter (stray callback) must be a harmless no-op.
    func testExitWithoutEnterIsNoOp() {
        let nook = makeNook()
        nook.nookPanelDraggingExited()
        XCTAssertEqual(nook.dragSession, .idle)
        XCTAssertFalse(nook.isDragInFlight)
    }

    /// A drop ends the session exactly once; a trailing exit/end AppKit delivers around
    /// the drop cannot re-trigger a restore.
    func testDropEndsSessionAndTrailingExitIsNoOp() {
        let nook = makeNook()
        var dropped: [URL] = []
        nook.onFileDrop = { urls in
            dropped = urls
            return true
        }

        _ = nook.nookPanelDraggingEntered([URL(fileURLWithPath: "/tmp/a")])
        let accepted = nook.nookPanelPerformDrop([URL(fileURLWithPath: "/tmp/a")])

        XCTAssertTrue(accepted)
        XCTAssertEqual(dropped.count, 1)
        XCTAssertEqual(nook.dragSession, .idle)
        XCTAssertFalse(nook.isDragInFlight)

        // AppKit's post-drop exit/end - idempotent no-op.
        nook.nookPanelDraggingExited()
        XCTAssertEqual(nook.dragSession, .idle)
    }

    /// A drop with no preceding enter still ends cleanly and does not wedge the session.
    func testDropWithoutEnterIsHandledCleanly() {
        let nook = makeNook()
        nook.onFileDrop = { _ in false }
        let accepted = nook.nookPanelPerformDrop([URL(fileURLWithPath: "/tmp/a")])
        XCTAssertFalse(accepted)
        XCTAssertEqual(nook.dragSession, .idle)
        XCTAssertFalse(nook.isDragInFlight)
    }

    /// `isDragInFlight` is a strict mirror of `dragSession` - observers of the published
    /// bool see exactly the active/idle of the authoritative enum.
    func testIsDragInFlightMirrorsSession() {
        let nook = makeNook()
        XCTAssertFalse(nook.isDragInFlight)

        nook.dragSession = .active(stateBeforeEntry: .compact)
        XCTAssertTrue(nook.isDragInFlight)

        nook.dragSession = .idle
        XCTAssertFalse(nook.isDragInFlight)
    }

    // MARK: - BUG 1: hide-vs-expand supersession

    /// `runTransition` claims a fresh generation synchronously and invalidates the prior
    /// one. A generation a transition's body captured is no longer `isCurrent` once a
    /// newer transition has been claimed - this is the signal an in-flight `_hide`
    /// re-checks to bail out of its teardown rather than deinit a window the newer
    /// transition owns.
    func testNewerTransitionSupersedesAnEarlierGeneration() async {
        let nook = makeNook()

        // A hide-like transition captures its generation, then yields so a newer
        // transition can be claimed while it is "in flight".
        var hideStillCurrentAfterSupersede: Bool?
        let hideTask = nook.runTransition { generation in
            // Cooperatively yield: lets the second `runTransition` below claim a
            // newer generation, mimicking an expand racing this hide's teardown.
            await Task.yield()
            hideStillCurrentAfterSupersede = nook.isCurrent(generation)
        }

        var expandGenerationIsCurrent: Bool?
        let expandTask = nook.runTransition { generation in
            expandGenerationIsCurrent = nook.isCurrent(generation)
        }

        await hideTask.value
        await expandTask.value

        // The hide observed itself superseded after the yield - its teardown bails.
        XCTAssertEqual(hideStillCurrentAfterSupersede, false)
        // The expand is the most recent claim and owns the surface.
        XCTAssertEqual(expandGenerationIsCurrent, true)
    }

    /// `supersedeInFlightTransition` - used by the synchronous window-swap paths
    /// (`presentation.didSet`, screen-parameter observer) - invalidates any in-flight
    /// generation so a mid-flight `_expand`/`_compact`/`_hide` bails when the window is
    /// rebuilt under it.
    func testWindowSwapSupersedesInFlightTransition() async {
        let nook = makeNook()
        var stillCurrentAfterSwap: Bool?

        let task = nook.runTransition { generation in
            await Task.yield()
            stillCurrentAfterSwap = nook.isCurrent(generation)
        }
        // Swap the window out from under the in-flight transition.
        nook.supersedeInFlightTransition()
        await task.value

        XCTAssertEqual(stillCurrentAfterSwap, false)
    }

    /// An awaited `hide()` always resolves - it now routes through `runTransition` like
    /// `expand`/`compact`, so the awaited task completes rather than wedging on a dropped
    /// continuation. With no window to tear down it is effectively a fast no-op.
    func testAwaitedHideOnHiddenNookResolves() async {
        let nook = makeNook()
        XCTAssertEqual(nook.state, .hidden)
        // Must not hang: `_hide` returns immediately when already hidden.
        await nook.hide()
        XCTAssertEqual(nook.state, .hidden)
    }

    // MARK: - Peripheral feedback lifecycle

    private func feedbackEvent(duration: TimeInterval, repeats: Bool) -> NookFeedbackEvent {
        NookFeedbackEvent(
            id: UUID(),
            startedAt: Date(),
            effect: .shimmer,
            duration: duration,
            tint: .white,
            respectsReduceMotion: true,
            repeats: repeats
        )
    }

    /// A one-shot cue must auto-clear once it has finished, otherwise the overlay's
    /// `TimelineView(.animation)` keeps ticking at 60fps forever rendering `Color.clear`.
    func testOneShotFeedbackClearsAfterDuration() async {
        let nook = makeNook()
        nook.setFeedbackEvent(feedbackEvent(duration: 0.05, repeats: false))
        XCTAssertNotNil(nook.feedbackEvent)

        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(nook.feedbackEvent, "finished one-shot cue must clear so the timeline tears down")
    }

    /// A repeating cue is meant to nag until acknowledged, so it must persist past its
    /// per-cycle duration.
    func testRepeatingFeedbackPersists() async {
        let nook = makeNook()
        nook.setFeedbackEvent(feedbackEvent(duration: 0.05, repeats: true))

        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNotNil(nook.feedbackEvent, "repeating cue must keep running until acknowledged")
    }

    /// A new cue cancels the prior cue's pending clear, so the first event's timer can't
    /// nil out the replacement.
    func testNewFeedbackSupersedesPriorClear() async {
        let nook = makeNook()
        nook.setFeedbackEvent(feedbackEvent(duration: 0.05, repeats: false))
        let second = feedbackEvent(duration: 1.0, repeats: false)
        nook.setFeedbackEvent(second)

        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(nook.feedbackEvent?.id, second.id, "the first cue's clear must not nil the second")
    }

    // MARK: - Layout-resize grace

    func testLayoutGraceRequiresExpandedState() {
        let nook = makeNook()
        nook.noteExpandedContentSizeChange()
        XCTAssertFalse(nook.isLayoutGraceActive)
    }

    func testLayoutGraceExpiresAfterConfiguredDuration() async {
        let nook = makeNook()
        nook.transitionConfiguration.layoutGraceDuration = 0.15
        nook.beginLayoutGrace()
        XCTAssertTrue(nook.isLayoutGraceActive)
        await waitUntil { !nook.isLayoutGraceActive }
        XCTAssertFalse(nook.isLayoutGraceActive)
    }

    func testLayoutGraceRefreshesOnRepeatedActivation() async {
        let nook = makeNook()
        nook.transitionConfiguration.layoutGraceDuration = 0.2
        nook.beginLayoutGrace()

        // Refresh far faster than the grace duration, for longer than a single,
        // un-refreshed grace (0.2s) would last. Each activation resets the timer, so grace
        // must stay continuously active across the whole window - which is only possible
        // if a refresh extends it. Asserting across the window (rather than at one
        // knife-edge instant) is robust to CI `Task.sleep` overruns: a single 40ms refresh
        // gap would have to overrun ~5x to let the 0.2s grace lapse between refreshes.
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .milliseconds(450) {
            nook.beginLayoutGrace()
            XCTAssertTrue(nook.isLayoutGraceActive, "refresh should keep grace active")
            try? await Task.sleep(for: .milliseconds(40))
        }

        // Still active after ~2x the configured duration - proof the repeated activation
        // refreshed the window rather than letting the first grace expire.
        XCTAssertTrue(nook.isLayoutGraceActive, "repeated refresh should extend grace")

        // Once refreshing stops, it expires.
        await waitUntil { !nook.isLayoutGraceActive }
        XCTAssertFalse(nook.isLayoutGraceActive)
    }

    /// Regression: the public designated init (the one `AppCoordinator` builds its surface
    /// with) never subscribed the state observer that ends layout grace, so a collapse left
    /// `isLayoutGraceActive` set until its timer ran out - holding the coordinator's
    /// `isUserEngaged` true after the user was gone. The grace here is far longer than the
    /// poll timeout, so only the observer can clear it in time.
    func testCompactEndsLayoutGraceOnNookBuiltWithPublicInit() async throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No main display attached")
        }

        // `hoverBehavior: []` keeps `hide()` from waiting on a pointer that happens to be
        // over the notch; compact content keeps `compact` from collapsing to a hide.
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") }, compactLeading: { Text("L") })
        nook.transitionConfiguration.layoutGraceDuration = 30
        nook.transitionConfiguration.animationDuration = 0.05
        await nook.expand(on: screen)
        XCTAssertEqual(nook.state, .expanded)

        nook.beginLayoutGrace()
        XCTAssertTrue(nook.isLayoutGraceActive)

        await nook.compact(on: screen)
        XCTAssertEqual(nook.state, .compact)
        await waitUntil { !nook.isLayoutGraceActive }
        XCTAssertFalse(nook.isLayoutGraceActive, "leaving the expanded state should end layout grace")

        await nook.hide()
    }

    /// Hover-exit auto-compact must not run while layout grace is active - the common
    /// failure when expanded content shrinks under a stationary cursor.
    func testLayoutGraceSuppressesHoverExitCompact() async throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No main display attached")
        }

        let nook = Nook(expanded: { Text("x") }, compactLeading: { Text("L") })
        nook.transitionConfiguration.layoutGraceDuration = 0.2
        nook.transitionConfiguration.animationDuration = 0.05
        await nook.expand(on: screen)
        XCTAssertEqual(nook.state, .expanded)

        var compactCount = 0
        nook.onCompact = { compactCount += 1 }

        nook.updateHoverState(true)
        nook.beginLayoutGrace()
        nook.updateHoverState(false)
        await Task.yield()
        XCTAssertEqual(compactCount, 0, "layout grace should block hover-exit compact")

        await waitUntil { !nook.isLayoutGraceActive }
        XCTAssertFalse(nook.isLayoutGraceActive)
        await waitUntil { compactCount >= 1 }
        XCTAssertEqual(compactCount, 1, "the exit layout grace held back should collapse once the grace ends")
        XCTAssertEqual(nook.state, .compact)
    }

    // MARK: - Hover exits a hold deferred

    /// A nook expanded on the main display with compact content, fast transitions, and an
    /// `onCompact` counter.
    private func makeExpandedNook(on screen: NSScreen) async -> (Nook<Text, Text, EmptyView>, () -> Int) {
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") }, compactLeading: { Text("L") })
        nook.transitionConfiguration.animationDuration = 0.05
        await nook.expand(on: screen)
        var compactCount = 0
        nook.onCompact = { compactCount += 1 }
        return (nook, { compactCount })
    }

    /// Regression: a pointer that left while a hold kept the nook open left it open for good,
    /// until the pointer came back and left again. Releasing the hold now collapses it.
    func testPointerThatLeftDuringAHoldCollapsesWhenTheHoldEnds() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        let (nook, compactCount) = await makeExpandedNook(on: screen)

        nook.staysExpandedOnHoverExit = true
        nook.updateHoverState(true)
        nook.updateHoverState(false)
        await Task.yield()
        XCTAssertEqual(compactCount(), 0, "the hold keeps the nook open while it lasts")
        XCTAssertTrue(nook.hasDeferredHoverExit)

        nook.staysExpandedOnHoverExit = false
        await waitUntil { nook.state == .compact }
        XCTAssertEqual(compactCount(), 1)
        XCTAssertFalse(nook.hasDeferredHoverExit)
        await nook.hide()
    }

    /// A nook the pointer never left - opened from the keyboard, say - stays open when a hold
    /// ends, exactly as before.
    func testHoldEndingWithoutAHoverExitKeepsTheNookOpen() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        let (nook, compactCount) = await makeExpandedNook(on: screen)

        nook.staysExpandedOnHoverExit = true
        nook.staysExpandedOnHoverExit = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(nook.state, .expanded)
        XCTAssertEqual(compactCount(), 0)
        await nook.hide()
    }

    /// The pointer coming back before the hold ends cancels the collapse it owed.
    func testPointerReturningBeforeTheHoldEndsCancelsTheOwedCollapse() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        let (nook, compactCount) = await makeExpandedNook(on: screen)

        nook.staysExpandedOnHoverExit = true
        nook.updateHoverState(true)
        nook.updateHoverState(false)
        nook.updateHoverState(true)
        XCTAssertFalse(nook.hasDeferredHoverExit)

        nook.staysExpandedOnHoverExit = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(nook.state, .expanded, "the pointer is over the nook, so nothing collapses it")
        XCTAssertEqual(compactCount(), 0)
        await nook.hide()
    }

    /// With two holds at once, the owed collapse waits for the last one to end.
    func testOwedCollapseWaitsForEveryHoldToEnd() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        let (nook, compactCount) = await makeExpandedNook(on: screen)
        nook.transitionConfiguration.layoutGraceDuration = 30

        nook.staysExpandedOnHoverExit = true
        nook.beginLayoutGrace()
        nook.updateHoverState(true)
        nook.updateHoverState(false)

        nook.staysExpandedOnHoverExit = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(nook.state, .expanded, "layout grace still holds the nook open")
        XCTAssertEqual(compactCount(), 0)

        nook.endLayoutGrace()
        await waitUntil { nook.state == .compact }
        XCTAssertEqual(compactCount(), 1)
        await nook.hide()
    }

    /// An owed collapse is forgotten when the nook collapses some other way first, so it cannot
    /// fire later into a nook that was opened again.
    func testCollapsingForgetsTheOwedCollapse() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        let (nook, compactCount) = await makeExpandedNook(on: screen)

        nook.staysExpandedOnHoverExit = true
        nook.updateHoverState(true)
        nook.updateHoverState(false)
        await nook.compact(on: screen)
        XCTAssertFalse(nook.hasDeferredHoverExit)
        await nook.expand(on: screen)

        nook.staysExpandedOnHoverExit = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(nook.state, .expanded)
        XCTAssertEqual(compactCount(), 1, "only the explicit compact")
        await nook.hide()
    }

    // MARK: - Keyboard focus

    /// A click or a focus on an editable text input counts as typing, found from the input
    /// itself or a view inside it; labels, read-only text, and plain views do not.
    func testOnlyEditableTextInputsAcceptTyping() {
        XCTAssertTrue(NookPanel.acceptsTyping(NSTextField()))
        XCTAssertFalse(NookPanel.acceptsTyping(NSTextField(labelWithString: "Label")))

        let editor = NSTextView()
        XCTAssertTrue(NookPanel.acceptsTyping(editor))
        editor.isEditable = false
        XCTAssertFalse(NookPanel.acceptsTyping(editor), "read-only text is selectable, not typed into")

        let field = NSTextField()
        let inner = NSView()
        field.addSubview(inner)
        XCTAssertTrue(NookPanel.acceptsTyping(inner), "a click on a view inside a field is a click on the field")

        XCTAssertFalse(NookPanel.acceptsTyping(NSView()))
        XCTAssertFalse(NookPanel.acceptsTyping(nil))
    }

    /// A hidden chrome has no panel to give the keyboard to.
    func testHiddenChromeCannotTakeTheKeyboard() {
        let nook = makeNook()
        XCTAssertFalse(nook.takeKeyboardFocus())
        XCTAssertFalse(nook.hasKeyboardFocus)
        XCTAssertNil(nook.window)
        nook.releaseKeyboardFocus()  // nothing to release; must not crash
    }

    /// An expanded chrome's panel takes the keyboard, and collapsing hands it back.
    func testExpandedChromeTakesTheKeyboardAndCollapsingReleasesIt() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") }, compactLeading: { Text("L") })
        nook.transitionConfiguration.animationDuration = 0.05
        await nook.expand(on: screen)
        XCTAssertNotNil(nook.window)
        XCTAssertEqual(nook.window?.accessibilityIdentifier(), "opennook.panel")

        guard nook.takeKeyboardFocus() else {
            await nook.hide()
            throw XCTSkip("This test process cannot make a window key")
        }
        XCTAssertTrue(nook.hasKeyboardFocus)

        await nook.compact(on: screen)
        await waitUntil { !nook.hasKeyboardFocus }
        XCTAssertFalse(nook.hasKeyboardFocus, "a collapsed chrome does not keep the keyboard")
        await nook.hide()
    }

    /// Companions inherit the chrome's backdrop unless the chrome sets one for them.
    func testCompanionsInheritTheirOwnBackdropWhenSet() {
        let nook = makeNook()
        nook.backdrop = .solid(.red)
        XCTAssertEqual(nook.inheritedCompanionBackdrop, .solid(.red))
        nook.companionBackdrop = .solid(.blue)
        XCTAssertEqual(nook.inheritedCompanionBackdrop, .solid(.blue))
        XCTAssertEqual(
            NookCompanionBackdrop.inherit.resolved(inheriting: nook.inheritedCompanionBackdrop),
            .solid(.blue)
        )
    }
}
