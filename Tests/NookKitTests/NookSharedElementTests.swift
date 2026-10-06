// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import AppKit
import Combine
import SwiftUI
import XCTest

@testable import NookSurface

/// Shared elements: which copies hide, which ones fly and from where, how a move ends, and that
/// a nook with a shared element on screen converts without dipping through hidden.
@MainActor
final class NookSharedElementTests: XCTestCase {
    private func drawn(_ key: String, _ region: NookSharedElementRegion, _ frame: CGRect) -> NookSharedElementDrawn {
        NookSharedElementDrawn(key: key, region: region, frame: frame, content: AnyView(EmptyView()), style: .resize)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition not met within \(timeout)", file: file, line: line)
    }

    private let pill = CGRect(x: 10, y: 4, width: 20, height: 20)
    private let panel = CGRect(x: 20, y: 40, width: 156, height: 156)

    // MARK: - Regions

    func testThePartOfTheChromeOnScreenFollowsTheStateAndThePeek() {
        XCTAssertEqual(NookSharedElementRegion.onScreen(state: .expanded, isPeeking: false), .expanded)
        XCTAssertEqual(NookSharedElementRegion.onScreen(state: .compact, isPeeking: false), .compact)
        XCTAssertEqual(NookSharedElementRegion.onScreen(state: .compact, isPeeking: true), .peek)
        XCTAssertNil(NookSharedElementRegion.onScreen(state: .hidden, isPeeking: false))
    }

    // MARK: - Moves

    func testNoElementsMeansNoMove() {
        let coordinator = NookSharedElementCoordinator()
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        XCTAssertFalse(coordinator.holdsElements)
        coordinator.surfaceWillMove(to: .expanded, animation: .default)
        XCTAssertNil(coordinator.transition)
        XCTAssertTrue(coordinator.flights(for: [drawn("cover", .expanded, panel)]).isEmpty)
    }

    func testAnElementFliesFromWhereItWasToItsCopy() async {
        let coordinator = NookSharedElementCoordinator()
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        coordinator.record([drawn("cover", .compact, pill), drawn("title", .compact, pill)])
        XCTAssertTrue(coordinator.holdsElements)

        coordinator.surfaceWillMove(to: .expanded, animation: .default)
        XCTAssertEqual(coordinator.transition?.sources, ["cover": pill, "title": pill])
        XCTAssertTrue(
            coordinator.isHidden("cover", in: .expanded),
            "the destination waits for the flight from the start"
        )
        XCTAssertFalse(coordinator.isHidden("cover", in: .compact), "the source leaves as usual until a copy is found")

        let laidOut = [drawn("cover", .compact, pill), drawn("cover", .expanded, panel)]
        let plans = coordinator.flights(for: laidOut)
        XCTAssertEqual(plans.map(\.key), ["cover"], "an element with no copy on the far side does not fly")
        XCTAssertEqual(plans.first?.start, pill)
        XCTAssertEqual(plans.first?.target, panel)

        coordinator.record(laidOut)
        await waitUntil { coordinator.transition?.matched == ["cover"] }
        XCTAssertTrue(coordinator.isHidden("cover", in: .compact), "once matched, only the moving copy shows")
        XCTAssertFalse(coordinator.isHidden("title", in: .compact))

        coordinator.land("cover", generation: coordinator.transition?.generation ?? 0)
        XCTAssertNil(coordinator.transition)
        XCTAssertFalse(coordinator.isHidden("cover", in: .expanded))
    }

    func testALandingFromAnEarlierMoveIsIgnored() {
        let coordinator = NookSharedElementCoordinator()
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        coordinator.record([drawn("cover", .compact, pill)])
        coordinator.surfaceWillMove(to: .expanded, animation: .default)
        let first = coordinator.transition?.generation ?? 0

        coordinator.record([drawn("cover", .expanded, panel)])
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        XCTAssertEqual(coordinator.transition?.sources["cover"], panel, "turned around, it flies back from the panel")

        coordinator.land("cover", generation: first)
        XCTAssertNotNil(coordinator.transition)
        XCTAssertTrue(coordinator.transition?.isMoving("cover") == true)
    }

    func testAnElementStillOnItsWayKeepsFlyingWhenTheNookChangesCourse() {
        let coordinator = NookSharedElementCoordinator()
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        coordinator.record([drawn("cover", .compact, pill)])
        coordinator.surfaceWillMove(to: .peek, animation: .default)
        // The chrome expanded before the peek's copy was ever drawn.
        coordinator.surfaceWillMove(to: .expanded, animation: .default)
        XCTAssertEqual(coordinator.transition?.from, .peek)
        XCTAssertEqual(coordinator.transition?.sources["cover"], pill)
    }

