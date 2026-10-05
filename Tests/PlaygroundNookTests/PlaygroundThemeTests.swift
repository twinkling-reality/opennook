// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import SwiftUI
import XCTest

@testable import PlaygroundNookCore

/// The playground's theme settings as a framework `NookTheme`, and presets from before the
/// theme moved into NookKit.
final class PlaygroundThemeTests: XCTestCase {
    func testUntouchedSettingsAreTheStandardThemeAndSetNoTheme() {
        XCTAssertEqual(PlaygroundSettings.Theme().nookTheme, .standard)
        let configuration = PlaygroundSettings().makeConfiguration(
            home: { Text("home") },
            companion: { _ in Text("c") }
        )
        XCTAssertNil(configuration.chromeTheme)
    }

    func testTheThemeSettingsBecomeAChromeTheme() {
        var theme = PlaygroundSettings.Theme()
        theme.accent = PlaygroundColor(red: 1, green: 0, blue: 0)
        theme.primaryLabel = PlaygroundColor(red: 0, green: 1, blue: 0)
        theme.destructive = PlaygroundColor(red: 0, green: 0, blue: 1)
        theme.fontDesign = .serif
        theme.radius = 1.5
        theme.scale = 1.2
        theme.motion = .expressive
        let nook = theme.nookTheme
        XCTAssertEqual(nook.accent, .hex(PlaygroundColor(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(nook.tokens[.labelPrimary], .hex(PlaygroundColor(red: 0, green: 1, blue: 0)))
        XCTAssertEqual(nook.tokens[.destructive], .hex(PlaygroundColor(red: 0, green: 0, blue: 1)))
        XCTAssertEqual(nook.fontDesign, .serif)
        XCTAssertEqual(nook.radius, .factor(1.5))
        XCTAssertEqual(nook.scale, 1.2)
        XCTAssertEqual(nook.motion, .expressive)

        var settings = PlaygroundSettings()
        settings.theme = theme
        let configuration = settings.makeConfiguration(home: { Text("home") }, companion: { _ in Text("c") })
        XCTAssertEqual(configuration.chromeTheme, nook)
    }

    func testEveryColorRoleHasAToken() {
        let ids = PlaygroundSettings.Theme.ColorRole.allCases.map(\.tokenID)
        XCTAssertEqual(Set(ids).count, ids.count)
        for role in PlaygroundSettings.Theme.ColorRole.allCases {
            XCTAssertEqual(NookColorID(rawValue: role.tokenID.rawValue), role.tokenID)
        }
    }

    func testAVersionOnePresetFromBeforeThemesStillOpens() throws {
        let json = ##"""
            {
              "appearance" : { "accentPreset" : "violet", "chromePalette" : "dark" },
              "format" : "opennook.playground-preset",
              "settings" : {
                "theme" : { "accent" : "#FF8000", "fontDesign" : "rounded", "primaryLabel" : "#FFFFFFE6" },
                "typography" : { "topBarLabel" : { "size" : 12, "weight" : "medium" } },
                "motion" : { "viewModeChange" : { "dampingFraction" : 0.8, "response" : 0.5 } }
              },
              "version" : 1
            }
            """##
        let preset = try PlaygroundPresetCoder.decode(json)
        XCTAssertEqual(preset.settings.theme.accent, PlaygroundColor(hex: "#FF8000"))
        XCTAssertEqual(preset.settings.theme.fontDesign, .rounded)
        XCTAssertNil(preset.settings.theme.radius)
        XCTAssertEqual(preset.settings.typography.topBarLabel, PlaygroundSettings.FontSpec(size: 12, weight: .medium))
        XCTAssertEqual(preset.settings.motion.viewModeChange.nookSpec, .spring(response: 0.5, dampingFraction: 0.8))
        // And it writes back with the same keys: no new members appear for untouched knobs.
        let text = try PlaygroundPresetCoder.encodeString(preset)
        XCTAssertFalse(text.contains("\"radius\""))
        XCTAssertFalse(text.contains("\"motion\" : \""))
    }

    func testThemeKnobsAreKeptInRange() {
        var settings = PlaygroundSettings()
        settings.theme.radius = 9
        settings.theme.scale = 0.1
        let normalized = settings.normalized()
        XCTAssertEqual(normalized.theme.radius, 4)
        XCTAssertEqual(normalized.theme.scale, 0.5)
    }

    func testTheThemeWritesAFrameworkThemeFile() throws {
        var theme = PlaygroundSettings.Theme()
        theme.accent = PlaygroundColor(red: 1, green: 0.5, blue: 0)
        let text = try NookThemeCoder.encodeString(theme.nookTheme)
        XCTAssertEqual(try NookThemeCoder.decode(text).theme, theme.nookTheme)
    }
}
