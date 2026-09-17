// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import XCTest

@testable import NookKit

/// Launch-seed preference defaults: a host can ship its own out-of-box appearance /
/// hotkey / display without the user opening Settings, while any value the user has
/// already persisted always wins and the seed is never written.
///
/// `@MainActor`: `AppState` / `AppCoordinator` are main-actor isolated.
@MainActor
final class NookPreferenceDefaultsTests: XCTestCase {
    private var customDefaults: NookPreferenceDefaults {
        NookPreferenceDefaults(
            appearance: NookAppearancePreferences(
                chromePalette: .dark,
                surfaceStyle: .translucent,
                presentation: .floating,
                hapticFeedbackEnabled: true,
                keepNookOpen: true
            ),
            hotkey: NookHotkey(keyCode: 12, carbonModifiers: 256, keySymbol: "Q"),
            display: .main
        )
    }

    /// The default bag reproduces the framework exactly, and both configuration structs
    /// default to it - so an unconfigured host behaves as before.
    func testDefaultsReproduceFramework() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            XCTAssertEqual(NookPreferenceDefaults.default, NookPreferenceDefaults())
            XCTAssertEqual(NookPreferenceDefaults.default.appearance, .default)
            XCTAssertEqual(NookPreferenceDefaults.default.hotkey, .default)
            XCTAssertEqual(NookPreferenceDefaults.default.display, .default)

