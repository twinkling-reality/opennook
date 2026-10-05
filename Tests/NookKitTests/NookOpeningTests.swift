// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// How the nook opens: the person's hover choices and their intent, a host that fixes the
/// intent, a module's peek view, and claims that peek or end on a schedule.
@MainActor
final class NookOpeningTests: XCTestCase {
    private func makeCoordinator(
        _ configure: (inout NookConfiguration) -> Void = { _ in },
        behavior: NookChromeBehavior = .default
    ) -> (AppCoordinator, FakeNookSurface) {
        var configuration = NookConfiguration()
        configure(&configuration)
        let moduleHost = ModuleHost(configuration: configuration)
        moduleHost.chromeBehavior = behavior
        let surface = FakeNookSurface()
        let coordinator = AppCoordinator(moduleHost: moduleHost, surface: surface)
        return (coordinator, surface)
    }

    // MARK: - Preferences

    func testTheDefaultChoicesAreTheStandardIntent() {
        XCTAssertEqual(NookAppearancePreferences.default.openOnHover, .immediately)
        XCTAssertEqual(NookAppearancePreferences.default.hoverIntent, .standard)
    }

    func testChoicesMapOntoTheIntent() {
        var preferences = NookAppearancePreferences()
        preferences.openOnHover = .peekFirst
        preferences.hoverDelay = 0.2
        preferences.externalDisplayHoverDelay = 0.5
        preferences.peekDwell = 1.2
        XCTAssertEqual(
            preferences.hoverIntent,
            NookHoverIntent(
                action: .peek,
                delay: .milliseconds(200),
                externalDisplayDelay: .milliseconds(500),
                dwellToExpand: .milliseconds(1200)
            )
        )

        preferences.openOnHover = .off
        preferences.externalDisplayHoverDelay = 0.2
        preferences.peekDwell = 0
        let intent = preferences.hoverIntent
        XCTAssertEqual(intent.action, .none)
        XCTAssertNil(intent.externalDisplayDelay, "an equal delay is not a separate one")
        XCTAssertNil(intent.dwellToExpand, "no dwell waits for a click")
    }

    func testNonsenseTimingsReadAsNone() {
        var preferences = NookAppearancePreferences()
        preferences.hoverDelay = -3
        preferences.peekDwell = .nan
        XCTAssertEqual(preferences.hoverIntent, .standard)
    }

    func testHoverChoicesRoundTripAndOlderRecordsDecodeToDefaults() throws {
        var preferences = NookAppearancePreferences()
        preferences.openOnHover = .peekFirst
        preferences.hoverDelay = 0.3
        preferences.externalDisplayHoverDelay = 0.6
        preferences.peekDwell = 1
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(NookAppearancePreferences.self, from: data), preferences)

        let older = Data(#"{"chromePalette":"dark","surfaceStyle":"solid"}"#.utf8)
        let decoded = try JSONDecoder().decode(NookAppearancePreferences.self, from: older)
        XCTAssertEqual(decoded.openOnHover, .immediately)
        XCTAssertEqual(decoded.hoverIntent, .standard)
    }

    func testOnlyTheHoverFieldsAPersonChangedAreKept() {
        let defaults = NookAppearancePreferences(openOnHover: .peekFirst)
        var chosen = defaults
        chosen.hoverDelay = 0.4
        let choices = NookAppearanceChoices(differencesFrom: defaults, to: chosen)
        XCTAssertNil(choices.openOnHover, "unchanged, so it keeps following the host's default")
        XCTAssertEqual(choices.hoverDelay, 0.4)

        let applied = choices.applied(to: NookAppearancePreferences(openOnHover: .off))
        XCTAssertEqual(applied.openOnHover, .off)
        XCTAssertEqual(applied.hoverDelay, 0.4)
    }

    // MARK: - The coordinator

    func testThePersonsChoiceReachesTheSurface() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let (coordinator, surface) = makeCoordinator()
            coordinator.applyHoverIntent()
            XCTAssertEqual(surface.hoverIntent, .standard)
            XCTAssertFalse(coordinator.appState.hostFixesHoverIntent)

