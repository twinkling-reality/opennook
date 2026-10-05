// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import XCTest

@testable import NookKit

/// Direct coverage for ``ModuleHost``: the attention/badging API, the single-
/// configuration convenience init, and the bare `switchModule` bookkeeping. The
/// surface-side effects (hook re-wiring, synthetic onExpand, arbiter invalidation)
/// live in `AppCoordinator` and are covered by ``AppCoordinatorTests``.
@MainActor
final class ModuleHostTests: XCTestCase {
    /// A minimal `NookModule` with distinguishable onActivate / onDeactivate counters.
    private final class StubModule: NookModule {
        let descriptor: NookModuleDescriptor
        private(set) var activateCount = 0
        private(set) var deactivateCount = 0

        init(id: String, backgroundPolicy: NookModuleDescriptor.BackgroundPolicy = .stayResident) {
            descriptor = NookModuleDescriptor(
                id: id,
                displayName: id,
                backgroundPolicy: backgroundPolicy
            )
        }

        func makeConfiguration() -> NookConfiguration { NookConfiguration() }
        func onActivate() { activateCount += 1 }
        func onDeactivate() { deactivateCount += 1 }
        func prepareForSwitchAway() async {}
    }

    private func makeHost(_ modules: [StubModule], defaultID: String? = nil) -> ModuleHost {
        var config = NookHostConfiguration()
        for module in modules {
            let m = module
            config.register(m.descriptor) { _ in m }
        }
        if let defaultID { config.defaultModule = defaultID }
        return ModuleHost(registry: config.makeRegistry())
    }

    // MARK: - Attention API

    /// `requestAttention(for:)` inserts the module id into `attentionModuleIDs`.
    func testRequestAttentionInsertsBackgroundModule() {
        let a = StubModule(id: "A")
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        host.requestAttention(for: "B")
        XCTAssertEqual(host.attentionModuleIDs, ["B"])
    }

    /// `requestAttention(for:)` is a no-op for the foreground module - it is already on
    /// screen so there is nothing to badge.
    func testRequestAttentionIsNoOpForForegroundModule() {
        let a = StubModule(id: "A")
        let host = makeHost([a])

        host.requestAttention(for: "A")
        XCTAssertTrue(host.attentionModuleIDs.isEmpty)
    }

    /// `clearAttention(for:)` removes the module id; idempotent on a missing id.
    func testClearAttentionRemovesBadge() {
        let a = StubModule(id: "A")
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        host.requestAttention(for: "B")
        host.clearAttention(for: "B")
        XCTAssertTrue(host.attentionModuleIDs.isEmpty)
        // Clearing a non-existent badge is a safe no-op.
        host.clearAttention(for: "B")
        host.clearAttention(for: "ghost")
        XCTAssertTrue(host.attentionModuleIDs.isEmpty)
    }

    /// Switching to a module clears its attention badge - the user has now seen it.
    func testSwitchClearsTargetModuleAttention() {
        let a = StubModule(id: "A")
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        host.requestAttention(for: "B")
        XCTAssertEqual(host.attentionModuleIDs, ["B"])

        XCTAssertTrue(host.switchModule(to: "B"))
        XCTAssertEqual(host.activeModuleID, "B")
        XCTAssertFalse(host.attentionModuleIDs.contains("B"), "switching to B clears B's badge")
    }

    /// `attentionModuleIDs` is `@Published` - observers see each update.
    func testAttentionModuleIDsIsPublished() {
        let a = StubModule(id: "A")
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        var snapshots: [Set<String>] = []
        let cancellable = host.$attentionModuleIDs.sink { snapshots.append($0) }
        defer { cancellable.cancel() }

        host.requestAttention(for: "B")
        host.requestAttention(for: "B")  // dedupe within the set
        host.clearAttention(for: "B")

        XCTAssertEqual(
            snapshots,
            [[], ["B"], ["B"], []],
            "snapshots include the initial empty value, then each distinct update"
        )
    }

    // MARK: - Single-configuration init

    /// The single-configuration convenience init registers exactly one module under the
    /// well-known singleModuleID, so the existing `NookApp.main(configuration:)` entry
    /// point is just a special case of the multi-module host.
    func testSingleConfigurationInitWrapsLoneModule() {
        let host = ModuleHost(configuration: NookConfiguration())

        XCTAssertEqual(host.descriptors.count, 1)
        XCTAssertEqual(host.activeModuleID, ModuleHost.singleModuleID)
        XCTAssertFalse(host.isMultiModule, "one module → no switcher")
    }

    // MARK: - switchModule bookkeeping

    /// `switchModule` returns `false` for an unknown id without touching state.
    func testSwitchToUnknownIDReturnsFalseAndIsNoOp() {
        let a = StubModule(id: "A")
        let host = makeHost([a])

        XCTAssertFalse(host.switchModule(to: "ghost"))
        XCTAssertEqual(host.activeModuleID, "A")
        XCTAssertEqual(a.deactivateCount, 0, "no module was deactivated")
    }

    /// `switchModule` to the already-active module returns `false` and does not
    /// re-trigger onActivate.
    func testSwitchToActiveModuleReturnsFalseWithoutSideEffects() {
        let a = StubModule(id: "A")
        let host = makeHost([a])

        // Force first construction so we have a baseline activate count.
        _ = host.activeModule
        let beforeActivate = a.activateCount

        XCTAssertFalse(host.switchModule(to: "A"))
        XCTAssertEqual(a.activateCount, beforeActivate, "no double-activation")
        XCTAssertEqual(a.deactivateCount, 0)
    }