    func testReduceMotionMovesNothing() {
        let coordinator = NookSharedElementCoordinator()
        coordinator.reduceMotion = true
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        coordinator.record([drawn("cover", .compact, pill)])
        coordinator.surfaceWillMove(to: .expanded, animation: .default)
        XCTAssertNil(coordinator.transition)
        XCTAssertFalse(coordinator.isHidden("cover", in: .expanded))
    }

    func testHidingForgetsEverything() {
        let coordinator = NookSharedElementCoordinator()
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        coordinator.record([drawn("cover", .compact, pill)])
        coordinator.surfaceWillMove(to: nil, animation: .default)
        XCTAssertFalse(coordinator.holdsElements)
        coordinator.surfaceWillMove(to: .expanded, animation: .default)
        XCTAssertNil(coordinator.transition, "a new window has nothing to fly from")
    }

    func testWhileThePillPeeksTheElementShowsInThePeekOnly() async {
        let coordinator = NookSharedElementCoordinator()
        coordinator.surfaceWillMove(to: .compact, animation: .default)
        coordinator.surfaceWillMove(to: .peek, animation: .default)
        coordinator.record([drawn("cover", .compact, pill), drawn("cover", .peek, panel)])
        await waitUntil { coordinator.presence["cover"] == [.compact, .peek] }
        XCTAssertTrue(coordinator.isHidden("cover", in: .compact))
        XCTAssertFalse(coordinator.isHidden("cover", in: .peek))
        XCTAssertFalse(coordinator.isHidden("cover", in: .flight))
    }

    // MARK: - The surface

    private func screen() throws -> NSScreen {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        return screen
    }

    private func makeNook(shared: Bool) -> Nook<AnyView, AnyView, EmptyView> {
        let nook = Nook(
            hoverBehavior: [],
            expanded: {
                AnyView(Color.red.frame(width: 120, height: 120).nookSharedElementIf(shared, "cover"))
            },
            compactLeading: {
                AnyView(Color.red.frame(width: 16, height: 16).nookSharedElementIf(shared, "cover"))
            }
        )
        nook.transitionConfiguration.animationDuration = 0.05
        return nook
    }

    /// The states the surface passes through while `body` runs.
    private func states(of nook: Nook<AnyView, AnyView, EmptyView>, during body: () async -> Void) async -> [NookState]
    {
        var seen: [NookState] = []
        let subscription = nook.$state.dropFirst().sink { seen.append($0) }
        await body()
        subscription.cancel()
        return seen
    }

    func testAConversionWithoutSharedElementsStillDipsThroughHidden() async throws {
        let screen = try screen()
        let nook = makeNook(shared: false)
        await nook.compact(on: screen)
        let seen = await states(of: nook) { await nook.expand(on: screen) }
        XCTAssertEqual(seen, [.hidden, .expanded])
        await nook.hide()
    }

    func testASharedElementOnScreenFliesAndTheConversionSkipsTheDip() async throws {
        let screen = try screen()
        let nook = makeNook(shared: true)
        await nook.compact(on: screen)
        await waitUntil { nook.sharedElements.holdsElements }

        var moves: [NookSharedElementCoordinator.Transition?] = []
        let subscription = nook.sharedElements.$transition.dropFirst().sink { moves.append($0) }
        let seen = await states(of: nook) { await nook.expand(on: screen) }
        XCTAssertEqual(seen, [.expanded], "no dip through hidden")
        await waitUntil { nook.sharedElements.transition == nil }
        subscription.cancel()
        XCTAssertEqual(moves.first??.sources.keys.sorted(), ["cover"], "the move starts from the pill")
        XCTAssertTrue(moves.contains { $0?.matched == ["cover"] }, "the expanded copy was found")
        XCTAssertNil(moves.last ?? nil, "and it landed")
        XCTAssertFalse(nook.sharedElements.isHidden("cover", in: .expanded), "landed in place")
        await nook.hide()
        XCTAssertFalse(nook.sharedElements.holdsElements)
    }
}

extension View {
    /// Marks the view as a shared element when `shared` is `true`.
    @ViewBuilder
    fileprivate func nookSharedElementIf(_ shared: Bool, _ id: String) -> some View {
        if shared { nookSharedElement(id) } else { self }
    }
}