            var preferences = coordinator.appState.appearancePreferences
            preferences.openOnHover = .peekFirst
            coordinator.appState.replaceAppearancePreferences(preferences)
            coordinator.applyHoverIntent()
            XCTAssertEqual(surface.hoverIntent.action, .peek)
        }
    }

    func testAHostIntentWinsAndHidesTheRows() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let fixed = NookHoverIntent(action: .none)
            var behavior = NookChromeBehavior()
            behavior.hoverIntent = fixed
            let (coordinator, surface) = makeCoordinator(behavior: behavior)
            var preferences = coordinator.appState.appearancePreferences
            preferences.openOnHover = .peekFirst
            coordinator.appState.replaceAppearancePreferences(preferences)

            coordinator.applyHoverIntent()
            XCTAssertEqual(surface.hoverIntent, fixed)
            XCTAssertTrue(coordinator.appState.hostFixesHoverIntent)

            coordinator.replaceChromeBehavior(NookChromeBehavior())
            XCTAssertEqual(surface.hoverIntent.action, .peek, "back to the person's choice")
            XCTAssertFalse(coordinator.appState.hostFixesHoverIntent)
        }
    }

    func testAModulesPeekReachesTheSurfaceOnlyWhenItHasOne() {
        let (_, plain) = makeCoordinator()
        XCTAssertNil(plain.peekContent)

        let (_, peeking) = makeCoordinator { $0.setPeek { Text("Now playing") } }
        XCTAssertNotNil(peeking.peekContent)
    }

    // MARK: - Claims

    func testAPeekClaimPeeksAndItsEndShrinksThePill() async throws {
        let (coordinator, surface) = makeCoordinator { $0.setPeek { Text("Volume") } }
        await surface.compact(on: nil)

        let grant = await coordinator.beginTransientPresentation(
            NookSurfaceClaim(moduleID: coordinator.activeModuleID, presentation: .peek)
        )
        let token = try XCTUnwrap(grant)
        XCTAssertEqual(surface.state, .compact, "a peek claim does not open the nook")
        XCTAssertTrue(surface.isPeeking)

        await coordinator.endTransientPresentation(token)
        XCTAssertFalse(surface.isPeeking)
        XCTAssertEqual(surface.state, .compact)
    }

    func testAPeekClaimWithoutAPeekOpensTheNook() async throws {
        let (coordinator, surface) = makeCoordinator()
        await surface.compact(on: nil)
        let grant = await coordinator.beginTransientPresentation(
            NookSurfaceClaim(moduleID: coordinator.activeModuleID, presentation: .peek)
        )
        _ = try XCTUnwrap(grant)
        XCTAssertEqual(surface.state, .expanded)
        XCTAssertFalse(surface.isPeeking)
    }

    func testAScheduledEndReleasesTheClaimAndCanBeMoved() async throws {
        let (coordinator, surface) = makeCoordinator { $0.setPeek { Text("Volume") } }
        await surface.compact(on: nil)
        let grant = await coordinator.beginTransientPresentation(
            NookSurfaceClaim(moduleID: coordinator.activeModuleID, presentation: .peek)
        )
        let token = try XCTUnwrap(grant)

        let scheduled = await coordinator.endTransientPresentation(token, after: .milliseconds(150))
        XCTAssertTrue(scheduled)
        try await Task.sleep(for: .milliseconds(100))
        let moved = await coordinator.endTransientPresentation(token, after: .milliseconds(150))
        XCTAssertTrue(moved)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(surface.isPeeking, "the end moved, so the claim still holds")

        let deadline = ContinuousClock.now + .seconds(2)
        while surface.isPeeking, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(surface.isPeeking)

        let stale = await coordinator.endTransientPresentation(token, after: .milliseconds(10))
        XCTAssertFalse(stale, "an ended claim cannot be scheduled")
    }

    func testAPresenterWithoutScheduledEndsSaysSo() async {
        let presenter = PlainPresenter()
        let scheduled = await presenter.endTransientPresentation(NookSurfaceToken(value: 1), after: .seconds(1))
        XCTAssertFalse(scheduled)
    }
}

/// A conformer written before scheduled ends existed: it still compiles, and says it does not
/// schedule them.
@MainActor
private final class PlainPresenter: NookSurfacePresenting {
    var isUserEngaged: Bool { false }
    var userEngagementChanges: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var activeModuleID: String { "plain" }
    func beginTransientPresentation(_ claim: NookSurfaceClaim) async -> NookSurfaceToken? { nil }
    func endTransientPresentation(_ token: NookSurfaceToken) async {}
}
