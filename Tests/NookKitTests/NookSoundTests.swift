// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import Combine
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// The chrome theme's sounds: which chrome event plays which sound, the person's "Sounds"
/// switch, and the player. Nothing here makes a noise: the coordinator plays through a
/// recording player, and the system player is silenced whenever a test asks it to play.
@MainActor
final class NookSoundTests: XCTestCase {
    /// Records what would have played.
    private final class RecordingSoundPlayer: NookSoundPlaying {
        private(set) var played: [NookSoundSpec] = []
        private(set) var preloaded: [[NookSoundSpec]] = []

        func preload(_ sounds: [NookSoundSpec]) { preloaded.append(sounds) }
        func play(_ sound: NookSoundSpec) { played.append(sound) }

        /// The event each played sound stands for: the tests name each system sound after its id.
        var events: [String] {
            played.compactMap { sound in
                if case .system(let name) = sound.source { return name }
                return nil
            }
        }
    }

    /// A theme with a sound for every event, each a "system sound" named after its id.
    private func soundTheme(volume: Double = 1) -> NookTheme {
        var theme = NookTheme(soundVolume: volume)
        for id in NookSoundID.allEvents {
            theme.tokens[id] = .system(id.rawValue, volume: 0.5)
        }
        return theme
    }

    private struct Harness {
        let coordinator: AppCoordinator
        let surface: FakeNookSurface
        let player: RecordingSoundPlayer
        let appState: AppState
        /// How many times the coordinator made a sound player.
        let madePlayers: () -> Int
    }

    private func makeHarness(theme: NookTheme?, soundsEnabled: Bool = true) -> Harness {
        let appState = AppState()
        // Assigned directly, so nothing is written to the preference store.
        appState.appearancePreferences = NookAppearancePreferences(soundsEnabled: soundsEnabled)
        var configuration = NookConfiguration()
        configuration.chromeTheme = theme
        let surface = FakeNookSurface()
        let coordinator = AppCoordinator(
            appState: appState,
            moduleHost: ModuleHost(configuration: configuration),
            surface: surface,
            systemAppearanceChanges: Empty().eraseToAnyPublisher()
        )
        coordinator.reduceTransparencyProvider = { false }
        let player = RecordingSoundPlayer()
        var made = 0
        coordinator.makeSoundPlayer = {
            made += 1
            return player
        }
        return Harness(
            coordinator: coordinator,
            surface: surface,
            player: player,
            appState: appState,
            madePlayers: { made }
        )
    }

    // MARK: - Events

    func testOpenAndClosePlayOnTheExpandedStatesEdges() async {
        let harness = makeHarness(theme: soundTheme())
        await harness.surface.compact(on: nil)
        XCTAssertEqual(harness.player.events, [], "hidden to compact is neither")
        await harness.surface.expand(on: nil)
        XCTAssertEqual(harness.player.events, ["sound.open"])
        await harness.surface.compact(on: nil)
        XCTAssertEqual(harness.player.events, ["sound.open", "sound.close"])
        await harness.surface.expand(on: nil)
        await harness.surface.hide()
        XCTAssertEqual(harness.player.events, ["sound.open", "sound.close", "sound.open", "sound.close"])
    }

    func testHoverPlaysWhenThePointerArrives() {
        let harness = makeHarness(theme: soundTheme())
        harness.surface.isHovering = true
        harness.surface.isHovering = false
        harness.surface.isHovering = true
        XCTAssertEqual(harness.player.events, ["sound.hover", "sound.hover"])
    }

    func testStatusesPlayAlertAndFinish() {
        let harness = makeHarness(theme: soundTheme())
        harness.appState.showStatus("Failed", severity: .error)
        harness.appState.showStatus("Careful", severity: .warning)
        harness.appState.showStatus("Saved", severity: .success)
        harness.appState.showStatus("FYI", severity: .info)
        harness.appState.errorMessage = "Legacy error"
        harness.appState.status = nil
        XCTAssertEqual(
            harness.player.events,
            ["sound.alert", "sound.alert", "sound.finish", "sound.alert"]
        )
    }

    func testFeedbackPlaysWithTheCue() {
        let harness = makeHarness(theme: soundTheme())
        harness.coordinator.playFeedback(.pulse)
        XCTAssertEqual(harness.surface.feedbackCount, 1)
        XCTAssertEqual(harness.player.events, ["sound.feedback"])
    }

    func testTheLaunchShimmerPlaysTheFeedbackSound() async {
        let harness = makeHarness(theme: soundTheme())
        harness.coordinator.start()
        await harness.coordinator.drainLifecycleForTesting()
        XCTAssertEqual(harness.player.events, ["sound.feedback"])
    }

