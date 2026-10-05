// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import AppKit
import SwiftUI
import XCTest

@testable import NookSurface

/// The compact pill's peek and the hover intent that can lead to it: the peek verbs, the
/// pointer's delay and dwell, click to open, and that the standard intent leaves hover as it was.
@MainActor
final class NookPeekTests: XCTestCase {
    private func makeNook(peek: Bool = true) -> Nook<Text, Text, EmptyView> {
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") }, compactLeading: { Text("L") })
        nook.transitionConfiguration.animationDuration = 0.05
        if peek { nook.peekContent = AnyView(Text("Now playing")) }
        return nook
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
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

    private func screen() throws -> NSScreen {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }
        return screen
    }

    // MARK: - Defaults

    func testDefaultsLeaveTheSurfaceAsItWas() {
        let nook = makeNook(peek: false)
        XCTAssertEqual(nook.hoverIntent, .standard)
        XCTAssertNil(nook.peekContent)
        XCTAssertFalse(nook.isPeeking)
        XCTAssertFalse(nook.opensOnClick)
        XCTAssertEqual(nook.style.peekBottomCornerRadius, 22)
        XCTAssertEqual(nook.style.peekMaxHeight, 120)
        XCTAssertEqual(nook.transitionConfiguration.peekContentTransition, .standardPeek)
        XCTAssertNil(nook.transitionConfiguration.peekContentRemoval)
        XCTAssertNil(nook.transitionConfiguration.peekAnimation)
    }

    func testAnIntentClampsNegativeDurationsAndPicksTheDisplaysDelay() {
        let intent = NookHoverIntent(
            action: .peek,
            delay: .milliseconds(-5),
            externalDisplayDelay: .milliseconds(300),
            dwellToExpand: .seconds(-1)
        )
        XCTAssertEqual(intent.delay, .zero)
        XCTAssertEqual(intent.dwellToExpand, .zero)
        XCTAssertEqual(intent.delay(onBuiltInDisplay: true), .zero)
        XCTAssertEqual(intent.delay(onBuiltInDisplay: false), .milliseconds(300))
        XCTAssertEqual(NookHoverIntent(delay: .milliseconds(80)).delay(onBuiltInDisplay: false), .milliseconds(80))
    }

    // MARK: - Peek verbs

    func testPeekGrowsTheCompactPillAndEndPeekShrinksIt() async throws {
        let screen = try screen()
        let nook = makeNook()
        await nook.compact(on: screen)

        await nook.peek(on: screen)
        XCTAssertEqual(nook.state, .compact, "a peek is a way of being compact")
        XCTAssertTrue(nook.isPeeking)
        XCTAssertFalse(nook.peekStartedByHover)
        XCTAssertTrue(nook.opensOnClick, "a peeking pill opens on a click")

        await nook.endPeek()
        XCTAssertFalse(nook.isPeeking)
        await nook.hide()
    }

    func testPeekWithoutContentDoesNothing() async throws {
        let screen = try screen()
        let nook = makeNook(peek: false)
        await nook.compact(on: screen)
        await nook.peek(on: screen)
        XCTAssertFalse(nook.isPeeking)
        XCTAssertEqual(nook.state, .compact)
        await nook.hide()
    }

    func testPeekOnAHiddenNookShowsTheCompactPillFirst() async throws {
        let screen = try screen()
        let nook = makeNook()
        await nook.peek(on: screen)
        XCTAssertEqual(nook.state, .compact)
        XCTAssertTrue(nook.isPeeking)
        await nook.hide()
        XCTAssertFalse(nook.isPeeking, "hiding ends the peek")
    }

    func testPeekDoesNothingWhileExpanded() async throws {
        let screen = try screen()
        let nook = makeNook()
        await nook.expand(on: screen)
        await nook.peek(on: screen)
        XCTAssertEqual(nook.state, .expanded)
        XCTAssertFalse(nook.isPeeking)
        await nook.hide()
    }

    func testANookWithoutCompactContentCannotPeek() async throws {
        let screen = try screen()
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") })
        nook.peekContent = AnyView(Text("peek"))
        await nook.peek(on: screen)
        XCTAssertFalse(nook.isPeeking)
        XCTAssertEqual(nook.state, .hidden)
    }

