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

/// The module-switch lifecycle under both background policies, a background module's
/// urgent claim putting that module's content on the surface, and the per-module
/// breadcrumb.
@MainActor
final class ModuleSwitchLifecycleTests: XCTestCase {
    /// Records every lifecycle event, from every module, in one ordered list.
    private final class EventLog {
        var events: [String] = []
    }

    /// A module that logs its lifecycle and tags its configuration so a test can tell
    /// which module's configuration the surface shows.
    private final class LoggingModule: NookModule {
        let descriptor: NookModuleDescriptor
        let log: EventLog
        /// Runs inside `prepareForSwitchAway`, after the event is logged.
        var quiesceWork: (@MainActor () async -> Void)?

        init(id: String, policy: NookModuleDescriptor.BackgroundPolicy, log: EventLog) {
            self.descriptor = NookModuleDescriptor(id: id, displayName: id, backgroundPolicy: policy)
            self.log = log
        }

        /// The tag a configuration built by module `id` carries in `expandedWidth`.
        static func tag(_ id: String) -> CGFloat { 400 + CGFloat(id.unicodeScalars.first?.value ?? 0) }

        func makeConfiguration() -> NookConfiguration {
            var configuration = NookConfiguration()
            configuration.expandedWidth = Self.tag(descriptor.id)
            configuration.addCompanion(id: "companion-\(descriptor.id)") { Text(self.descriptor.id) }
            return configuration
        }

        func onActivate() { log.events.append("activate:\(descriptor.id)") }
        func onDeactivate() { log.events.append("deactivate:\(descriptor.id)") }
        func prepareForSwitchAway() async {
            log.events.append("prepare:\(descriptor.id)")
            await quiesceWork?()
        }
    }

    private func makeCoordinator(
        _ modules: [LoggingModule],
        surface: FakeNookSurface = FakeNookSurface()
    ) -> AppCoordinator {
        var host = NookHostConfiguration()
        for module in modules {
            let captured = module
            host.register(captured.descriptor) { _ in captured }
        }
        host.defaultModule = modules[0].descriptor.id
        return AppCoordinator(
            appState: AppState(),
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: surface
        )
    }

    private func settle(_ coordinator: AppCoordinator) async {
        await coordinator.drainLifecycleForTesting()
        await coordinator.drainSwitchTailsForTesting()
    }

    // MARK: - Switch-away order