    func testAGrantedUrgentClaimPlaysTheAlert() async {
        let harness = makeHarness(theme: soundTheme())
        let coordinator = harness.coordinator
        let normal = await coordinator.beginTransientPresentation(
            NookSurfaceClaim(moduleID: coordinator.activeModuleID, priority: .normal)
        )
        XCTAssertNotNil(normal)
        XCTAssertFalse(harness.player.events.contains("sound.alert"))
        if let normal { await coordinator.endTransientPresentation(normal) }

        let urgent = await coordinator.beginTransientPresentation(
            NookSurfaceClaim(moduleID: coordinator.activeModuleID, priority: .urgent)
        )
        XCTAssertNotNil(urgent)
        XCTAssertEqual(harness.player.events.filter { $0 == "sound.alert" }.count, 1)
        if let urgent { await coordinator.endTransientPresentation(urgent) }
    }

    func testHostsPlayAnySoundOnDemand() {
        let harness = makeHarness(theme: soundTheme())
        harness.coordinator.playSound(.peek)
        harness.coordinator.chromeActions.playSound(.finish)
        XCTAssertEqual(harness.player.events, ["sound.peek", "sound.finish"])
    }

    /// The played volume is the sound's own times the theme's `soundVolume`.
    func testSoundsPlayAtTheThemesVolume() {
        let harness = makeHarness(theme: soundTheme(volume: 0.5))
        harness.coordinator.playSound(.open)
        XCTAssertEqual(harness.player.played.first?.volume ?? 0, 0.25, accuracy: 1e-9)
    }

    // MARK: - Silence

    func testNothingPlaysWhileThePersonTurnedSoundsOff() async {
        let harness = makeHarness(theme: soundTheme(), soundsEnabled: false)
        await harness.surface.expand(on: nil)
        harness.surface.isHovering = true
        harness.appState.showStatus("Failed")
        harness.coordinator.playFeedback()
        harness.coordinator.playSound(.finish)
        XCTAssertEqual(harness.player.played, [])

        harness.appState.appearancePreferences.soundsEnabled = true
        harness.coordinator.playSound(.finish)
        XCTAssertEqual(harness.player.events, ["sound.finish"])
    }

    /// The default theme has no sounds: every event passes without a player ever being made,
    /// and the surface look loads nothing.
    func testAThemeWithoutSoundsNeverMakesAPlayer() async {
        for theme in [nil, NookTheme.standard, NookTheme(accent: "#FF0000")] {
            let harness = makeHarness(theme: theme)
            harness.coordinator.applySurfaceLook()
            await harness.surface.expand(on: nil)
            harness.surface.isHovering = true
            await harness.surface.compact(on: nil)
            harness.appState.showStatus("Failed")
            harness.appState.showStatus("Saved", severity: .success)
            harness.coordinator.playFeedback()
            for id in NookSoundID.allEvents { harness.coordinator.playSound(id) }
            XCTAssertEqual(harness.madePlayers(), 0)
        }
    }

    func testTheSurfaceLookPreloadsTheThemesSounds() {
        let harness = makeHarness(theme: soundTheme())
        harness.coordinator.applySurfaceLook()
        XCTAssertEqual(harness.player.preloaded.count, 1)
        XCTAssertEqual(
            harness.player.preloaded.first?.compactMap { sound -> String? in
                if case .system(let name) = sound.source { return name }
                return nil
            },
            NookSoundID.allEvents.map(\.rawValue)
        )
        XCTAssertEqual(harness.madePlayers(), 1)
    }

    /// Every sound goes to the player the coordinator's factory made, made once and kept.
    func testTheCoordinatorPlaysThroughTheInjectedPlayer() {
        let harness = makeHarness(theme: soundTheme())
        harness.coordinator.playSound(.open)
        harness.coordinator.playSound(.close)
        XCTAssertEqual(harness.player.events, ["sound.open", "sound.close"])
        XCTAssertEqual(harness.madePlayers(), 1)
        XCTAssertTrue(harness.coordinator.madeSoundPlayer === harness.player)
    }

    // MARK: - Status severities

    func testEachSeveritysSound() {
        XCTAssertEqual(NookStatusSeverity.error.sound, .alert)
        XCTAssertEqual(NookStatusSeverity.warning.sound, .alert)
        XCTAssertEqual(NookStatusSeverity.success.sound, .finish)
        XCTAssertNil(NookStatusSeverity.info.sound)
    }

    // MARK: - Settings

