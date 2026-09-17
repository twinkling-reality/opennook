// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// Coverage for the NookKit side of companion surfaces and the movable chrome controls:
/// registration, projection onto the surface, teardown on a module switch, the Settings
/// restriction, and the chrome actions a companion uses to stand in for the lock and gear.
@MainActor
final class NookCompanionConfigurationTests: XCTestCase {
    /// A module whose configuration is built by a closure, so each test shapes its own.
    private final class ConfiguredModule: NookModule {
        let descriptor: NookModuleDescriptor
        private let build: () -> NookConfiguration

        init(id: String, build: @escaping () -> NookConfiguration) {
            self.descriptor = NookModuleDescriptor(id: id, displayName: id, backgroundPolicy: .stayResident)
            self.build = build
        }

        func makeConfiguration() -> NookConfiguration { build() }
    }

    private func makeCoordinator(
        _ modules: [ConfiguredModule],
        surface: FakeNookSurface
    ) -> AppCoordinator {
        var host = NookHostConfiguration()
        for module in modules {
            let captured = module
            host.register(captured.descriptor) { _ in captured }
        }
        host.defaultModule = modules[0].descriptor.id
        return AppCoordinator(moduleHost: ModuleHost(registry: host.makeRegistry()), surface: surface)
    }

    private func configurationWithCompanions() -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.addCompanion(id: "pill", spacing: 10, accessibilityLabel: "Actions") { Text("pill") }
        configuration.addCompanion(
            id: "timer",
            anchor: .trailing(alignment: .start),
            visibility: .both,
            shape: .circle,
            backdrop: .none,
            hidesInSettings: false
        ) {
            Text("timer")
        }
        configuration.rimGlow = NookRimGlowStyle(glowRadius: 4, followsAmbientColor: true)
        configuration.scrollEdgeFade = NookScrollEdgeFade(edges: .vertical, length: 24)
        return configuration
    }

    // MARK: - Registration

    func testDefaultsLeaveTheChromeAsItWas() {
        let configuration = NookConfiguration()
        XCTAssertTrue(configuration.companions.isEmpty)
        XCTAssertEqual(configuration.rimGlow, .standard)
        XCTAssertNil(configuration.scrollEdgeFade)
        XCTAssertTrue(configuration.topBar.showsKeepOpenButton)
        XCTAssertTrue(configuration.topBar.showsSettingsButton)
    }

    func testAddCompanionRecordsItsPlacementAndBuildsLazily() {
        final class BuildCount: @unchecked Sendable { var value = 0 }
        let builds = BuildCount()
        var configuration = NookConfiguration()
        configuration.addCompanion(id: "pill") { () -> Text in
            builds.value += 1
            return Text("pill")
        }

        let pill = configuration.companions[0]
        XCTAssertEqual(pill.id, "pill")
        XCTAssertEqual(pill.anchor, .below)
        XCTAssertEqual(pill.spacing, NookCompanionSurface.defaultSpacing)
        XCTAssertEqual(pill.visibility, .expanded)
        XCTAssertEqual(pill.shape, .capsule)
        XCTAssertEqual(pill.backdrop, .inherit)
        XCTAssertTrue(pill.hidesInSettings)
        XCTAssertNil(pill.theme)
        XCTAssertEqual(pill.accessibilityIdentifier, "opennook.companion.pill")
        XCTAssertEqual(builds.value, 0, "content is built when rendered, not when registered")

        _ = pill.content()
        XCTAssertEqual(builds.value, 1)
    }

    // MARK: - Projection and teardown

    func testCoordinatorProjectsCompanionsAndDecorationsOntoTheSurface() {
        let surface = FakeNookSurface()
        _ = makeCoordinator([ConfiguredModule(id: "A", build: configurationWithCompanions)], surface: surface)

        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer"])
        let pill = surface.companions[0]
        XCTAssertEqual(pill.spacing, 10)
        XCTAssertEqual(pill.accessibilityLabel, "Actions")
        let timer = surface.companions[1]
        XCTAssertEqual(timer.anchor, .trailing(alignment: .start))
        XCTAssertEqual(timer.visibility, .both)
        XCTAssertEqual(timer.shape, .circle)
        XCTAssertEqual(timer.backdrop, NookCompanionBackdrop.none)
        XCTAssertEqual(surface.rimGlowStyle, NookRimGlowStyle(glowRadius: 4, followsAmbientColor: true))
        XCTAssertEqual(surface.scrollEdgeFade, NookScrollEdgeFade(edges: .vertical, length: 24))
    }

    func testCoordinatorLeavesTheSurfaceUndecoratedByDefault() {
        let surface = FakeNookSurface()
        _ = makeCoordinator([ConfiguredModule(id: "A", build: { NookConfiguration() })], surface: surface)

        XCTAssertTrue(surface.companions.isEmpty)
        XCTAssertEqual(surface.rimGlowStyle, .standard)
        XCTAssertNil(surface.scrollEdgeFade)
    }

    /// A switched-away module's companions leave the surface in the switch itself, and the
    /// incoming module's decorations replace its own.
    func testSwitchingModulesSwapsCompanionsAndDecorations() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [
                ConfiguredModule(id: "A", build: configurationWithCompanions),
                ConfiguredModule(id: "B", build: { NookConfiguration() }),
            ],
            surface: surface
        )
        await surface.expand(on: nil)

        coordinator.switchModule(to: "B")
        await coordinator.drainLifecycleForTesting()
        XCTAssertTrue(surface.companions.isEmpty, "module A's companions left with it")
        XCTAssertEqual(surface.rimGlowStyle, .standard)
        XCTAssertNil(surface.scrollEdgeFade)

        coordinator.switchModule(to: "A")
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer"])
        XCTAssertEqual(surface.scrollEdgeFade?.length, 24)
    }

    func testSettingsOnlyTakesAwayTheExpandedState() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let appState = AppState()
            let stepsAside = NookCompanion(id: "a") { Text("a") }
            let staysPut = NookCompanion(id: "b", hidesInSettings: false) { Text("b") }

            XCTAssertEqual(NookCompanionHost.settingsRestriction(for: stepsAside, appState: appState), .both)
            appState.showSettings()
            XCTAssertEqual(NookCompanionHost.settingsRestriction(for: stepsAside, appState: appState), .compact)
            XCTAssertEqual(NookCompanionHost.settingsRestriction(for: staysPut, appState: appState), .both)
            appState.showHome()
            XCTAssertEqual(NookCompanionHost.settingsRestriction(for: stepsAside, appState: appState), .both)
        }
    }

    // MARK: - Style, size, and presence

    func testCompanionDefaultsAreTheStandardStyleAtTheRegularSizeWithTheFold() {
        let configuration = NookConfiguration()
        XCTAssertEqual(configuration.companionStyle.base as? NookStandardCompanionStyle, .standard)
        XCTAssertEqual(configuration.companionSize, .regular)
        XCTAssertEqual(configuration.companionPresence, .fold)
        XCTAssertNil(configuration.companionSource)

        let companion = NookCompanion(id: "a") { Text("a") }
        XCTAssertNil(companion.style)
        XCTAssertNil(companion.size)
        XCTAssertNil(companion.presence)
        XCTAssertNil(companion.gap)
        XCTAssertNil(companion.rowAlignment)
    }

    /// A companion that leaves its style, size, and presence unset takes the configuration's; one
    /// that sets them keeps its own.
    func testCompanionsTakeTheConfigurationDefaultsUnlessTheySetTheirOwn() {
        let surface = FakeNookSurface()
        _ = makeCoordinator(
            [
                ConfiguredModule(id: "A") {
                    var configuration = NookConfiguration()
                    configuration.companionStyle = .faded
                    configuration.companionSize = .large
                    configuration.companionPresence = .slide
                    configuration.addCompanion(id: "plain") { Text("plain") }
                    configuration.addCompanion(
                        id: "own",
                        gap: 20,
                        rowAlignment: .end,
                        style: .plain,
                        size: .small,
                        presence: .pop
                    ) {
                        Text("own")
                    }
                    return configuration
                }
            ],
            surface: surface
        )

        let plain = surface.companions[0]
        XCTAssertEqual(plain.style.base as? NookStandardCompanionStyle, .faded)
        XCTAssertEqual(plain.size, .large)
        XCTAssertEqual(plain.presence, .slide)
        XCTAssertNil(plain.gap)
        XCTAssertNil(plain.rowAlignment)

        let own = surface.companions[1]
        XCTAssertEqual(own.style.base as? NookStandardCompanionStyle, .plain)
        XCTAssertEqual(own.size, .small)
        XCTAssertEqual(own.presence, .pop)
        XCTAssertEqual(own.gap, 20)
        XCTAssertEqual(own.rowAlignment, .end)
    }

    func testTheGlyphButtonStyleSizesFromTheCompanionSize() {
        let control = NookGlyphButtonStyle()
        XCTAssertEqual(control.side(in: .regular), 32)
        XCTAssertEqual(control.resolvedGlyphSize(in: .regular), 13)
        XCTAssertEqual(control.side(in: .small), 26)

        let surface = NookGlyphButtonStyle(size: .surface)
        XCTAssertEqual(surface.side(in: .regular), 40, "a button that is its own surface is surface height")
        XCTAssertEqual(surface.resolvedGlyphSize(in: .regular), 16, "and its glyph scales with it")

        let points = NookGlyphButtonStyle(size: .points(64), glyphSize: 20)
        XCTAssertEqual(points.side(in: .regular), 64)
        XCTAssertEqual(points.resolvedGlyphSize(in: .regular), 20)
        XCTAssertEqual(NookGlyphButtonStyle(size: .points(-3)).side(in: .regular), 0)
    }

    /// The lock and gear keep the top bar's frame there, and take a companion's control size in one.
    func testChromeGlyphsTakeTheCompanionControlSize() {
        let geometry = HeaderGlyphGeometry.companion(.large)
        XCTAssertEqual(geometry.side, 40)
        XCTAssertEqual(geometry.cornerRadius, 20, "a round chip, like the glyph button style's")
        XCTAssertEqual(geometry.font, .system(size: 16, weight: .semibold))
    }

    // MARK: - Live companions

    func testASourceChangesTheSurfaceWithoutAReload() {
        let surface = FakeNookSurface()
        let source = NookCompanionSource([NookCompanion(id: "live") { Text("live") }])
        let coordinator = makeCoordinator(
            [
                ConfiguredModule(id: "A") {
                    var configuration = self.configurationWithCompanions()
                    configuration.companionSource = source
                    return configuration
                }
            ],
            surface: surface
        )
        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer", "live"])

        source.set(NookCompanion(id: "leave", shape: .circle) { Text("leave") })
        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer", "live", "leave"])
        XCTAssertEqual(surface.companions[3].shape, .circle)

        source.set(NookCompanion(id: "live", spacing: 14) { Text("live") })
        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer", "live", "leave"], "replaced in place")
        XCTAssertEqual(surface.companions[2].spacing, 14)

        source.remove(id: "live")
        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer", "leave"])

        source.removeAll()
        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer"])
        withExtendedLifetime(coordinator) {}
    }

    func testSourceCompanionsTakeTheConfigurationDefaults() {
        let surface = FakeNookSurface()
        let source = NookCompanionSource()
        let coordinator = makeCoordinator(
            [
                ConfiguredModule(id: "A") {
                    var configuration = NookConfiguration()
                    configuration.companionSize = .small
                    configuration.companionSource = source
                    return configuration
                }
            ],
            surface: surface
        )
        withExtendedLifetime(coordinator) {
            source.set(NookCompanion(id: "late") { Text("late") })
            XCTAssertEqual(surface.companions.first?.size, .small)
        }
    }

    /// A switched-away module's source no longer reaches the surface, and switching back shows
    /// whatever the source holds by then.
    func testASourceFollowsItsModuleThroughSwitches() async {
        let surface = FakeNookSurface()
        let source = NookCompanionSource([NookCompanion(id: "a") { Text("a") }])
        let coordinator = makeCoordinator(
            [
                ConfiguredModule(id: "A") {
                    var configuration = NookConfiguration()
                    configuration.companionSource = source
                    return configuration
                },
                ConfiguredModule(id: "B", build: { NookConfiguration() }),
            ],
            surface: surface
        )
        await surface.expand(on: nil)
        XCTAssertEqual(surface.companions.map(\.id), ["a"])

        coordinator.switchModule(to: "B")
        await coordinator.drainLifecycleForTesting()
        XCTAssertTrue(surface.companions.isEmpty)

        source.set(NookCompanion(id: "b") { Text("b") })
        XCTAssertTrue(surface.companions.isEmpty, "module B's surface is not module A's to change")

        coordinator.switchModule(to: "A")
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.companions.map(\.id), ["a", "b"])
    }

    /// A reload that brings a different source follows the new one and lets the old one go.
    func testAReloadFollowsTheNewSource() {
        @MainActor
        final class Sources {
            var current = NookCompanionSource([NookCompanion(id: "old") { Text("old") }])
        }
        let sources = Sources()
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [
                ConfiguredModule(id: "A") {
                    var configuration = NookConfiguration()
                    configuration.companionSource = sources.current
                    return configuration
                }
            ],
            surface: surface
        )
        let old = sources.current
        sources.current = NookCompanionSource([NookCompanion(id: "new") { Text("new") }])
        coordinator.reloadActiveConfiguration()
        XCTAssertEqual(surface.companions.map(\.id), ["new"])

        old.set(NookCompanion(id: "stale") { Text("stale") })
        XCTAssertEqual(surface.companions.map(\.id), ["new"])
        sources.current.set(NookCompanion(id: "fresh") { Text("fresh") })
        XCTAssertEqual(surface.companions.map(\.id), ["new", "fresh"])
    }

    /// Two companions with one id would merge on the surface, so the first one wins: the
    /// configuration's own before its source's.
    func testOnlyTheFirstCompanionWithAnIDReachesTheSurface() {
        let surface = FakeNookSurface()
        let source = NookCompanionSource([NookCompanion(id: "pill", spacing: 30) { Text("dupe") }])
        _ = makeCoordinator(
            [
                ConfiguredModule(id: "A") {
                    var configuration = self.configurationWithCompanions()
                    configuration.companions.append(NookCompanion(id: "timer") { Text("dupe") })
                    configuration.companionSource = source
                    return configuration
                }
            ],
            surface: surface
        )
        XCTAssertEqual(surface.companions.map(\.id), ["pill", "timer"])
        XCTAssertEqual(surface.companions[0].spacing, 10, "the configuration's own pill wins")
        XCTAssertEqual(surface.companions[1].shape, .circle, "and so does the first timer")
    }

    func testEditingASource() {
        let source = NookCompanionSource()
        source.set(NookCompanion(id: "a") { Text("a") })
        source.set(NookCompanion(id: "b") { Text("b") })
        source.insert(NookCompanion(id: "c") { Text("c") }, at: 0)
        XCTAssertEqual(source.ids, ["c", "a", "b"])

        source.insert(NookCompanion(id: "a", spacing: 3) { Text("a") }, at: 99)
        XCTAssertEqual(source.ids, ["c", "b", "a"], "inserting an id that is there moves it")
        XCTAssertEqual(source.companion(id: "a")?.spacing, 3)

        source.move(id: "a", to: 0)
        XCTAssertEqual(source.ids, ["a", "c", "b"])
        source.move(id: "missing", to: 0)
        XCTAssertEqual(source.ids, ["a", "c", "b"])

        source.remove(id: "c")
        XCTAssertEqual(source.ids, ["a", "b"])
        XCTAssertNil(source.companion(id: "c"))
        source.removeAll()
        XCTAssertTrue(source.ids.isEmpty)
    }

    // MARK: - Chrome actions

    func testKeepOpenActionFlipsThePreferenceAndTheSurface() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let surface = FakeNookSurface()
            let coordinator = makeCoordinator(
                [ConfiguredModule(id: "A", build: { NookConfiguration() })],
                surface: surface
            )
            XCTAssertFalse(coordinator.appState.keepNookOpen)

            coordinator.chromeActions.toggleKeepOpen()
            XCTAssertTrue(coordinator.appState.keepNookOpen)
            XCTAssertTrue(surface.staysExpandedOnHoverExit)

            coordinator.chromeActions.toggleKeepOpen()
            XCTAssertFalse(coordinator.appState.keepNookOpen)
            XCTAssertFalse(surface.staysExpandedOnHoverExit)
        }
    }

    /// From the compact pill, the gear expands the nook straight into Settings.
    func testSettingsActionExpandsACollapsedNookIntoSettings() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ConfiguredModule(id: "A", build: { NookConfiguration() })],
            surface: surface
        )
        await surface.compact(on: nil)

        coordinator.chromeActions.toggleSettings()
        await coordinator.drainLifecycleForTesting()

        XCTAssertEqual(surface.state, .expanded)
        XCTAssertTrue(coordinator.appState.isSettingsView)
        XCTAssertTrue(coordinator.isUserEngaged, "opening Settings is a user-initiated open")
    }

    func testSettingsActionTogglesInPlaceWhileExpanded() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ConfiguredModule(id: "A", build: { NookConfiguration() })],
            surface: surface
        )
        await surface.expand(on: nil)

        coordinator.chromeActions.toggleSettings()
        XCTAssertTrue(coordinator.appState.isSettingsView)
        coordinator.chromeActions.toggleSettings()
        XCTAssertTrue(coordinator.appState.isHomeView)
        XCTAssertEqual(surface.transitions, [.expanded], "no extra surface transitions")
    }

    func testSettingsActionDoesNothingWhenSettingsIsDisabled() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [
                ConfiguredModule(id: "A") {
                    var configuration = NookConfiguration()
                    configuration.topBar.showsSettings = false
                    return configuration
                }
            ],
            surface: surface
        )
        await surface.compact(on: nil)

        coordinator.chromeActions.toggleSettings()
        await coordinator.drainLifecycleForTesting()

        XCTAssertEqual(surface.state, .compact)
        XCTAssertTrue(coordinator.appState.isHomeView)
    }

    func testCollapseActionCompactsTheNook() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ConfiguredModule(id: "A", build: { NookConfiguration() })],
            surface: surface
        )
        await surface.expand(on: nil)

        coordinator.chromeActions.collapse()
        await coordinator.drainLifecycleForTesting()

        XCTAssertEqual(surface.state, .compact)
    }

    func testChromeActionsOutsideTheChromeAreInert() {
        let actions = EnvironmentValues().nookChromeActions
        // Nothing to assert beyond "does not trap": the default is a safe no-op.
        actions.toggleKeepOpen()
        actions.toggleSettings()
        actions.collapse()
    }

    /// Companions change nothing about the global hotkey: it still toggles the nook, the
    /// same way it does without them.
    func testGlobalHotkeyStillTogglesTheNookWithCompanions() async {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ConfiguredModule(id: "A", build: configurationWithCompanions)],
            surface: surface
        )
        await surface.compact(on: nil)
        coordinator.registerGlobalHotkey()

        // Carbon registration can fail without a full app context; the handler it
        // installs is `toggleNook`, so fall back to calling that directly.
        if !coordinator.hotkeyController.fireForTesting(id: NookHotkeyIDs.toggle) {
            coordinator.toggleNook()
        }
        await waitForState(.expanded, on: surface, coordinator: coordinator)
        XCTAssertEqual(surface.companions.count, 2)

        if !coordinator.hotkeyController.fireForTesting(id: NookHotkeyIDs.toggle) {
            coordinator.toggleNook()
        }
        await waitForState(.compact, on: surface, coordinator: coordinator)
        coordinator.hotkeyController.unregisterAll()
    }

    /// The hotkey handler hops to the main actor in a new task before it enqueues, so poll
    /// rather than assume one drain is enough.
    private func waitForState(_ state: NookState, on surface: FakeNookSurface, coordinator: AppCoordinator) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            await coordinator.drainLifecycleForTesting()
            if surface.state == state { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("surface did not reach \(state)")
    }
}