    /// `.unloadOnSwitchAway` (the default policy): `prepareForSwitchAway` runs - it used to
    /// be skipped because the module was unloaded first - then `onDeactivate`, then the
    /// unload. While the module quiesces it is still loaded and not yet deactivated.
    func testUnloadPolicyRunsPrepareThenDeactivateThenUnload() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .unloadOnSwitchAway, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])
        var stateDuringQuiesce: (loaded: Bool, deactivated: Bool)?
        a.quiesceWork = {
            stateDuringQuiesce = (
                coordinator.moduleHost.registry.isLoaded("A"),
                log.events.contains("deactivate:A")
            )
        }

        coordinator.switchModule(to: "B")
        await settle(coordinator)

        XCTAssertEqual(log.events, ["activate:B", "prepare:A", "deactivate:A"])
        XCTAssertEqual(stateDuringQuiesce?.loaded, true, "the module is still loaded while it quiesces")
        XCTAssertEqual(stateDuringQuiesce?.deactivated, false, "prepareForSwitchAway runs before onDeactivate")
        XCTAssertFalse(coordinator.moduleHost.registry.isLoaded("A"), "unloaded after onDeactivate")
    }

    /// `.stayResident`: `prepareForSwitchAway` runs before `onDeactivate`, and the module
    /// stays loaded.
    func testStayResidentRunsPrepareBeforeDeactivate() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .stayResident, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])

        coordinator.switchModule(to: "B")
        await settle(coordinator)

        XCTAssertEqual(log.events, ["activate:B", "prepare:A", "deactivate:A"])
        XCTAssertTrue(coordinator.moduleHost.registry.isLoaded("A"))
    }

    /// An unloaded module gets a fresh `onReady` each time it is built again. (The test never
    /// calls `start()`, so the launch module's first `onReady` is not counted.)
    func testUnloadedModuleGetsOnReadyAgain() async {
        @MainActor final class ReadyCount { var value = 0 }
        let count = ReadyCount()
        var host = NookHostConfiguration()
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) {
            var configuration = NookConfiguration()
            configuration.onReady = { _ in count.value += 1 }
            return configuration
        }
        host.register(NookModuleDescriptor(id: "B", displayName: "B")) { NookConfiguration() }
        let coordinator = AppCoordinator(
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: FakeNookSurface()
        )

        for id in ["B", "A", "B", "A"] {
            coordinator.switchModule(to: id)
            await settle(coordinator)
        }

        XCTAssertEqual(count.value, 2, "A got onReady on each return, as it was unloaded in between")
    }

    /// A quick A to B to A: the switch back lands while A's switch away is still pending, so
    /// A is never deactivated or unloaded under the user, and B is finished normally.
    func testRapidSwitchBackKeepsModuleLoadedAndActive() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .unloadOnSwitchAway, log: log)
        let b = LoggingModule(id: "B", policy: .unloadOnSwitchAway, log: log)
        let coordinator = makeCoordinator([a, b])

        coordinator.switchModule(to: "B")
        coordinator.switchModule(to: "A")
        await settle(coordinator)

        XCTAssertEqual(coordinator.activeModuleID, "A")
        XCTAssertTrue(coordinator.moduleHost.registry.isLoaded("A"))
        XCTAssertFalse(log.events.contains("deactivate:A"), "the switch away from A was superseded")
        XCTAssertEqual(log.events.filter { $0 == "deactivate:B" }.count, 1)
        XCTAssertFalse(coordinator.moduleHost.registry.isLoaded("B"))
        XCTAssertEqual(log.events.last, "deactivate:B")
    }

    /// While a module's switch away is running, the arbiter denies it the surface - even
    /// with an urgent claim - and lets it back once the switch away has finished.
    func testModuleIsDeniedTheSurfaceWhileSwitchingAway() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .stayResident, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])
        var tokenDuringQuiesce: NookSurfaceToken?
        a.quiesceWork = {
            tokenDuringQuiesce = await coordinator.beginTransientPresentation(
                NookSurfaceClaim(moduleID: "A", priority: .urgent)
            )
        }

        coordinator.switchModule(to: "B")
        await settle(coordinator)

        XCTAssertNil(tokenDuringQuiesce, "a module mid switch-away gets no claim")
        let after = await coordinator.beginTransientPresentation(NookSurfaceClaim(moduleID: "A", priority: .urgent))
        XCTAssertNotNil(after, "a resident background module may claim urgently once switched away")
    }

    // MARK: - Background module content

    /// A background module's urgent claim puts *its* content, companions included, on the
    /// surface; when the claim ends the surface collapses and goes back to the foreground
    /// module.
    func testBackgroundUrgentClaimShowsClaimingModule() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .stayResident, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([a, b], surface: surface)
        await surface.compact(on: nil)
        // B is resident in the background: it ran once and was switched away from.
        coordinator.switchModule(to: "B")
        coordinator.switchModule(to: "A")
        await settle(coordinator)
        let host = coordinator.moduleHost

        let token = await coordinator.beginTransientPresentation(NookSurfaceClaim(moduleID: "B", priority: .urgent))

        XCTAssertNotNil(token)
        XCTAssertEqual(surface.state, .expanded)
        XCTAssertEqual(host.activeModuleID, "A", "the claim does not switch modules")
        XCTAssertEqual(host.displayedModuleID, "B")
        XCTAssertEqual(host.displayedConfiguration.expandedWidth, LoggingModule.tag("B"))
        XCTAssertEqual(surface.companions.map(\.id), ["companion-B"])

        await coordinator.endTransientPresentation(token!)

        XCTAssertEqual(surface.state, .compact, "restored to the pre-claim state")
        XCTAssertEqual(host.displayedModuleID, "A")
        XCTAssertEqual(host.displayedConfiguration.expandedWidth, LoggingModule.tag("A"))
        XCTAssertEqual(surface.companions.map(\.id), ["companion-A"])
    }

    /// Stacked claims: the surface shows whichever module's claim is on top, and goes back
    /// to the preempted one when the top claim ends.
    func testPreemptedClaimGetsItsContentBack() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .stayResident, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])
        coordinator.switchModule(to: "B")
        coordinator.switchModule(to: "A")
        await settle(coordinator)
        let host = coordinator.moduleHost

        let foreground = await coordinator.beginTransientPresentation(
            NookSurfaceClaim(moduleID: "A", priority: .normal)
        )
        XCTAssertEqual(host.displayedModuleID, "A")
        let background = await coordinator.beginTransientPresentation(
            NookSurfaceClaim(moduleID: "B", priority: .urgent)
        )
        XCTAssertNotNil(background)
        XCTAssertEqual(host.displayedModuleID, "B", "the urgent background claim preempts")

        await coordinator.endTransientPresentation(background!)
        XCTAssertEqual(host.displayedModuleID, "A", "the preempted foreground claim is on top again")
        await coordinator.endTransientPresentation(foreground!)
        XCTAssertEqual(host.displayedModuleID, "A")
    }

    /// Switching to the module whose background claim is on screen makes it the active
    /// module; it is no longer presented as a background one.
    func testSwitchToPresentingModuleEndsBackgroundPresentation() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .stayResident, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])
        coordinator.switchModule(to: "B")
        coordinator.switchModule(to: "A")
        await settle(coordinator)

        _ = await coordinator.beginTransientPresentation(NookSurfaceClaim(moduleID: "B", priority: .urgent))
        coordinator.switchModule(to: "B")
        await settle(coordinator)

        XCTAssertEqual(coordinator.activeModuleID, "B")
        XCTAssertNil(coordinator.moduleHost.presentedBackgroundModuleID)
        XCTAssertEqual(coordinator.moduleHost.displayedConfiguration.expandedWidth, LoggingModule.tag("B"))
    }

    // MARK: - Breadcrumb

    /// The breadcrumb belongs to the module that set it: a switch clears it for the
    /// incoming module, and a resident module gets its own back when the user returns.
    func testBreadcrumbFollowsTheDisplayedModule() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .stayResident, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])
        let appState = coordinator.appState

        appState.moduleBreadcrumb = "Deck"
        coordinator.switchModule(to: "B")
        await settle(coordinator)
        XCTAssertNil(appState.moduleBreadcrumb, "A's breadcrumb does not leak into B")

        appState.moduleBreadcrumb = "Profile"
        coordinator.switchModule(to: "A")
        await settle(coordinator)
        XCTAssertEqual(appState.moduleBreadcrumb, "Deck", "the resident module returns to its breadcrumb")

        coordinator.switchModule(to: "B")
        await settle(coordinator)
        XCTAssertEqual(appState.moduleBreadcrumb, "Profile")
    }

    /// An unloaded module starts again at its root, so its old breadcrumb is dropped.
    func testUnloadedModuleBreadcrumbIsDropped() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .unloadOnSwitchAway, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])
        let appState = coordinator.appState

        appState.moduleBreadcrumb = "Deck"
        coordinator.switchModule(to: "B")
        await settle(coordinator)
        coordinator.switchModule(to: "A")
        await settle(coordinator)

        XCTAssertNil(appState.moduleBreadcrumb)
    }

    /// A background module presenting over the active one does not show the active
    /// module's breadcrumb, which comes back when the presentation ends.
    func testBackgroundPresentationParksTheBreadcrumb() async {
        let log = EventLog()
        let a = LoggingModule(id: "A", policy: .stayResident, log: log)
        let b = LoggingModule(id: "B", policy: .stayResident, log: log)
        let coordinator = makeCoordinator([a, b])
        coordinator.switchModule(to: "B")
        coordinator.switchModule(to: "A")
        await settle(coordinator)
        let appState = coordinator.appState

        appState.moduleBreadcrumb = "Deck"
        let token = await coordinator.beginTransientPresentation(NookSurfaceClaim(moduleID: "B", priority: .urgent))
        XCTAssertNil(appState.moduleBreadcrumb)

        await coordinator.endTransientPresentation(token!)
        XCTAssertEqual(appState.moduleBreadcrumb, "Deck")
    }
}