            XCTAssertEqual(NookConfiguration().preferenceDefaults, .default)
            XCTAssertEqual(NookHostConfiguration().preferenceDefaults, .default)
        }
    }

    /// With nothing persisted, `AppState` seeds from the host defaults.
    func testAppStateSeedsFromDefaultsWhenNothingPersisted() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let appState = AppState(preferenceDefaults: customDefaults)

            XCTAssertEqual(appState.appearancePreferences, customDefaults.appearance)
            XCTAssertEqual(appState.hotkey, customDefaults.hotkey)
            XCTAssertEqual(appState.displayPreference, customDefaults.display)
        }
    }

    /// `AppState()` (and a `.default` seed) still falls back to framework defaults.
    func testAppStateWithoutSeedUsesFrameworkDefaults() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let appState = AppState()

            XCTAssertEqual(appState.appearancePreferences, .default)
            XCTAssertEqual(appState.hotkey, .default)
            XCTAssertEqual(appState.displayPreference, .default)
        }
    }

    /// A value the user has already persisted beats the host seed.
    func testPersistedValueBeatsSeed() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            var choices = NookAppearanceChoices()
            choices.chromePalette = .light
            NookAppearanceStore.saveChoices(choices)

            let appState = AppState(preferenceDefaults: customDefaults)

            XCTAssertEqual(appState.appearancePreferences.chromePalette, .light)
            XCTAssertNotEqual(appState.appearancePreferences, customDefaults.appearance)
        }
    }

    // MARK: - Per-field appearance

    /// REGRESSION: changing one appearance field saved the whole record, freezing every other
    /// field at the default of the build it was saved under. Now only the changed field is kept,
    /// so a default the host changes later still reaches the fields the user never chose.
    func testChangingOneFieldLeavesTheOthersFollowingTheDefaults() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let first = AppState(preferenceDefaults: NookPreferenceDefaults(appearance: .init(surfaceStyle: .solid)))
            var preferences = first.appearancePreferences
            preferences.keepNookOpen = true
            first.replaceAppearancePreferences(preferences)

            let later = AppState(
                preferenceDefaults: NookPreferenceDefaults(
                    appearance: .init(chromePalette: .dark, surfaceStyle: .liquidGlass)
                )
            )

            XCTAssertTrue(later.appearancePreferences.keepNookOpen, "the user's choice is kept")
            XCTAssertEqual(
                later.appearancePreferences.surfaceStyle,
                .liquidGlass,
                "an unchosen field follows the new default"
            )
            XCTAssertEqual(later.appearancePreferences.chromePalette, .dark)
        }
    }

    /// A field the user sets is their choice even when it matches the default at the time, so a
    /// later default change does not move it.
    func testAChoiceMatchingTheDefaultIsStillKept() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let first = AppState(preferenceDefaults: NookPreferenceDefaults(appearance: .init(surfaceStyle: .solid)))
            var preferences = first.appearancePreferences
            preferences.surfaceStyle = .translucent
            first.replaceAppearancePreferences(preferences)
            preferences.surfaceStyle = .solid
            first.replaceAppearancePreferences(preferences)

            let later = AppState(
                preferenceDefaults: NookPreferenceDefaults(appearance: .init(surfaceStyle: .liquidGlass))
            )

            XCTAssertEqual(later.appearancePreferences.surfaceStyle, .solid)
        }
    }

    /// A whole record from an earlier build is migrated: fields matching the current defaults are
    /// taken as never chosen, the rest are kept, and the migration is stored so it runs once.
    func testEarlierBuildsRecordMigratesOnlyItsDifferences() throws {
        try PreferenceStoreTestIsolation.withIsolatedStore {
            let legacy = NookAppearancePreferences(chromePalette: .light, surfaceStyle: .solid, keepNookOpen: true)
            NookPreferenceStorage.defaults.set(try JSONEncoder().encode(legacy), forKey: NookAppearanceStore.legacyKey)

            let seed = NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .solid)
            let migrated = AppState(preferenceDefaults: NookPreferenceDefaults(appearance: seed))
            XCTAssertEqual(migrated.appearancePreferences, legacy, "nobody's appearance changes on upgrade")
            XCTAssertNotNil(NookPreferenceStorage.defaults.data(forKey: NookAppearanceStore.choicesKey))

            let changedSeed = NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .liquidGlass)
            let later = AppState(preferenceDefaults: NookPreferenceDefaults(appearance: changedSeed))
            XCTAssertEqual(later.appearancePreferences.chromePalette, .light, "a field that differed is a choice")
            XCTAssertTrue(later.appearancePreferences.keepNookOpen)
            XCTAssertEqual(
                later.appearancePreferences.surfaceStyle,
                .liquidGlass,
                "a field that matched the defaults at migration follows them afterwards"
            )
        }
    }

    /// A stored choice this build cannot read drops that choice alone.
    func testUnreadableChoiceDropsOnlyThatField() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let json = #"{"chromePalette":"light","surfaceStyle":"holographic"}"#
            NookPreferenceStorage.defaults.set(Data(json.utf8), forKey: NookAppearanceStore.choicesKey)

            let appState = AppState(
                preferenceDefaults: NookPreferenceDefaults(appearance: .init(surfaceStyle: .translucent))
            )

            XCTAssertEqual(appState.appearancePreferences.chromePalette, .light)
            XCTAssertEqual(appState.appearancePreferences.surfaceStyle, .translucent)
        }
    }

    /// Resetting forgets every choice and returns to the host's defaults - not the framework's -
    /// for appearance, the shortcut, and the display, and an earlier build's record is not
    /// migrated back in.
    func testResetReturnsToTheHostsDefaultsAndForgetsChoices() throws {
        try PreferenceStoreTestIsolation.withIsolatedStore {
            let legacy = NookAppearancePreferences(chromePalette: .light)
            NookPreferenceStorage.defaults.set(try JSONEncoder().encode(legacy), forKey: NookAppearanceStore.legacyKey)

            let appState = AppState(preferenceDefaults: customDefaults)
            appState.replaceHotkey(.default)
            appState.replaceDisplayPreference(.builtIn)
            let coordinator = AppCoordinator(
                appState: appState,
                moduleHost: ModuleHost(configuration: NookConfiguration()),
                surface: FakeNookSurface()
            )

            coordinator.resetAllSettingsToDefaults()

            XCTAssertEqual(appState.appearancePreferences, customDefaults.appearance)
            XCTAssertEqual(appState.hotkey, customDefaults.hotkey)
            XCTAssertEqual(appState.displayPreference, customDefaults.display)
            XCTAssertNil(NookPreferenceStorage.defaults.data(forKey: "opennook.hotkey.v1"))
            XCTAssertNil(NookPreferenceStorage.defaults.data(forKey: "opennook.display.v1"))

            let relaunched = AppState(preferenceDefaults: customDefaults)
            XCTAssertEqual(relaunched.appearancePreferences, customDefaults.appearance)
            XCTAssertEqual(relaunched.hotkey, customDefaults.hotkey)
        }
    }

    /// Seeding must not write the host defaults to `UserDefaults` - otherwise a later
    /// build couldn't revise them for users who never touched Settings.
    func testSeedIsNotPersisted() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            _ = AppState(preferenceDefaults: customDefaults)

            for key in PreferenceStoreTestIsolation.storeKeys {
                XCTAssertNil(
                    NookPreferenceStorage.defaults.data(forKey: key),
                    "Seeding wrote \(key) to UserDefaults; it should stay a pure fallback."
                )
            }
        }
    }

    /// The seeded appearance reaches the surface on the first backdrop sync - the path
    /// the chrome's first paint uses - so a host's launch presentation is honored before
    /// any user interaction.
    func testSeededPresentationReachesSurface() {
        PreferenceStoreTestIsolation.withIsolatedStore {
            let seeded = AppState(
                preferenceDefaults: NookPreferenceDefaults(
                    appearance: NookAppearancePreferences(presentation: .floating)
                )
            )
            let surface = FakeNookSurface()
            let coordinator = AppCoordinator(
                appState: seeded,
                moduleHost: ModuleHost(configuration: NookConfiguration()),
                surface: surface
            )

            coordinator.syncNotchBackdrop()

            XCTAssertEqual(surface.presentation, .floating)
        }
    }
}