    func testTheSoundsRowFollowsTheThemeAndThePersonsChoice() {
        let sounds = soundTheme()
        let tokens = sounds.resolvedTokens()
        func shows(_ theme: NookTheme, _ tokens: NookResolvedTokens, enabled: Bool) -> Bool {
            NookShortcutSettingsSection.showsSoundsRow(theme: theme, tokens: tokens, soundsEnabled: enabled)
        }
        XCTAssertFalse(shows(.standard, .standard, enabled: true), "no sounds, no row")
        XCTAssertFalse(shows(.standard, .standard, enabled: false))
        XCTAssertTrue(shows(sounds, tokens, enabled: true))
        XCTAssertTrue(shows(sounds, tokens, enabled: false))

        var locked = sounds
        locked.allowsUserSoundToggle = false
        XCTAssertFalse(shows(locked, locked.resolvedTokens(), enabled: true), "the theme keeps its sounds on")
        XCTAssertTrue(
            shows(locked, locked.resolvedTokens(), enabled: false),
            "but a person who turned them off can always turn them back on"
        )
    }

    func testSoundsLabelsDefaults() {
        let shortcut = NookChromeLabels.default.shortcut
        XCTAssertEqual(shortcut.soundsTitle, "Sounds")
        XCTAssertEqual(shortcut.soundsOn, "On - the nook plays its sounds")
        XCTAssertEqual(shortcut.soundsOff, "Off - the nook stays quiet")
    }

    // MARK: - Preference

    func testSoundsAreOnByDefaultAndDecodeForwardCompatibly() throws {
        XCTAssertTrue(NookAppearancePreferences.default.soundsEnabled)
        let older = try JSONDecoder().decode(
            NookAppearancePreferences.self,
            from: Data(#"{"chromePalette":"dark"}"#.utf8)
        )
        XCTAssertTrue(older.soundsEnabled)

        let off = NookAppearancePreferences(soundsEnabled: false)
        let decoded = try JSONDecoder().decode(NookAppearancePreferences.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(decoded.soundsEnabled)
    }

    func testTurningSoundsOffIsKeptAsAChoice() throws {
        var preferences = NookAppearancePreferences.default
        preferences.soundsEnabled = false
        let choices = NookAppearanceChoices(differencesFrom: .default, to: preferences)
        XCTAssertEqual(choices.soundsEnabled, false)
        XCTAssertNil(choices.chromePalette, "only the changed field is a choice")
        XCTAssertFalse(choices.applied(to: .default).soundsEnabled)

        let decoded = try JSONDecoder().decode(NookAppearanceChoices.self, from: JSONEncoder().encode(choices))
        XCTAssertEqual(decoded, choices)
        // A record from a build before the switch existed leaves it to the defaults.
        let older = try JSONDecoder().decode(NookAppearanceChoices.self, from: Data(#"{"keepNookOpen":true}"#.utf8))
        XCTAssertNil(older.soundsEnabled)
    }

    func testTheSoundsRowPersistsThroughAppState() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let appState = AppState()
            var preferences = appState.appearancePreferences
            preferences.soundsEnabled = false
            appState.replaceAppearancePreferences(preferences)
            XCTAssertFalse(AppState().appearancePreferences.soundsEnabled)
            appState.resetAppearancePreferences()
            XCTAssertTrue(AppState().appearancePreferences.soundsEnabled)
        }
    }

    // MARK: - The system player

    func testTheSystemPlayerLoadsEachSourceOnce() throws {
        let player = NookSystemSoundPlayer(isSilenced: true)
        let tink = try XCTUnwrap(player.loaded(.system("Tink")), "a system sound by name")
        XCTAssertTrue(player.loaded(.system("Tink")) === tink, "loaded once and kept")
        XCTAssertFalse(tink === NSSound(named: "Tink"), "a copy, so its volume is the player's own")

        let file = URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
        XCTAssertNotNil(player.loaded(.file(file)), "a sound file")

        XCTAssertNil(player.loaded(.system("No Such Sound")))
        XCTAssertNil(player.loaded(.resource("missing.caf")))
        XCTAssertNil(player.loaded(.file(URL(fileURLWithPath: "/nonexistent/sound.caf"))))
    }

    /// The shipping player plays: nothing about the process it runs in silences it.
    func testTheSystemPlayerIsNotSilencedByDefault() {
        XCTAssertFalse(NookSystemSoundPlayer().isSilenced)
    }

    func testASilencedSystemPlayerPlaysNothing() {
        let player = NookSystemSoundPlayer(isSilenced: true)
        player.preload([.system("Tink")])
        player.play(.system("Tink", volume: 0.2))
        XCTAssertEqual(player.loaded(.system("Tink"))?.isPlaying, false)
    }
}
