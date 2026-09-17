// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import XCTest

@testable import PlaygroundNookCore

final class PlaygroundPresetCoderTests: XCTestCase {
    private typealias Coder = PlaygroundPresetCoder

    private func decodingError(_ json: String, file: StaticString = #filePath, line: UInt = #line)
        -> PlaygroundPresetError?
    {
        do {
            _ = try Coder.decode(json)
            XCTFail("expected the preset to be rejected", file: file, line: line)
            return nil
        } catch {
            return error as? PlaygroundPresetError
        }
    }

    // MARK: - Round trips

    func testEverySampleSurvivesARoundTrip() throws {
        for sample in PlaygroundPreset.samples {
            let data = try Coder.encode(sample.preset)
            XCTAssertEqual(try Coder.decode(data), sample.preset, sample.id)
        }
    }

    func testAFullyCustomizedPresetSurvivesARoundTrip() throws {
        let preset = PlaygroundFixtures.everythingChanged
        XCTAssertEqual(try Coder.decode(try Coder.encodeString(preset)), preset)
    }

    func testEncodingIsStableSortedAndNamesItsFormat() throws {
        let text = try Coder.encodeString(PlaygroundPreset())
        XCTAssertEqual(text, try Coder.encodeString(PlaygroundPreset()))
        XCTAssertTrue(text.contains(#""format" : "opennook.playground-preset""#))
        XCTAssertTrue(text.contains(#""version" : 1"#))
        XCTAssertTrue(text.hasSuffix("}\n"))
        let keys = [#""appearance""#, #""format""#, #""settings""#, #""version""#]
        let offsets = try keys.map { try XCTUnwrap(text.range(of: $0)).lowerBound }
        XCTAssertEqual(offsets, offsets.sorted(), "top-level keys are sorted")
    }

    func testColorsAreWrittenAsHexStrings() throws {
        var preset = PlaygroundPreset()
        preset.settings.theme.accent = PlaygroundColor(red: 1, green: 0.5, blue: 0, opacity: 0.5)
        XCTAssertTrue(try Coder.encodeString(preset).contains(##""accent" : "#FF800080""##))
    }

    // MARK: - Leniency

    func testMissingKeysFallBackToDefaults() throws {
        XCTAssertEqual(try Coder.decode(#"{"format": "opennook.playground-preset", "version": 1}"#), PlaygroundPreset())

        let partial = try Coder.decode(
            #"""
            {
              "format": "opennook.playground-preset",
              "version": 1,
              "appearance": { "surfaceStyle": "liquidGlass" },
              "settings": {
                "panel": { "expandedWidth": 400 },
                "companions": [ { "id": "x" } ]
              }
            }
            """#
        )
        XCTAssertEqual(partial.appearance, NookAppearancePreferences(surfaceStyle: .liquidGlass))
        XCTAssertEqual(partial.settings.panel.expandedWidth, 400)
        XCTAssertEqual(partial.settings.panel.bottomCornerRadius, PlaygroundSettings.Panel().bottomCornerRadius)
        XCTAssertEqual(partial.settings.companions, [PlaygroundSettings.Companion(id: "x", template: .actions)])
        XCTAssertEqual(partial.settings.metrics, PlaygroundSettings.Metrics())
    }

    func testUnknownKeysAreIgnored() throws {
        let preset = try Coder.decode(
            #"{"format": "opennook.playground-preset", "version": 1, "future": [1], "settings": {"panel": {"wobble": 3}}}"#
        )
        XCTAssertEqual(preset, PlaygroundPreset())
    }

    func testKeepOpenIsClearedOnTheWayInAndOut() throws {
        var appearance = NookAppearancePreferences()
        appearance.keepNookOpen = true
        var preset = PlaygroundPreset(appearance: appearance)
        XCTAssertFalse(preset.appearance.keepNookOpen)
        preset.appearance.keepNookOpen = true
        XCTAssertFalse(preset.appearance.keepNookOpen)

        let decoded = try Coder.decode(
            #"{"format": "opennook.playground-preset", "version": 1, "appearance": {"keepNookOpen": true}}"#
        )
        XCTAssertFalse(decoded.appearance.keepNookOpen)
    }

    func testDecodingNormalizesTheSettings() throws {
        let preset = try Coder.decode(
            #"""
            {
              "format": "opennook.playground-preset",
              "version": 1,
              "settings": {
                "panel": { "topCornerRadius": -5 },
                "companions": [ { "id": "a" }, { "id": "a" }, { "id": "", "kind": "chip" } ]
              }
            }
            """#
        )
        XCTAssertEqual(preset.settings.panel.topCornerRadius, 0)
        XCTAssertEqual(preset.settings.companions.map(\.id), ["a", "a-2", "status"])
    }

    /// A preset written before companions held items names its content with `kind`, and opens with
    /// the same content.
    func testAnOlderPresetsKindOpensAsItsTemplate() throws {
        let preset = try Coder.decode(
            #"""
            {
              "format": "opennook.playground-preset",
              "version": 1,
              "settings": {
                "companions": [
                  { "id": "a", "kind": "actions" },
                  { "id": "b", "kind": "button", "outline": "circle" },
                  { "id": "c", "kind": "controls", "anchor": "trailing", "hidesInSettings": false },
                  { "id": "d", "kind": "chip" },
                  { "id": "e", "kind": "chip", "items": [] }
                ]
              }
            }
            """#
        )
        let companions = preset.settings.companions
        typealias Template = PlaygroundSettings.Companion.Template
        XCTAssertEqual(companions[0].items, Template.actions.items)
        XCTAssertEqual(companions[1].items, Template.button.items)
        XCTAssertEqual(companions[1].outline, .circle)
        XCTAssertEqual(companions[2].items, Template.controls.items)
        XCTAssertEqual(companions[3].items, Template.chip.items)
        XCTAssertTrue(companions[4].items.isEmpty, "items, when present, win over a kind")

        // And it writes back as items, with no kind.
        let written = try Coder.encodeString(preset)
        XCTAssertFalse(written.contains("\"kind\""))
        XCTAssertEqual(try Coder.decode(written), preset)
    }

    func testCompanionItemsAndStyleRoundTrip() throws {
        var item = PlaygroundSettings.Item(symbol: "phone.down.fill", title: "Leave", action: .collapse)
        item.tint = PlaygroundColor(red: 1, green: 1, blue: 1)
        item.fill = .color
        item.fillColor = PlaygroundColor(red: 1, green: 0, blue: 0)
        item.fade = 0.5
        item.size = .surface
        var companion = PlaygroundSettings.Companion(id: "call", items: [item, PlaygroundSettings.Item(type: .label)])
        companion.layout = .column
        companion.gap = 12
        companion.rowAlignment = .end
        companion.size = .large
        companion.presence = .slide
        companion.fade = 0.3
        companion.stroke = false
        companion.shadow = true
        companion.hover = .glow
        companion.accent = PlaygroundColor(red: 0, green: 1, blue: 0)
        var settings = PlaygroundSettings()
        settings.companions = [companion]
        settings.companionDefaults.size = .small
        settings.companionDefaults.hover = .lift
        let preset = PlaygroundPreset(settings: settings)

        XCTAssertEqual(try Coder.decode(Coder.encode(preset)), preset)
    }

    func testAnUnknownItemTypeNamesItsPath() {
        let text = #"""
            {"format": "opennook.playground-preset", "version": 1,
             "settings": {"companions": [{"id": "a", "items": [{"type": "slider"}]}]}}
            """#
        guard case .invalidValue(let detail) = decodingError(text) else {
            return XCTFail("expected an invalid value")
        }
        XCTAssertTrue(detail.hasPrefix("settings.companions[0].items[0].type: "), detail)
    }

    // MARK: - Rejection

    func testRejectsTextThatIsNotJSON() {
        XCTAssertEqual(decodingError("not json"), .notJSON)
        XCTAssertEqual(decodingError(""), .notJSON)
    }

    func testRejectsJSONThatIsNotAPreset() {
        XCTAssertEqual(decodingError("[1, 2]"), .notAPreset)
        XCTAssertEqual(decodingError("{}"), .notAPreset)
        XCTAssertEqual(decodingError(#"{"format": "something-else", "version": 1}"#), .notAPreset)
        XCTAssertEqual(decodingError(#"{"format": "opennook.playground-preset"}"#), .notAPreset)
        XCTAssertEqual(decodingError(#"{"format": "opennook.playground-preset", "version": "1"}"#), .notAPreset)
    }

    func testRejectsFormatVersionsItCannotRead() {
        XCTAssertEqual(
            decodingError(#"{"format": "opennook.playground-preset", "version": 2}"#),
            .unsupportedVersion(2)
        )
        XCTAssertEqual(
            decodingError(#"{"format": "opennook.playground-preset", "version": 0}"#),
            .unsupportedVersion(0)
        )
    }

    func testNamesThePathOfAValueWithTheWrongType() {
        let error = decodingError(
            #"{"format": "opennook.playground-preset", "version": 1, "settings": {"panel": {"expandedWidth": "wide"}}}"#
        )
        XCTAssertEqual(error, .invalidValue("settings.panel.expandedWidth should be a number"))
    }

    func testNamesThePathOfAnUnknownChoice() throws {
        let error = decodingError(
            #"""
            {"format": "opennook.playground-preset", "version": 1,
             "settings": {"companions": [{"id": "a"}, {"id": "b", "anchor": "above"}]}}
            """#
        )
        guard case .invalidValue(let detail) = try XCTUnwrap(error) else {
            return XCTFail("expected an invalid value, got \(String(describing: error))")
        }
        XCTAssertTrue(detail.hasPrefix("settings.companions[1].anchor: "), detail)
        XCTAssertTrue(detail.contains("above"), detail)
    }

    func testNamesThePathOfAMalformedColor() {
        let error = decodingError(
            #"{"format": "opennook.playground-preset", "version": 1, "settings": {"theme": {"accent": "blue"}}}"#
        )
        XCTAssertEqual(
            error,
            .invalidValue(##"settings.theme.accent: expected a color such as "#3F8CFA", found "blue""##)
        )
    }

    func testRejectsAnAppearanceValueTheFrameworkDoesNotKnow() throws {
        let error = decodingError(
            #"{"format": "opennook.playground-preset", "version": 1, "appearance": {"surfaceStyle": "hologram"}}"#
        )
        guard case .invalidValue(let detail) = try XCTUnwrap(error) else {
            return XCTFail("expected an invalid value, got \(String(describing: error))")
        }
        XCTAssertTrue(detail.hasPrefix("appearance.surfaceStyle"), detail)
    }

    func testErrorsDescribeThemselves() {
        let errors: [PlaygroundPresetError] = [
            .notJSON,
            .notAPreset,
            .unsupportedVersion(3),
            .invalidValue("settings.panel.expandedWidth should be a number"),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertTrue(PlaygroundPresetError.notAPreset.localizedDescription.contains("opennook.playground-preset"))
        XCTAssertTrue(PlaygroundPresetError.unsupportedVersion(3).localizedDescription.contains("version 3"))
        XCTAssertTrue(
            PlaygroundPresetError.invalidValue("x should be a number").localizedDescription.contains(
                "x should be a number"
            )
        )
    }
}

final class PlaygroundColorTests: XCTestCase {
    func testHexRoundTrips() throws {
        XCTAssertEqual(PlaygroundColor(hex: "#3F8CFA")?.hex, "#3F8CFA")
        XCTAssertEqual(PlaygroundColor(hex: "3f8cfa80")?.hex, "#3F8CFA80")
        XCTAssertEqual(PlaygroundColor(hex: " #FFFFFFFF ")?.hex, "#FFFFFF", "an opaque color drops its alpha")
        let color = try XCTUnwrap(PlaygroundColor(hex: "#3F8CFA80"))
        XCTAssertEqual(PlaygroundColor(hex: color.hex), color)
    }

    func testRejectsMalformedHex() {
        for text in ["", "#", "#12345", "#1234567", "#GGGGGG", "+FFFFF", "-FFFFF", "#FFFFFF0"] {
            XCTAssertNil(PlaygroundColor(hex: text), text)
        }
    }

    func testComponentsAreClampedAndKeptAtEightBits() {
        let color = PlaygroundColor(red: 2, green: -1, blue: 0.5, opacity: 0.25)
        XCTAssertEqual(color.hex, "#FF008040")
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 128.0 / 255)
        XCTAssertEqual(PlaygroundColor(red: 0.1, green: 0.2, blue: 0.25), PlaygroundColor(hex: "#1A3340"))
    }
}

final class PlaygroundStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        suiteName = "opennook.playground.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        // Removing the domain still leaves an empty plist behind, one per test run.
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: file)
    }

    func testAnEmptyStoreLoadsTheDefaults() {
        let store = PlaygroundStore(defaults: defaults)
        XCTAssertEqual(store.loadSettings(), .default)
        XCTAssertEqual(store.loadDemo(), PlaygroundDemo())
    }

    func testSettingsAndDemoSurviveARelaunch() {
        let settings = PlaygroundFixtures.everythingChanged.settings
        var demo = PlaygroundDemo()
        demo.rimGlowLit = true
        demo.statusMessage = "Hello"
        PlaygroundStore(defaults: defaults).saveSettings(settings)
        PlaygroundStore(defaults: defaults).saveDemo(demo)

        let relaunched = PlaygroundStore(defaults: defaults)
        XCTAssertEqual(relaunched.loadSettings(), settings)
        XCTAssertEqual(relaunched.loadDemo(), demo)
    }

    func testUnreadableDataLoadsTheDefaults() {
        defaults.set(Data("not json".utf8), forKey: PlaygroundStore.settingsKey)
        defaults.set(Data("[]".utf8), forKey: PlaygroundStore.demoKey)
        let store = PlaygroundStore(defaults: defaults)
        XCTAssertEqual(store.loadSettings(), .default)
        XCTAssertEqual(store.loadDemo(), PlaygroundDemo())
    }

    func testLoadedSettingsAreNormalized() {
        var settings = PlaygroundSettings()
        settings.companions = [
            PlaygroundSettings.Companion(id: "a", template: .chip),
            PlaygroundSettings.Companion(id: "a", template: .chip),
        ]
        let store = PlaygroundStore(defaults: defaults)
        store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings().companions.map(\.id), ["a", "a-2"])
    }
}
