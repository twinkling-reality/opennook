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

/// Coverage for changing a running chrome's configuration: `reloadActiveConfiguration()`,
/// `replaceChromeBehavior(_:)`, and the settable `Nook.style` / `Nook.hoverBehavior` they
/// project onto.
@MainActor
final class LiveConfigurationTests: XCTestCase {
    /// A module that rebuilds its configuration from mutable state, and counts the builds and
    /// the lifecycle calls a reload must not make.
    private final class TunableModule: NookModule {
        let descriptor: NookModuleDescriptor
        var tune: (inout NookConfiguration) -> Void = { _ in }
        private(set) var buildCount = 0
        private(set) var activateCount = 0
        private(set) var deactivateCount = 0

        init(id: String) {
            descriptor = NookModuleDescriptor(id: id, displayName: id, backgroundPolicy: .stayResident)
        }

        func makeConfiguration() -> NookConfiguration {
            buildCount += 1
            var configuration = NookConfiguration()
            tune(&configuration)
            return configuration
        }

        func onActivate() { activateCount += 1 }
        func onDeactivate() { deactivateCount += 1 }
    }

    /// Shared between a test and the closures its configurations carry.
    private final class Log: @unchecked Sendable {
        var entries: [String] = []
    }

    private func makeCoordinator(
        _ modules: [TunableModule],
        surface: FakeNookSurface,
        appState: AppState = AppState(),
        chromeBehavior: NookChromeBehavior = .default
    ) -> AppCoordinator {
        var host = NookHostConfiguration()
        host.chromeBehavior = chromeBehavior
        for module in modules {
            let captured = module
            host.register(captured.descriptor) { _ in captured }
        }
        host.defaultModule = modules[0].descriptor.id
        return AppCoordinator(
            appState: appState,
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: surface
        )
    }

    // MARK: - reloadActiveConfiguration

    func testReloadRebuildsTheConfigurationWithoutReactivatingTheModule() async {
        let module = TunableModule(id: "A")
        let readyLog = Log()
        module.tune = { configuration in
            configuration.expandedWidth = 300
            configuration.onReady = { _ in readyLog.entries.append("ready") }
        }
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([module], surface: surface)
        coordinator.start()
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(coordinator.configuration.expandedWidth, 300)
        XCTAssertEqual(module.buildCount, 1)
        XCTAssertEqual(readyLog.entries, ["ready"])

        module.tune = { configuration in
            configuration.expandedWidth = 420
            configuration.topBar.showsKeepOpenButton = false
            configuration.onReady = { _ in readyLog.entries.append("ready again") }
        }
        coordinator.reloadActiveConfiguration()

        XCTAssertEqual(coordinator.configuration.expandedWidth, 420)
        XCTAssertFalse(coordinator.configuration.topBar.showsKeepOpenButton)
        XCTAssertEqual(module.buildCount, 2)
        XCTAssertEqual(module.activateCount, 0, "a reload is not an activation")
        XCTAssertEqual(module.deactivateCount, 0)
        XCTAssertEqual(readyLog.entries, ["ready"], "onReady fires once per loaded module, not per reload")
        XCTAssertEqual(coordinator.activeModuleID, "A")
    }

