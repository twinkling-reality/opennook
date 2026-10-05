// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookKit
import XCTest

@testable import NookComponents

/// A `NookSurfacePresenting` stand-in - no real window, fully controllable engagement.
@MainActor
private final class FakePresenter: NookSurfacePresenting {
    private let engagement = CurrentValueSubject<Bool, Never>(false)

    private(set) var beginCount = 0
    private(set) var endCount = 0
    private var nextToken = 0

    /// When > 0, the next N `beginTransientPresentation(_:)` calls reject the takeover -
    /// simulating the user grabbing the surface in the pre-takeover race window.
    var rejectNextBegins = 0

    var isUserEngaged: Bool { engagement.value }

    var userEngagementChanges: AnyPublisher<Bool, Never> {
        engagement.eraseToAnyPublisher()
    }

    var activeModuleID = "test.module"

    func beginTransientPresentation(_ claim: NookSurfaceClaim) async -> NookSurfaceToken? {
        beginCount += 1
        if rejectNextBegins > 0 {
            rejectNextBegins -= 1
            return nil
        }
        guard !isUserEngaged else { return nil }
        defer { nextToken += 1 }
        return NookSurfaceToken(value: nextToken)
    }

    func endTransientPresentation(_ token: NookSurfaceToken) async { endCount += 1 }

    /// When `true`, the presenter schedules ends the way `AppCoordinator` does; when `false`
    /// (the default), it is a presenter written before scheduled ends existed.
    var schedulesEnds = false
    private(set) var scheduledEnds: [Duration] = []

    func endTransientPresentation(_ token: NookSurfaceToken, after delay: Duration) async -> Bool {
        guard schedulesEnds else { return false }
        scheduledEnds.append(delay)
        return true
    }

    func setEngaged(_ value: Bool) { engagement.send(value) }
}

final class NookActivityQueueTests: XCTestCase {
    /// Poll until `condition` is true. Fixed post-`Task.sleep` margins flake on CI when
    /// the full suite runs in parallel and the cooperative scheduler defers drain tasks.
    @MainActor
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

    /// A queue whose `dwell` waits resolve instantly, for deterministic draining.
    @MainActor
    private func instantQueue() -> NookActivityQueue {
        NookActivityQueue(sleep: { _ in })
    }

