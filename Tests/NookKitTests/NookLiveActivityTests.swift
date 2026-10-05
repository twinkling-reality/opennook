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

/// Live activities: the center's order and lifetimes, a module's view of it, and how the
/// coordinator puts them on the surface - the pill, the capsules, the peek, alerts, and the
/// expanded view the nook opens onto.
@MainActor
final class NookLiveActivityTests: XCTestCase {
    private func activity(
        _ id: String,
        priority: NookLiveActivity.Priority = .normal,
        lifetime: NookLiveActivity.Lifetime = .ongoing,
        alert: NookLiveActivity.Alert = .none,
        peek: Bool = false,
        expanded: Bool = false
    ) -> NookLiveActivity {
        var activity = NookLiveActivity(
            id: id,
            priority: priority,
            lifetime: lifetime,
            alert: alert,
            accessibilityLabel: id.capitalized
        ) {
            Text("L")
        } compactTrailing: {
            Text("T")
        } minimal: {
            Text("M")
        }
        if peek { activity.setPeek { Text("peek") } }
        if expanded { activity.setExpanded { Text("expanded") } }
        return activity
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - The center

    func testOrderIsPriorityThenAlertThenMostRecent() {
        let center = NookActivityCenter()
        let music = center.activities(for: "music")
        music.start(activity("song"))
        music.start(activity("weather", priority: .low))
        music.start(activity("call"))
        XCTAssertEqual(center.activities.map(\.activity.id), ["call", "song", "weather"])

        music.start(activity("timer", priority: .high))
        XCTAssertEqual(center.primary?.activity.id, "timer")

        music.alert("song", .peek(.seconds(5)))
        XCTAssertEqual(center.activities.map(\.activity.id), ["timer", "song", "call", "weather"])
        XCTAssertTrue(center.entry(moduleID: "music", id: "song")?.isAlerting == true)
    }

    func testRestartingKeepsThePlaceAndUpdatesInPlace() {
        let center = NookActivityCenter()
        let music = center.activities(for: "music")
        music.start(activity("song"))
        music.start(activity("call"))
        music.start(activity("song"))
        XCTAssertEqual(center.activities.map(\.activity.id), ["call", "song"], "a restart does not jump the queue")
        XCTAssertEqual(center.activities.count, 2)
    }

    func testAModuleSeesAndEndsOnlyItsOwnActivities() {
        let center = NookActivityCenter()
        let music = center.activities(for: "music")
        let focus = center.activities(for: "focus")
        music.start(activity("song"))
        focus.start(activity("session"))
        XCTAssertEqual(music.running.map(\.id), ["song"])

        music.end("session")
        XCTAssertEqual(center.activities.count, 2, "music cannot end focus's activity")
        music.endAll()
        XCTAssertEqual(center.activities.map(\.moduleID), ["focus"])
        XCTAssertTrue(center.activities(for: "focus") === focus, "one view per module")
    }

    func testTransientAndScheduledEnds() async {
        let center = NookActivityCenter()
        let module = center.activities(for: "m")
        module.start(activity("flash", lifetime: .transient(.milliseconds(80))))
        module.start(activity("later"))
        module.end("later", after: .milliseconds(120))
        XCTAssertEqual(center.activities.count, 2)
        await waitUntil { center.activities.isEmpty }
        XCTAssertTrue(center.activities.isEmpty)
    }

    func testAnAlertEndsOnItsOwn() async {
        let center = NookActivityCenter()
        let module = center.activities(for: "m")
        module.start(activity("song", alert: .peek(.milliseconds(80))))
        XCTAssertTrue(center.primary?.isAlerting == true)
        await waitUntil { center.primary?.isAlerting == false }
        XCTAssertEqual(center.primary?.isAlerting, false)
    }

    func testTheKeysDefaultStartsNothing() {
        NookLiveActivitiesKey.defaultValue.start(activity("x"))
        XCTAssertTrue(NookLiveActivitiesKey.defaultValue.running.isEmpty)
    }

    func testAPolicyNeverHasNegativeCapsules() {
        XCTAssertEqual(NookActivityPolicy(capsules: -2).capsules, 0)
        XCTAssertEqual(NookActivityPolicy.standard.capsules, 1)
        XCTAssertEqual(NookActivityPolicy.standard.side, .trailing)
    }

    // MARK: - The coordinator

    private func makeCoordinator(
        modulePeek: Bool = false,
        policy: NookActivityPolicy = .standard
    ) -> (AppCoordinator, FakeNookSurface, NookLiveActivities) {
        var host = NookHostConfiguration()
        host.register(TestModule.descriptor(id: "a")) { _ in TestModule(id: "a", peek: modulePeek) }
        host.register(TestModule.descriptor(id: "b", loadsAtLaunch: true)) { _ in TestModule(id: "b") }
        host.activityPolicy = policy
        let moduleHost = ModuleHost(registry: host.makeRegistry())
        let surface = FakeNookSurface()
        let coordinator = AppCoordinator(moduleHost: moduleHost, surface: surface)
        let activities = moduleHost.registry.liveActivities.activities(for: "a")
        return (coordinator, surface, activities)
    }

    func testEveryModuleResolvesItsOwnActivities() {
        let (coordinator, _, _) = makeCoordinator()
        let registry = coordinator.moduleHost.registry
        let a = registry.context(for: "a")?.services.resolve(NookLiveActivitiesKey.self)
        XCTAssertEqual(a?.moduleID, "a")
        XCTAssertTrue(a === registry.liveActivities.activities(for: "a"))
    }

    func testTheNextActivitiesShowInCapsulesAndTheLastCountsTheRest() {
        let (coordinator, surface, activities) = makeCoordinator()
        activities.start(activity("one"))
        XCTAssertTrue(surface.companions.isEmpty, "one activity holds the pill and needs no capsule")

        activities.start(activity("two"))
        activities.start(activity("three"))
        XCTAssertEqual(surface.companions.map(\.id), ["opennook.activity.a.two"])
        let capsules = coordinator.activityCapsuleCompanions(coordinator.liveActivities.activities)
        XCTAssertEqual(capsules.count, 1)
        XCTAssertEqual(capsules.first?.visibility, .compact)

        activities.endAll()
        XCTAssertTrue(surface.companions.isEmpty)
    }

    func testAPolicyCanShowMoreCapsulesOnTheLeadingSide() {
        let (coordinator, surface, activities) = makeCoordinator(
            policy: NookActivityPolicy(capsules: 3, side: .leading)
        )
        for id in ["one", "two", "three", "four"] { activities.start(activity(id)) }
        XCTAssertEqual(surface.companions.count, 3)
        XCTAssertEqual(surface.companions.first?.anchor, .leading)
        withExtendedLifetime(coordinator) {}
    }

    func testAnActivitysPeekComesBeforeTheModules() {
        let (coordinator, surface, activities) = makeCoordinator(modulePeek: true)
        XCTAssertNotNil(surface.peekContent, "the module's own peek")
        XCTAssertNil(coordinator.peekOwnerActivity)

        activities.start(activity("song", peek: true))
        XCTAssertNotNil(surface.peekContent)
        XCTAssertEqual(coordinator.peekOwnerActivity, "a\u{1F}song")

        activities.end("song")
        XCTAssertNil(coordinator.peekOwnerActivity, "back to the module's peek")
        XCTAssertNotNil(surface.peekContent)
    }

    func testAPeekAlertPeeksAndEndsOnSchedule() async {
        let (coordinator, surface, activities) = makeCoordinator()
        await surface.compact(on: nil)
        activities.start(activity("song", alert: .peek(.milliseconds(900)), peek: true))
        await waitUntil(timeout: .seconds(4)) { surface.isPeeking }
        XCTAssertTrue(surface.isPeeking)
        XCTAssertEqual(surface.state, .compact)
        await waitUntil(timeout: .seconds(4)) { !surface.isPeeking }
        XCTAssertFalse(surface.isPeeking)
        withExtendedLifetime(coordinator) {}
    }

    func testAnExpandAlertOpensOntoTheActivityAndCollapsingTakesItDown() async {
        let (coordinator, surface, activities) = makeCoordinator()
        await surface.compact(on: nil)
        activities.start(activity("timer", alert: .expand(.milliseconds(900)), expanded: true))
        await waitUntil(timeout: .seconds(4)) { surface.state == .expanded }
        XCTAssertEqual(coordinator.appState.presentedLiveActivity, "a\u{1F}timer")
        XCTAssertEqual(coordinator.appState.moduleBreadcrumb, "Timer")
        await waitUntil(timeout: .seconds(4)) { surface.state == .compact }
        XCTAssertNil(coordinator.appState.presentedLiveActivity)
        XCTAssertNil(coordinator.appState.moduleBreadcrumb)
    }

    func testABackgroundModulesOrdinaryAlertOnlyUpdatesThePill() async throws {
        let (coordinator, surface, _) = makeCoordinator()
        await surface.compact(on: nil)
        let background = coordinator.liveActivities.activities(for: "b")
        background.start(activity("download", alert: .peek(.seconds(1)), peek: true))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(surface.isPeeking)
        XCTAssertEqual(coordinator.liveActivities.primary?.moduleID, "b", "it still holds the pill")

        background.start(activity("alarm", priority: .high, alert: .peek(.milliseconds(900)), peek: true))
        await waitUntil(timeout: .seconds(4)) { surface.isPeeking }
        XCTAssertTrue(surface.isPeeking, "a high priority alert from the background takes the surface")
    }

    func testOpeningFromAnActivitysPeekShowsItsExpandedViewAndBackGoesHome() async {
        let (coordinator, surface, activities) = makeCoordinator()
        await surface.compact(on: nil)
        activities.start(activity("song", peek: true, expanded: true))
        await surface.peek(on: nil)
        XCTAssertTrue(surface.isPeeking)

        await surface.expand(on: nil)
        XCTAssertEqual(coordinator.appState.presentedLiveActivity, "a\u{1F}song")
        XCTAssertEqual(coordinator.appState.moduleBreadcrumb, "Song")

        NookTopBarCommands.goBack(coordinator.appState, animation: .default)
        XCTAssertNil(coordinator.appState.presentedLiveActivity)
        XCTAssertNil(coordinator.appState.moduleBreadcrumb)
    }

    func testOpeningTheNookYourselfShowsHome() async {
        let (coordinator, surface, activities) = makeCoordinator()
        await surface.compact(on: nil)
        activities.start(activity("song", peek: true, expanded: true))
        await surface.peek(on: nil)
        await surface.expand(on: nil)
        XCTAssertNotNil(coordinator.appState.presentedLiveActivity)

        coordinator.showNook()
        await coordinator.drainLifecycleForTesting()
        XCTAssertNil(coordinator.appState.presentedLiveActivity)
    }

    func testAnActivityThatEndsTakesItsViewDown() async {
        let (coordinator, surface, activities) = makeCoordinator()
        await surface.compact(on: nil)
        activities.start(activity("song", peek: true, expanded: true))
        await surface.peek(on: nil)
        await surface.expand(on: nil)
        activities.end("song")
        XCTAssertNil(coordinator.appState.presentedLiveActivity)
    }

    func testUnloadingAModuleEndsItsActivities() {
        let (coordinator, _, _) = makeCoordinator()
        let registry = coordinator.moduleHost.registry
        registry.liveActivities.activities(for: "b").start(activity("download"))
        registry.liveActivities.activities(for: "a").start(activity("song"))
        registry.unload("b")
        XCTAssertEqual(registry.liveActivities.activities.map(\.moduleID), ["a"])
    }

    func testAModuleThatLoadsAtLaunchIsBuiltAndReady() {
        let (coordinator, _, _) = makeCoordinator()
        TestModule.readyIDs = []
        XCTAssertFalse(coordinator.moduleHost.registry.isLoaded("b"))
        coordinator.loadModulesAtLaunch()
        XCTAssertTrue(coordinator.moduleHost.registry.isLoaded("b"))
        XCTAssertEqual(TestModule.readyIDs, ["b"])
        coordinator.loadModulesAtLaunch()
        XCTAssertEqual(TestModule.readyIDs, ["b"], "onReady runs once per loaded instance")
    }
}

/// A module with nothing but an id, an optional peek, and an `onReady` that records itself.
@MainActor
private final class TestModule: NookModule {
    static var readyIDs: [String] = []

    nonisolated static func descriptor(id: String, loadsAtLaunch: Bool = false) -> NookModuleDescriptor {
        var descriptor = NookModuleDescriptor(id: id, displayName: id, backgroundPolicy: .stayResident)
        descriptor.loadsAtLaunch = loadsAtLaunch
        return descriptor
    }

    let descriptor: NookModuleDescriptor
    private let peek: Bool

    init(id: String, peek: Bool = false) {
        self.descriptor = TestModule.descriptor(id: id)
        self.peek = peek
    }

    func makeConfiguration() -> NookConfiguration {
        var configuration = NookConfiguration()
        if peek { configuration.setPeek { Text("module peek") } }
        let id = descriptor.id
        configuration.onReady = { _ in TestModule.readyIDs.append(id) }
        return configuration
    }
}