    func testReloadProjectsHooksAndDecorationsOntoTheSurface() {
        let module = TunableModule(id: "A")
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([module], surface: surface)
        XCTAssertTrue(surface.companions.isEmpty)
        XCTAssertNil(surface.onExpand)
        XCTAssertEqual(surface.onFileDrop?([]), false)

        let log = Log()
        module.tune = { configuration in
            configuration.addCompanion(id: "pill", anchor: .leading, visibility: .both) { Text("pill") }
            configuration.rimGlow = NookRimGlowStyle(lineWidth: 3, pulses: false)
            configuration.scrollEdgeFade = NookScrollEdgeFade(edges: .bottom, length: 30)
            configuration.onExpand = { log.entries.append("expand") }
            configuration.onFileDrop = { _ in true }
        }
        coordinator.reloadActiveConfiguration()

        XCTAssertEqual(surface.companions.map(\.id), ["pill"])
        XCTAssertEqual(surface.companions.first?.anchor, .leading)
        XCTAssertEqual(surface.companions.first?.visibility, .both)
        XCTAssertEqual(surface.rimGlowStyle, NookRimGlowStyle(lineWidth: 3, pulses: false))
        XCTAssertEqual(surface.scrollEdgeFade, NookScrollEdgeFade(edges: .bottom, length: 30))
        surface.onExpand?()
        XCTAssertEqual(log.entries, ["expand"])
        XCTAssertEqual(surface.onFileDrop?([]), true)

        module.tune = { _ in }
        coordinator.reloadActiveConfiguration()

        XCTAssertTrue(surface.companions.isEmpty)
        XCTAssertEqual(surface.rimGlowStyle, .standard)
        XCTAssertNil(surface.scrollEdgeFade)
        XCTAssertNil(surface.onExpand)
        XCTAssertEqual(surface.onFileDrop?([]), false, "an unset drop handler rejects, as at launch")
    }

    func testReloadAppliesStyleAndTransitions() {
        let module = TunableModule(id: "A")
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([module], surface: surface)
        let style = NookStyle(
            topCornerRadius: 10,
            bottomCornerRadius: 30,
            expandedContentInsets: NookEdgeInsets(top: 2, bottom: 12, leading: 6, trailing: 6)
        )
        let opening = Animation.easeIn(duration: 0.9)

        module.tune = { configuration in
            configuration.style = style
            configuration.transitions = NookTransitionConfiguration(
                openingAnimation: opening,
                animationDuration: 0.9,
                layoutGraceDuration: 0.3
            )
        }
        coordinator.reloadActiveConfiguration()

        XCTAssertEqual(surface.style, style)
        XCTAssertEqual(surface.transitionConfiguration.openingAnimation, opening)
        XCTAssertEqual(surface.transitionConfiguration.layoutGraceDuration, 0.3)

        module.tune = { _ in }
        coordinator.reloadActiveConfiguration()

        XCTAssertEqual(surface.style, NookConfiguration.defaultStyle, "an unset style falls back to the default")
        XCTAssertEqual(
            surface.transitionConfiguration.openingAnimation,
            AppCoordinator.defaultTransitions.openingAnimation
        )
        XCTAssertNil(surface.transitionConfiguration.layoutGraceDuration)
    }

    func testReloadLeavesSettingsOnlyWhenTheNewConfigurationDisablesIt() {
        let module = TunableModule(id: "A")
        let appState = AppState()
        let coordinator = makeCoordinator([module], surface: FakeNookSurface(), appState: appState)
        appState.showSettings()

        coordinator.reloadActiveConfiguration()
        XCTAssertEqual(appState.viewMode, .settings, "Settings stays open while the configuration allows it")

        module.tune = { $0.topBar.showsSettings = false }
        coordinator.reloadActiveConfiguration()
        XCTAssertEqual(appState.viewMode, .home)
    }

    func testReloadKeepsTheSurfaceStateAndFiresNoLifecycleHooks() async {
        let module = TunableModule(id: "A")
        let log = Log()
        module.tune = { $0.onExpand = { log.entries.append("expand") } }
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([module], surface: surface)
        await surface.expand(on: nil)
        XCTAssertEqual(log.entries, ["expand"])
        let transitions = surface.transitions

        coordinator.reloadActiveConfiguration()
        await coordinator.drainLifecycleForTesting()

        XCTAssertEqual(surface.state, .expanded)
        XCTAssertEqual(surface.transitions, transitions, "a reload never moves the surface")
        XCTAssertEqual(log.entries, ["expand"], "unlike a switch, a reload fires no synthetic onExpand")
    }