    /// With a presenter that can move a claim's end, consecutive cards share one claim, so the
    /// nook stays open between them.
    @MainActor
    func testConsecutiveCardsShareOneClaim() async {
        let queue = instantQueue()
        let presenter = FakePresenter()
        presenter.schedulesEnds = true
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        queue.enqueue(NookActivity(title: "B"))
        queue.enqueue(NookActivity(title: "C"))
        await queue.drainTask?.value

        XCTAssertEqual(presenter.beginCount, 1, "one claim for the run of cards")
        XCTAssertEqual(presenter.endCount, 1)
        XCTAssertEqual(presenter.scheduledEnds.count, 2, "the end moved once per chained card")
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    /// A card with the same coalescing key as the one on screen updates it in place: the text
    /// changes, the card keeps its id, and nothing more is queued.
    @MainActor
    func testACardWithTheSameKeyUpdatesTheOneOnScreen() async {
        let queue = NookActivityQueue(sleep: { _ in try? await Task.sleep(for: .seconds(1)) })
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        let first = NookActivity(coalescingKey: "download", title: "Downloading 40%")
        queue.enqueue(first)
        await waitUntil { queue.current != nil }

        queue.enqueue(NookActivity(coalescingKey: "download", title: "Downloading 80%"))
        XCTAssertEqual(queue.current?.title, "Downloading 80%")
        XCTAssertEqual(queue.current?.id, first.id, "the card stays; only its content changes")
        XCTAssertTrue(queue.pending.isEmpty)

        await queue.drainTask?.value
        XCTAssertEqual(presenter.beginCount, 1)
    }

    @MainActor
    func testDrainsEveryEnqueuedActivity() async {
        let queue = instantQueue()
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        queue.enqueue(NookActivity(title: "B"))
        queue.enqueue(NookActivity(title: "C"))
        await queue.drainTask?.value

        XCTAssertEqual(presenter.beginCount, 3)
        XCTAssertEqual(presenter.endCount, 3)
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    @MainActor
    func testPresentsHighestPriorityFirst() async {
        let queue = instantQueue()
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        var presented: [String] = []
        let cancellable = queue.$current
            .compactMap { $0?.title }
            .sink { presented.append($0) }

        queue.enqueue(NookActivity(priority: .low, title: "Low"))
        queue.enqueue(NookActivity(priority: .high, title: "High"))
        queue.enqueue(NookActivity(priority: .normal, title: "Normal"))
        await queue.drainTask?.value
        cancellable.cancel()

        XCTAssertEqual(presented, ["High", "Normal", "Low"])
    }

    @MainActor
    func testCoalescingKeyKeepsLatest() {
        // No presenter bound - the queue holds activities without draining.
        let queue = instantQueue()

        queue.enqueue(NookActivity(coalescingKey: "sync", title: "First"))
        queue.enqueue(NookActivity(coalescingKey: "sync", title: "Second"))

        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.title, "Second")
    }

    @MainActor
    func testSuspendStopsDrainingAndResumeContinues() async {
        let queue = instantQueue()
        let presenter = FakePresenter()

        queue.suspend()
        queue.bind(to: presenter)
        queue.enqueue(NookActivity(title: "A"))
        XCTAssertEqual(presenter.beginCount, 0, "a suspended queue presents nothing")

        queue.resume()
        await queue.drainTask?.value
        XCTAssertEqual(presenter.beginCount, 1)
    }

    /// Regression: suspending the queue *while the user is engaged* must let the drain
    /// task wind down cooperatively, and after `resume()` the queue must drive cleanly
    /// to completion once the user disengages.
    @MainActor
    func testSuspendWhileEngagedThenResumeRecovers() async throws {
        let queue = instantQueue()
        let presenter = FakePresenter()
        presenter.setEngaged(true)
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        // Let the drain loop reach its engaged-yield point.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(presenter.beginCount, 0, "must not present while the user is engaged")

        // Cooperative suspend: the drain task is NOT cancelled - it exits on its own
        // when the engagement-wait next polls (≤200ms) or when the current dwell ends.
        queue.suspend()
        await queue.drainTask?.value
        XCTAssertNil(queue.drainTask, "drain task cleared itself after the cooperative exit")

        // Resume while still engaged - a fresh drain task spawns and re-parks in the
        // engagement wait. Disengage, then drain to completion.
        queue.resume()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(presenter.beginCount, 0, "still yields after resume while engaged")

        presenter.setEngaged(false)
        await queue.drainTask?.value
        XCTAssertEqual(presenter.beginCount, 1, "queue recovers and drains after suspend-while-engaged")
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(queue.current)
    }

    /// Regression: a `suspend()` issued *while an activity is dwelling on screen* must
    /// let that dwell finish and the claim release normally - not cancel mid-dwell and
    /// strand the arbiter token. The contract advertised by `suspend()` says the
    /// current activity finishes; this pins it.
    @MainActor
    func testSuspendDuringDwellLetsCurrentActivityFinish() async throws {
        // A real (but short) dwell so suspend() can land while one is on screen.
        let queue = NookActivityQueue(sleep: { _ in try? await Task.sleep(for: .milliseconds(150)) })
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        // Wait until the claim is granted and the activity is dwelling on screen.
        await waitUntil { presenter.beginCount == 1 && queue.current != nil }
        XCTAssertEqual(presenter.endCount, 0, "still dwelling")

        queue.suspend()
        // suspend() must NOT cancel the drain task - the current dwell must complete.
        await queue.drainTask?.value

        XCTAssertEqual(presenter.endCount, 1, "in-flight activity released its claim normally")
        XCTAssertNil(queue.current, "current cleared after the dwell finished")
        XCTAssertNil(queue.drainTask)
    }

    /// Regression: `suspend()` then `resume()` (without a `quiesce()` in between) must
    /// not leak a stranded arbiter claim. Before the cooperative-suspend fix, a hard
    /// cancel mid-dwell skipped `endTransientPresentation` and only the next
    /// `quiesce()` released the token; under repeated suspend/resume cycles the claim
    /// counter drifted by one per cycle.
    @MainActor
    func testSuspendResumeCycleDoesNotStrandClaim() async throws {
        let queue = NookActivityQueue(sleep: { _ in try? await Task.sleep(for: .milliseconds(80)) })
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        try await Task.sleep(for: .milliseconds(20))  // claim granted, dwell parking
        queue.suspend()
        await queue.drainTask?.value
        XCTAssertEqual(presenter.beginCount, presenter.endCount, "begin/end balanced after suspend")

        queue.resume()
        queue.enqueue(NookActivity(title: "B"))
        await queue.drainTask?.value
        XCTAssertEqual(presenter.beginCount, 2)
        XCTAssertEqual(presenter.endCount, 2, "no claim was stranded across the suspend/resume")
    }

    /// Regression: a rejected takeover requeues at the *end* of its priority class, not
    /// the front. A peer already waiting at the same priority must still go first.
    @MainActor
    func testRequeuePreservesFIFOWithinPriority() async {
        let queue = instantQueue()
        let presenter = FakePresenter()
        // Reject only the *first* takeover so we can pin the requeue position.
        presenter.rejectNextBegins = 1
        queue.bind(to: presenter)

        var presented: [String] = []
        let cancellable = queue.$current
            .compactMap { $0?.title }
            .sink { presented.append($0) }

        // A is enqueued first and is the one whose first takeover gets rejected.
        // B is enqueued *before* the retry - at the same priority. FIFO-within-priority
        // means B presents before A's retry.
        queue.enqueue(NookActivity(priority: .normal, title: "A"))
        queue.enqueue(NookActivity(priority: .normal, title: "B"))
        await queue.drainTask?.value
        cancellable.cancel()

        XCTAssertEqual(presented, ["B", "A"], "B (waiting same-priority peer) goes before A's retry")
        XCTAssertEqual(presenter.beginCount, 3, "A rejected once, A retried, B presented")
        XCTAssertEqual(presenter.endCount, 2, "exactly two presentations completed")
    }

    /// Regression: if the user grabs the surface in the window between the engagement
    /// wait and the takeover, `beginTransientPresentation()` returns `false`. The queue
    /// must re-queue the activity and retry, not drop it or render a card over a
    /// surface it never took.
    @MainActor
    func testRequeuesActivityWhenTakeoverRejected() async {
        let queue = instantQueue()
        let presenter = FakePresenter()
        presenter.rejectNextBegins = 1
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        await queue.drainTask?.value

        XCTAssertEqual(presenter.beginCount, 2, "first takeover rejected, retried once")
        XCTAssertEqual(presenter.endCount, 1, "presented exactly once, after the retry")
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(queue.current)
    }

    /// `quiesce()` must join the drain task and release any in-flight surface claim, so
    /// the owning module is safe to switch away once it returns.
    @MainActor
    func testQuiesceJoinsDrainAndReleasesToken() async {
        // A non-instant sleep so an activity is genuinely on screen when quiesce lands.
        let queue = NookActivityQueue(sleep: { _ in try? await Task.sleep(for: .seconds(10)) })
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        // Let the drain loop grant a claim and park in the (long) dwell.
        await waitUntil { presenter.beginCount == 1 && queue.current != nil }
        XCTAssertEqual(presenter.endCount, 0, "still dwelling — not yet released")

        await queue.quiesce()

        XCTAssertNil(queue.drainTask, "drain task joined and cleared")
        XCTAssertEqual(presenter.endCount, 1, "the in-flight claim was released")
        XCTAssertNil(queue.current, "current cleared")
        XCTAssertTrue(queue.isSuspended)
    }

    /// `quiesce()` is idempotent and safe on an idle queue - a second call is a no-op.
    @MainActor
    func testQuiesceIsIdempotent() async {
        let queue = instantQueue()
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        await queue.drainTask?.value

        await queue.quiesce()
        let endsAfterFirst = presenter.endCount
        await queue.quiesce()
        XCTAssertEqual(presenter.endCount, endsAfterFirst, "second quiesce releases nothing")
        XCTAssertNil(queue.drainTask)
    }

    /// `quiesce()` on a queue that never started draining (no in-flight token) is a
    /// clean no-op that still leaves the queue suspended.
    @MainActor
    func testQuiesceWithNothingInFlight() async {
        let queue = instantQueue()
        let presenter = FakePresenter()
        queue.bind(to: presenter)

        await queue.quiesce()

        XCTAssertEqual(presenter.endCount, 0)
        XCTAssertNil(queue.drainTask)
        XCTAssertTrue(queue.isSuspended)
    }

    @MainActor
    func testYieldsWhileUserEngaged() async throws {
        let queue = instantQueue()
        let presenter = FakePresenter()
        presenter.setEngaged(true)
        queue.bind(to: presenter)

        queue.enqueue(NookActivity(title: "A"))
        // Give the drain loop time to reach its yield point.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(presenter.beginCount, 0, "must not present while the user is engaged")

        presenter.setEngaged(false)
        await queue.drainTask?.value
        XCTAssertEqual(presenter.beginCount, 1, "presents once the user disengages")
    }
}
