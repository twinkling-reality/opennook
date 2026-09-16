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