    func testReloadRebuildsOnlyTheActiveModule() async {
        let a = TunableModule(id: "A")
        let b = TunableModule(id: "B")
        let coordinator = makeCoordinator([a, b], surface: FakeNookSurface())
        coordinator.switchModule(to: "B")
        await coordinator.drainLifecycleForTesting()
        let aBuilds = a.buildCount
        let bBuilds = b.buildCount

        b.tune = { $0.expandedWidth = 360 }
        coordinator.reloadActiveConfiguration()

        XCTAssertEqual(a.buildCount, aBuilds)
        XCTAssertEqual(b.buildCount, bBuilds + 1)
        XCTAssertEqual(coordinator.configuration.expandedWidth, 360)
    }

    /// The production surface is a real `Nook`; a reload restyles it in place.
    func testReloadRestylesTheProductionNook() throws {
        final class StyleBox: @unchecked Sendable {
            var style: NookStyle?
        }
        let box = StyleBox()
        var host = NookHostConfiguration()
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) {
            var configuration = NookConfiguration()
            configuration.style = box.style
            return configuration
        }
        let coordinator = AppCoordinator(moduleHost: ModuleHost(registry: host.makeRegistry()))
        let nook = try XCTUnwrap(coordinator.surface as? Nook<AnyView, AnyView, AnyView>)
        XCTAssertEqual(nook.style, NookConfiguration.defaultStyle)

        let style = NookStyle(topCornerRadius: 8, bottomCornerRadius: 28)
        box.style = style
        coordinator.reloadActiveConfiguration()

        XCTAssertEqual(nook.style, style)
    }

    // MARK: - replaceChromeBehavior

    func testReplaceChromeBehaviorAppliesHoverBehaviorAndBackdrop() {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([TunableModule(id: "A")], surface: surface)
        coordinator.syncNotchBackdrop()
        let launchBackdrop = surface.backdrop

        coordinator.replaceChromeBehavior(
            NookChromeBehavior(
                hoverBehavior: .all,
                showsLaunchShimmer: false,
                backdrop: { _ in .solid(.red) }
            )
        )

        XCTAssertEqual(surface.hoverBehavior, .all)
        XCTAssertEqual(surface.backdrop, .solid(.red), "the new resolver applies right away")
        XCTAssertEqual(coordinator.moduleHost.chromeBehavior.hoverBehavior, .all)
        XCTAssertFalse(coordinator.moduleHost.chromeBehavior.showsLaunchShimmer)
        XCTAssertEqual(
            coordinator.moduleHost.registry.chromeBehavior.hoverBehavior,
            [],
            "the registry keeps the launch value"
        )

        coordinator.replaceChromeBehavior(.default)

        XCTAssertEqual(surface.hoverBehavior, [])
        XCTAssertEqual(surface.backdrop, launchBackdrop, "no resolver means the framework mapping again")
    }

    func testReplacedBackdropResolverFollowsLaterAppearanceChanges() {
        let appState = AppState()
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([TunableModule(id: "A")], surface: surface, appState: appState)
        coordinator.replaceChromeBehavior(
            NookChromeBehavior(backdrop: { context in
                context.preferences.chromePalette == .light ? .solid(.white) : .solid(.blue)
            })
        )
        appState.appearancePreferences.chromePalette = .dark
        coordinator.syncNotchBackdrop()
        XCTAssertEqual(surface.backdrop, .solid(.blue))

        appState.appearancePreferences.chromePalette = .light
        coordinator.syncNotchBackdrop()
        XCTAssertEqual(surface.backdrop, .solid(.white))
    }

    // MARK: - Nook

    func testNookStyleAndHoverBehaviorAreSettable() {
        let nook = Nook(hoverBehavior: [], expanded: { Text("x") }, compactLeading: { Text("L") })
        var changes = 0
        let subscription = nook.objectWillChange.sink { changes += 1 }
        let style = NookStyle(topCornerRadius: 4, bottomCornerRadius: 12)

        nook.style = style
        nook.hoverBehavior = .all

        XCTAssertEqual(nook.style, style)
        XCTAssertEqual(changes, 1, "a style change re-renders the chrome")
        XCTAssertEqual(nook.hoverBehavior, .all)
        withExtendedLifetime(subscription) {}
    }
}