    func testExpandingFromAPeekEndsIt() async throws {
        let screen = try screen()
        let nook = makeNook()
        await nook.peek(on: screen)
        await nook.expand(on: screen)
        XCTAssertEqual(nook.state, .expanded)
        XCTAssertFalse(nook.isPeeking)
        await nook.compact(on: screen)
        XCTAssertFalse(nook.isPeeking, "collapsing again does not bring the peek back")
        await nook.hide()
    }

    func testRemovingThePeekContentEndsThePeek() async throws {
        let screen = try screen()
        let nook = makeNook()
        await nook.peek(on: screen)
        nook.peekContent = nil
        XCTAssertFalse(nook.isPeeking)
        await nook.hide()
    }

    // MARK: - Hover intent

    func testTheStandardIntentOpensOnHoverAtOnce() async throws {
        let screen = try screen()
        let nook = makeNook()
        await nook.compact(on: screen)
        nook.updateHoverState(true)
        await waitUntil { nook.state == .expanded }
        XCTAssertFalse(nook.isPeeking, "the standard intent never peeks, even with peek content")
        await nook.hide()
    }

    func testAPeekIntentWaitsItsDelayThenPeeks() async throws {
        let screen = try screen()
        let nook = makeNook()
        nook.hoverIntent = NookHoverIntent(
            action: .peek,
            delay: .milliseconds(900),
            externalDisplayDelay: .milliseconds(900)
        )
        await nook.compact(on: screen)

        nook.updateHoverState(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(nook.isPeeking, "still inside the delay")
        await waitUntil(timeout: .seconds(4)) { nook.isPeeking }
        XCTAssertTrue(nook.peekStartedByHover)
        XCTAssertEqual(nook.state, .compact)
        await nook.hide()
    }

    func testLeavingDuringTheDelayCancelsIt() async throws {
        let screen = try screen()
        let nook = makeNook()
        nook.hoverIntent = NookHoverIntent(
            action: .peek,
            delay: .milliseconds(900),
            externalDisplayDelay: .milliseconds(900)
        )
        await nook.compact(on: screen)

        nook.updateHoverState(true)
        try await Task.sleep(for: .milliseconds(20))
        nook.updateHoverState(false)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertFalse(nook.isPeeking)
        XCTAssertEqual(nook.state, .compact)
        await nook.hide()
    }

    func testLeavingEndsAPointersPeekButNotTheHosts() async throws {
        let screen = try screen()
        let nook = makeNook()
        nook.hoverIntent = NookHoverIntent(action: .peek)
        await nook.compact(on: screen)

        nook.updateHoverState(true)
        await waitUntil { nook.isPeeking }
        nook.updateHoverState(false)
        await waitUntil { !nook.isPeeking }

        await nook.peek(on: screen)
        nook.updateHoverState(true)
        nook.updateHoverState(false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(nook.isPeeking, "the host's peek stays when the pointer leaves")
        await nook.hide()
    }

    func testDwellingOnAPeekOpensTheNook() async throws {
        let screen = try screen()
        let nook = makeNook()
        nook.hoverIntent = NookHoverIntent(action: .peek, dwellToExpand: .milliseconds(900))
        await nook.compact(on: screen)

        nook.updateHoverState(true)
        await waitUntil { nook.isPeeking }
        XCTAssertEqual(nook.state, .compact)
        await waitUntil(timeout: .seconds(4)) { nook.state == .expanded }
        XCTAssertFalse(nook.isPeeking)
        await nook.hide()
    }

    func testAPeekIntentWithoutPeekContentOpensTheNook() async throws {
        let screen = try screen()
        let nook = makeNook(peek: false)
        nook.hoverIntent = NookHoverIntent(action: .peek)
        await nook.compact(on: screen)
        nook.updateHoverState(true)
        await waitUntil { nook.state == .expanded }
        await nook.hide()
    }

    func testANoneIntentLeavesThePillAloneUntilAClick() async throws {
        let screen = try screen()
        let nook = makeNook()
        nook.hoverIntent = NookHoverIntent(action: .none)
        await nook.compact(on: screen)

        nook.updateHoverState(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(nook.state, .compact)
        XCTAssertFalse(nook.isPeeking)
        XCTAssertTrue(nook.opensOnClick)

        nook.handleChromeClick()
        await waitUntil { nook.state == .expanded }
        await nook.hide()
    }

    func testAClickOnTheStandardPillDoesNothing() async throws {
        let screen = try screen()
        let nook = makeNook()
        await nook.compact(on: screen)
        XCTAssertFalse(nook.opensOnClick)
        nook.handleChromeClick()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(nook.state, .compact)
        await nook.hide()
    }
}
