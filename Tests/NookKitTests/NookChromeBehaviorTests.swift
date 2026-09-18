// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// Host-global chrome behavior: hover side-effects, the cold-launch shimmer opt-out, and
/// the appearance->backdrop mapping override - all defaulting to today's behavior and
/// threaded from the host (or, single-module, forwarded from `NookConfiguration`).
///
/// `@MainActor`: `AppCoordinator` / `ModuleHost` are main-actor isolated.
@MainActor
final class NookChromeBehaviorTests: XCTestCase {
    private func makeCoordinator(
        chromeBehavior: NookChromeBehavior,
        appState: AppState = AppState(),
        surface: any NookSurfaceDriving
    ) -> AppCoordinator {
        var host = NookHostConfiguration()
        host.chromeBehavior = chromeBehavior
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) { NookConfiguration() }
        host.defaultModule = "A"
        return AppCoordinator(
            appState: appState,
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: surface
        )
    }

    /// Defaults reproduce the framework: no hover side-effects, the shimmer plays, and no
    /// backdrop override - and both configuration structs default to that.
    func testDefaultsReproduceFramework() {
        let behavior = NookChromeBehavior.default
        XCTAssertEqual(behavior.hoverBehavior, [])
        XCTAssertTrue(behavior.showsLaunchShimmer)
        XCTAssertNil(behavior.backdrop)

        XCTAssertEqual(NookConfiguration().chromeBehavior.hoverBehavior, [])
        XCTAssertTrue(NookConfiguration().chromeBehavior.showsLaunchShimmer)
        XCTAssertNil(NookConfiguration().chromeBehavior.backdrop)

        XCTAssertEqual(NookHostConfiguration().chromeBehavior.hoverBehavior, [])
        XCTAssertTrue(NookHostConfiguration().chromeBehavior.showsLaunchShimmer)
    }

    /// The host's chrome behavior reaches `ModuleHost` (the path `AppCoordinator` reads).
    func testChromeBehaviorThreadsFromHostToModuleHost() {
        var host = NookHostConfiguration()
        host.chromeBehavior = NookChromeBehavior(
            hoverBehavior: .all,
            showsLaunchShimmer: false,
            backdrop: { _ in .solid(.red) }
        )
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) { NookConfiguration() }

        let moduleHost = ModuleHost(registry: host.makeRegistry())

        XCTAssertEqual(moduleHost.chromeBehavior.hoverBehavior, .all)
        XCTAssertFalse(moduleHost.chromeBehavior.showsLaunchShimmer)
        XCTAssertNotNil(moduleHost.chromeBehavior.backdrop)
    }

    /// The single-module path forwards `NookConfiguration.chromeBehavior` onto the
    /// synthesized host.
    func testSingleModuleForwardsChromeBehavior() {
        var configuration = NookConfiguration()
        configuration.chromeBehavior.hoverBehavior = .keepVisible

        let moduleHost = ModuleHost(configuration: configuration)

        XCTAssertEqual(moduleHost.chromeBehavior.hoverBehavior, .keepVisible)
    }

    /// A host backdrop resolver replaces the framework mapping on the surface.
    func testBackdropOverrideReachesSurface() {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(backdrop: { _ in .solid(.red) }),
            surface: surface
        )

        coordinator.syncNotchBackdrop()

        XCTAssertEqual(surface.backdrop, .solid(.red))
    }

    /// Without an override, the framework mapping applies - a `.dark` + `.solid`
    /// appearance maps to opaque black regardless of the system scheme.
    func testDefaultBackdropUsesFrameworkMapping() {
        let appState = AppState()
        appState.appearancePreferences = NookAppearancePreferences(
            chromePalette: .dark,
            surfaceStyle: .solid
        )
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: .default,
            appState: appState,
            surface: surface
        )

        coordinator.syncNotchBackdrop()

        XCTAssertEqual(surface.backdrop, .solid(.black))
    }

    /// With the shimmer opted out, cold launch fires no feedback (but still settles the
    /// surface into its compact launch state).
    func testLaunchShimmerOptOutPlaysNoFeedback() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(showsLaunchShimmer: false),
            surface: surface
        )

        coordinator.start()
        await coordinator.drainLifecycleForTesting()

        XCTAssertEqual(surface.feedbackCount, 0)
        XCTAssertEqual(surface.state, .compact)
    }

    /// By default the cold-launch shimmer plays exactly once.
    func testLaunchShimmerPlaysByDefault() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(chromeBehavior: .default, surface: surface)

        coordinator.start()
        await coordinator.drainLifecycleForTesting()

        XCTAssertEqual(surface.feedbackCount, 1)
    }

    // MARK: - Glass shading and companion backdrops

    private func glassAppState() -> AppState {
        let appState = AppState()
        appState.appearancePreferences = NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .liquidGlass)
        return appState
    }

    /// The glass shading reaches the chrome, and companions get the even glass that suits them.
    func testNotchFadeReachesTheChromeAndCompanions() {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(glassShading: .notchFade),
            appState: glassAppState(),
            surface: surface
        )

        coordinator.syncNotchBackdrop()

        XCTAssertEqual(
            surface.backdrop,
            .liquidGlass(.init(tint: nil, highlightStrength: 0.6, shading: .notchFade(.black, strength: 1)))
        )
        XCTAssertNotNil(surface.companionBackdrop)
        XCTAssertNotEqual(surface.companionBackdrop, surface.backdrop)
    }

    /// With the default even glass, companions inherit the chrome's backdrop as before.
    func testEvenGlassLeavesCompanionsOnTheChromesBackdrop() {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(chromeBehavior: .default, appState: glassAppState(), surface: surface)

        coordinator.syncNotchBackdrop()

        XCTAssertNil(surface.companionBackdrop)
    }

    /// A host that resolves the chrome's backdrop keeps companions on it, unless it resolves
    /// theirs too.
    func testHostResolversDecideTheCompanionBackdrop() {
        let surface = FakeNookSurface()
        let replacing = makeCoordinator(
            chromeBehavior: NookChromeBehavior(backdrop: { _ in .solid(.red) }, glassShading: .notchFade),
            appState: glassAppState(),
            surface: surface
        )
        replacing.syncNotchBackdrop()
        XCTAssertNil(surface.companionBackdrop)

        let companionSurface = FakeNookSurface()
        let both = makeCoordinator(
            chromeBehavior: NookChromeBehavior(
                backdrop: { _ in .solid(.red) },
                companionBackdrop: { _ in .solid(.blue) }
            ),
            surface: companionSurface
        )
        both.syncNotchBackdrop()
        XCTAssertEqual(companionSurface.backdrop, .solid(.red))
        XCTAssertEqual(companionSurface.companionBackdrop, .solid(.blue))
    }

    // MARK: - Per-state backdrops

    /// The whole point of the notch fade: the chrome is two surfaces, and they get two
    /// backdrops. Collapsed it is the flat notch color - the fade has nothing but the notch's
    /// own 32 points to run down, most of it behind the camera - and expanded it is the fade.
    /// The swap happens on the transition, without anything else changing.
    func testNotchFadeSwapsTheBackdropBetweenCompactAndExpanded() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(glassShading: .notchFade),
            appState: glassAppState(),
            surface: surface
        )
        let fade = NookBackdrop.liquidGlass(
            .init(tint: nil, highlightStrength: 0.6, shading: .notchFade(.black, strength: 1))
        )

        coordinator.start()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.state, .compact)
        XCTAssertEqual(surface.backdrop, .solid(.black), "collapsed, the chrome reads as the hardware notch")
        XCTAssertNil(surface.companionBackdrop, "no tall fade to squeeze, so companions inherit the chrome")

        coordinator.toggleNook()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.state, .expanded)
        XCTAssertEqual(surface.backdrop, fade, "expanded, the panel is tall enough for the fade")
        XCTAssertNotNil(surface.companionBackdrop, "and companions go back to their own even glass")

        coordinator.toggleNook()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.state, .compact)
        XCTAssertEqual(surface.backdrop, .solid(.black), "collapsing swaps it back")
        XCTAssertNil(surface.companionBackdrop)
    }

    /// Nothing repaints on the way out. A hide fades the panel away, and re-resolving across it
    /// would flash the collapsed backdrop over a panel that is still on screen - so the chrome
    /// keeps whatever it was painted with until it is visible again.
    func testHidingLeavesTheBackdropAlone() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(glassShading: .notchFade),
            appState: glassAppState(),
            surface: surface
        )

        coordinator.start()
        await coordinator.drainLifecycleForTesting()
        coordinator.toggleNook()
        await coordinator.drainLifecycleForTesting()
        let expanded = surface.backdrop

        await surface.hide()

        XCTAssertEqual(surface.state, .hidden)
        XCTAssertEqual(surface.backdrop, expanded)
    }

    /// A host resolver is re-run on every transition and told which chrome it is answering for -
    /// the state and the layout the presentation resolved to.
    func testHostResolverIsRerunWithTheLiveChromeState() async {
        let surface = FakeNookSurface()
        surface.layoutForm = .floating
        let log = ContextLog()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(
                backdrop: { context in
                    log.record(context)
                    return context.isExpanded ? .solid(.blue) : .solid(.red)
                }
            ),
            surface: surface
        )

        coordinator.start()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.backdrop, .solid(.red))

        coordinator.toggleNook()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.backdrop, .solid(.blue))

        coordinator.toggleNook()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.backdrop, .solid(.red))

        XCTAssertEqual(
            log.states.filter { $0 != .hidden },
            [.compact, .expanded, .compact],
            "every visible transition re-resolves, and none of them is the hidden one"
        )
        XCTAssertTrue(log.contexts.allSatisfy { $0.form == .floating }, "the resolved layout comes through")
    }

    /// A companion resolver gets the same context, so companions beside the compact pill can be
    /// painted differently from those under the expanded panel.
    func testCompanionResolverSeesTheChromeState() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(
                companionBackdrop: { $0.isExpanded ? .solid(.blue) : .solid(.red) }
            ),
            surface: surface
        )

        coordinator.start()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.companionBackdrop, .solid(.red))

        coordinator.toggleNook()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.companionBackdrop, .solid(.blue))
    }

    /// The freeze test: a host that sets no shading gets exactly today's rendering. The
    /// framework's even glass is one backdrop for the whole chrome, and expanding or collapsing
    /// must not move it - for any surface style.
    func testDefaultShadingPaintsTheSameBackdropInEveryState() async {
        for style in NookSurfaceStyle.allCases {
            let appState = AppState()
            appState.appearancePreferences = NookAppearancePreferences(chromePalette: .dark, surfaceStyle: style)
            let surface = FakeNookSurface()
            let coordinator = makeCoordinator(chromeBehavior: .default, appState: appState, surface: surface)
            let expected = NookBackdropMapping.notchBackdrop(
                preferences: appState.appearancePreferences,
                effectiveColorScheme: .dark,
                reduceTransparency: false
            )

            coordinator.start()
            await coordinator.drainLifecycleForTesting()
            XCTAssertEqual(surface.backdrop, expected, "\(style) compact")
            XCTAssertNil(surface.companionBackdrop, "\(style) compact companions")

            coordinator.toggleNook()
            await coordinator.drainLifecycleForTesting()
            XCTAssertEqual(surface.backdrop, expected, "\(style) expanded")
            XCTAssertNil(surface.companionBackdrop, "\(style) expanded companions")
        }
    }

    /// The same swap on the real surface. The fake pins the coordinator's wiring; this pins
    /// that a `Nook` mounting an actual window publishes the transitions that drive it - its
    /// state changes inside a `withAnimation`, and the sink has to reach the backdrop from
    /// there rather than a runloop turn later, after the panel has already resized.
    func testRealSurfaceRepaintsItsBackdropOnEveryTransition() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main display attached") }

        // `hoverBehavior: []` keeps a pointer parked over the notch from holding the panel
        // open; compact content keeps `compact` from collapsing to a hide.
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") }, compactLeading: { Text("L") })
        nook.transitionConfiguration.animationDuration = 0.05
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(glassShading: .notchFade),
            appState: glassAppState(),
            surface: nook
        )
        let fade = NookBackdrop.liquidGlass(
            .init(tint: nil, highlightStrength: 0.6, shading: .notchFade(.black, strength: 1))
        )
        coordinator.syncNotchBackdrop()

        await nook.compact(on: screen)
        XCTAssertEqual(nook.state, .compact)
        XCTAssertEqual(nook.backdrop, .solid(.black))

        await nook.expand(on: screen)
        XCTAssertEqual(nook.state, .expanded)
        XCTAssertEqual(nook.backdrop, fade)

        await nook.compact(on: screen)
        XCTAssertEqual(nook.state, .compact)
        XCTAssertEqual(nook.backdrop, .solid(.black))

        await nook.hide()
        XCTAssertEqual(nook.backdrop, .solid(.black), "a hide repaints nothing")
    }

    // MARK: - Keyboard

    /// Defaults: the shortcut does not take the keyboard, and the Edit menu is installed.
    func testKeyboardDefaults() {
        XCTAssertEqual(NookChromeBehavior.default.keyboard, .default)
        XCTAssertFalse(NookKeyboardBehavior.default.shortcutTakesKeyboardFocus)
        XCTAssertTrue(NookKeyboardBehavior.default.installsEditMenu)
        XCTAssertEqual(NookChromeBehavior.default.glassShading, .even)
        XCTAssertNil(NookChromeBehavior.default.companionBackdrop)
    }

    /// Opted in, a shortcut that opens the nook gives it the keyboard; any other open does not.
    func testShortcutOpenTakesTheKeyboardOnlyWhenOptedIn() async {
        let optedIn = FakeNookSurface()
        let coordinator = makeCoordinator(
            chromeBehavior: NookChromeBehavior(keyboard: NookKeyboardBehavior(shortcutTakesKeyboardFocus: true)),
            surface: optedIn
        )
        coordinator.toggleNook()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(optedIn.keyboardFocusRequests, 0, "an open from elsewhere leaves the keyboard alone")

        coordinator.toggleNook()
        coordinator.toggleNook(fromShortcut: true)
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(optedIn.state, .expanded)
        XCTAssertTrue(optedIn.hasKeyboardFocus)
        XCTAssertTrue(coordinator.nookHasKeyboardFocus)

        coordinator.toggleNook(fromShortcut: true)
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(optedIn.state, .compact)
        XCTAssertFalse(optedIn.hasKeyboardFocus, "collapsing hands the keyboard back")

        let optedOut = FakeNookSurface()
        let defaultCoordinator = makeCoordinator(chromeBehavior: .default, surface: optedOut)
        defaultCoordinator.toggleNook(fromShortcut: true)
        await defaultCoordinator.drainLifecycleForTesting()
        XCTAssertEqual(optedOut.state, .expanded)
        XCTAssertEqual(optedOut.keyboardFocusRequests, 0)
    }

    /// The coordinator's keyboard calls, and the chrome actions views use, reach the surface.
    func testKeyboardCallsReachTheSurface() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(chromeBehavior: .default, surface: surface)
        XCTAssertFalse(coordinator.takeNookKeyboardFocus(), "a hidden nook cannot take the keyboard")

        coordinator.showNook()
        await coordinator.drainLifecycleForTesting()
        coordinator.chromeActions.takeKeyboardFocus()
        XCTAssertTrue(surface.hasKeyboardFocus)
        coordinator.chromeActions.releaseKeyboardFocus()
        XCTAssertFalse(surface.hasKeyboardFocus)
        XCTAssertTrue(coordinator.takeNookKeyboardFocus())
        coordinator.releaseNookKeyboardFocus()
        XCTAssertFalse(coordinator.nookHasKeyboardFocus)
        XCTAssertNil(coordinator.nookWindow, "the fake surface has no window")
    }
}

/// Records the contexts a backdrop resolver is called with. A class, not a captured array:
/// the resolver is `@Sendable`, and a `@MainActor` reference type is `Sendable` by isolation.
@MainActor
private final class ContextLog {
    private(set) var contexts: [NookBackdropContext] = []

    var states: [NookState] { contexts.map(\.state) }

    func record(_ context: NookBackdropContext) {
        contexts.append(context)
    }
}