    /// A successful switch activates the incoming module and re-publishes; the outgoing
    /// module is deactivated only by `finishSwitchAway(from:)`, which the coordinator calls
    /// after the module's `prepareForSwitchAway` has returned.
    func testSuccessfulSwitchFiresLifecycleHooks() {
        let a = StubModule(id: "A")
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        // Eager-construct both so on*activate counts start at known values.
        _ = host.registry.module(for: "A")
        _ = host.registry.module(for: "B")
        XCTAssertEqual(a.activateCount, 0, "first construction does not auto-activate")

        XCTAssertTrue(host.switchModule(to: "B"))

        XCTAssertEqual(a.deactivateCount, 0, "deactivation waits for finishSwitchAway")
        XCTAssertEqual(b.activateCount, 1)
        XCTAssertEqual(host.activeModuleID, "B")

        XCTAssertFalse(host.finishSwitchAway(from: "A"), "a .stayResident module stays loaded")
        XCTAssertEqual(a.deactivateCount, 1)
        XCTAssertTrue(host.registry.isLoaded("A"))
    }

    /// `finishSwitchAway(from:)` is a no-op for the module that is active again - a switch
    /// back that landed before the switch away finished.
    func testFinishSwitchAwayIgnoresActiveModule() {
        let a = StubModule(id: "A", backgroundPolicy: .unloadOnSwitchAway)
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        host.switchModule(to: "B")
        host.switchModule(to: "A")

        XCTAssertFalse(host.finishSwitchAway(from: "A"))
        XCTAssertEqual(a.deactivateCount, 0)
        XCTAssertTrue(host.registry.isLoaded("A"))
    }

    /// A switch to a module with `.unloadOnSwitchAway` unloads the outgoing module
    /// from the registry, so the next switch back rebuilds it from scratch.
    func testSwitchAwayUnloadsModuleWithUnloadPolicy() {
        let a = StubModule(id: "A", backgroundPolicy: .unloadOnSwitchAway)
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        // Force the registry to cache A.
        _ = host.registry.module(for: "A")
        XCTAssertTrue(host.registry.isLoaded("A"))

        host.switchModule(to: "B")
        XCTAssertTrue(host.registry.isLoaded("A"), "A stays loaded until its switch away finishes")
        XCTAssertTrue(host.finishSwitchAway(from: "A"))
        XCTAssertEqual(a.deactivateCount, 1)
        XCTAssertFalse(host.registry.isLoaded("A"), "A was unloaded by its policy")
        XCTAssertTrue(host.registry.isLoaded("B"))
    }

    // MARK: - Background presentation

    /// `presentBackgroundModule(_:)` shows a loaded background module's configuration and
    /// services; `nil` goes back to the active module's.
    func testPresentBackgroundModuleSwapsTheDisplayedModule() {
        let a = StubModule(id: "A")
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")
        _ = host.registry.module(for: "B")

        XCTAssertTrue(host.presentBackgroundModule("B"))
        XCTAssertEqual(host.displayedModuleID, "B")
        XCTAssertEqual(host.activeModuleID, "A", "presenting does not switch")
        XCTAssertTrue(host.displayedServices === host.registry.context(for: "B")?.services)

        XCTAssertTrue(host.presentBackgroundModule(nil))
        XCTAssertEqual(host.displayedModuleID, "A")
        XCTAssertTrue(host.displayedServices === host.activeServices)
    }

    /// The active module and a module that is not loaded are never presented as background
    /// modules - the latter would mean building a module nobody activated.
    func testPresentBackgroundModuleIgnoresActiveAndUnloadedModules() {
        let a = StubModule(id: "A")
        let b = StubModule(id: "B")
        let host = makeHost([a, b], defaultID: "A")

        XCTAssertFalse(host.presentBackgroundModule("A"))
        XCTAssertFalse(host.presentBackgroundModule("B"))
        XCTAssertFalse(host.registry.isLoaded("B"), "presenting must not construct the module")
        XCTAssertNil(host.presentedBackgroundModuleID)
    }

    /// `isMultiModule` reflects how many modules are registered.
    func testIsMultiModuleReflectsRegistrationCount() {
        let single = makeHost([StubModule(id: "A")])
        XCTAssertFalse(single.isMultiModule)

        let multi = makeHost([StubModule(id: "A"), StubModule(id: "B")])
        XCTAssertTrue(multi.isMultiModule)
    }

    // MARK: - Branding

    /// An unconfigured host (the single-module convenience init) gets
    /// ``NookHostBranding/default`` so the demo strings render unchanged.
    func testSingleConfigurationInitGetsDefaultBranding() {
        let host = ModuleHost(configuration: NookConfiguration())
        XCTAssertEqual(host.branding, .default)
        XCTAssertEqual(host.branding.hostName, "Nook")
        XCTAssertNil(host.branding.hostTagline)
    }

    /// Custom branding set on `NookHostConfiguration` flows through the registry to
    /// `ModuleHost.branding`, where the chrome (About card, hotkey label,
    /// menu-bar fallback) reads it.
    func testCustomBrandingPropagatesFromHostConfigurationToModuleHost() {
        var config = NookHostConfiguration()
        config.register(NookModuleDescriptor(id: "A", displayName: "A")) { _ in
            StubModule(id: "A")
        }
        config.branding = NookHostBranding(
            hostName: "ContextNook",
            hostTagline: "Custom tagline."
        )

        let host = ModuleHost(registry: config.makeRegistry())
        XCTAssertEqual(host.branding.hostName, "ContextNook")
        XCTAssertEqual(host.branding.hostTagline, "Custom tagline.")
    }
}
