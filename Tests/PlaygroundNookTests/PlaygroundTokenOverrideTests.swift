// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import NookSurface
import SwiftUI
import XCTest

@testable import PlaygroundNookCore

/// Everything a theme can express, edited in the playground: token overrides by id, the knobs
/// and backdrops beyond Stage A, top bar symbols, and Settings group titles, through the live
/// configuration, the preset, the theme file, the Swift export, and the assistant.
final class PlaygroundTokenOverrideTests: XCTestCase {
    private func makeConfiguration(_ settings: PlaygroundSettings) -> NookConfiguration {
        settings.makeConfiguration(home: { Text("home") }, companion: { _ in Text("c") })
    }

    // MARK: - The theme

    func testTokenOverridesAndNewKnobsReachTheChromeTheme() {
        var settings = PlaygroundSettings()
        settings.theme.tokens[.bannerCornerRadius] = 14
        settings.theme.tokens[.statusBanner] = .reference(.springSnappy)
        settings.theme.fontWidth = .condensed
        settings.theme.soundVolume = 0.4
        settings.theme.allowsUserAccent = false
        settings.theme.allowsUserSoundToggle = false
        settings.theme.palette = .dark
        settings.theme.surface = .translucent
        settings.theme.backdropStrength = 0.5
        settings.theme.name = "Night"
        settings.theme.backdrops.translucent = .solid("#101014")

        let theme = makeConfiguration(settings).chromeTheme
        XCTAssertEqual(theme?.tokens[.bannerCornerRadius], 14)
        XCTAssertEqual(theme?.tokens[.statusBanner], .reference(.springSnappy))
        XCTAssertEqual(theme?.fontWidth, .condensed)
        XCTAssertEqual(theme?.soundVolume, 0.4)
        XCTAssertEqual(theme?.allowsUserAccent, false)
        XCTAssertEqual(theme?.allowsUserSoundToggle, false)
        XCTAssertEqual(theme?.palette, .dark)
        XCTAssertEqual(theme?.surface, .translucent)
        XCTAssertEqual(theme?.backdropStrength, 0.5)
        XCTAssertEqual(theme?.name, "Night")
        XCTAssertEqual(theme?.backdrops.translucent, .solid("#101014"))
    }

    func testAColorRoleWinsOverAnOverrideOfItsToken() {
        var theme = PlaygroundSettings.Theme()
        theme.tokens[.labelPrimary] = .accent
        theme.tokens[.accent] = "#00FF00"
        theme.primaryLabel = PlaygroundColor(red: 1, green: 0, blue: 0)
        theme.accent = PlaygroundColor(red: 0, green: 0, blue: 1)
        let nook = theme.nookTheme
        XCTAssertEqual(nook.tokens[.labelPrimary], .hex(PlaygroundColor(red: 1, green: 0, blue: 0)))
        XCTAssertEqual(nook.accent, .hex(PlaygroundColor(red: 0, green: 0, blue: 1)))
        XCTAssertNil(nook.tokens[.accent])
    }

    func testTheTokenFunnelStoresAPlainColorInItsRoleAndAnythingElseAsAToken() {
        var theme = PlaygroundSettings.Theme()
        let red = PlaygroundColor(red: 1, green: 0, blue: 0)

        theme.setTokenOverride(.color(.hex(red)), for: "color.label.primary")
        XCTAssertEqual(theme.primaryLabel, red)
        XCTAssertTrue(theme.tokens.isEmpty)
        XCTAssertEqual(theme.tokenOverride("color.label.primary"), .color(.hex(red)))

        let pair = NookColorValue.adaptive(NookAdaptiveColor(dark: "#FFFFFF", light: "#000000"))
        theme.setTokenOverride(.color(pair), for: "color.label.primary")
        XCTAssertNil(theme.primaryLabel)
        XCTAssertEqual(theme.tokens[.labelPrimary], pair)
        XCTAssertEqual(theme.tokenOverride("color.label.primary"), .color(pair))

        theme.setTokenOverride(.color(.hex(red)), for: "color.accent")
        XCTAssertEqual(theme.accent, red)

        theme.setTokenOverride(.dimension(3), for: "space.md")
        XCTAssertEqual(theme.tokens[.spaceMD], 3)

        // A value of the wrong kind, or an id the framework does not define, changes nothing.
        let before = theme
        theme.setTokenOverride(.dimension(3), for: "color.destructive")
        theme.setTokenOverride(.dimension(3), for: "made.up")
        XCTAssertEqual(theme, before)

        theme.setTokenOverride(nil, for: "color.label.primary")
        theme.setTokenOverride(nil, for: "space.md")
        XCTAssertNil(theme.tokenOverride("color.label.primary"))
        XCTAssertNil(theme.tokenOverride("space.md"))
    }

    func testNormalizingMovesAPlainRoleColorIntoItsRoleAndKeepsTheRoleWinning() {
        var settings = PlaygroundSettings()
        settings.theme.tokens[.labelSecondary] = "#336699"
        settings.theme.tokens[.destructive] = "#FF0000"
        settings.theme.destructive = PlaygroundColor(red: 0, green: 1, blue: 0)
        settings.theme.tokens[.warning] = .accent
        settings.theme.soundVolume = 3
        settings.theme.backdropStrength = 0
        settings.theme.name = "  "
        settings.topBar.settingsSymbol = " "

        let normalized = settings.normalized()
        XCTAssertEqual(normalized.theme.secondaryLabel, PlaygroundColor(hex: "#336699"))
        XCTAssertNil(normalized.theme.tokens[.labelSecondary])
        XCTAssertEqual(normalized.theme.destructive, PlaygroundColor(red: 0, green: 1, blue: 0))
        XCTAssertNil(normalized.theme.tokens[.destructive])
        XCTAssertEqual(normalized.theme.tokens[.warning], .accent)
        XCTAssertEqual(normalized.theme.soundVolume, 1)
        XCTAssertEqual(normalized.theme.backdropStrength, 0.15)
        XCTAssertNil(normalized.theme.name)
        XCTAssertNil(normalized.topBar.settingsSymbol)
    }

    func testTheThemePagesOwnValuesLeaveOutTheTokens() {
        var theme = PlaygroundSettings.Theme()
        theme.tokens[.spaceMD] = 9
        XCTAssertEqual(theme.withoutTokens, PlaygroundSettings.Theme())
    }

    // MARK: - Top bar and labels

    func testSymbolsAndGroupTitlesReachTheConfiguration() {
        var settings = PlaygroundSettings()
        settings.topBar.keepOpenOnSymbol = "pin.fill"
        settings.topBar.keepOpenOffSymbol = "pin"
        settings.topBar.settingsSymbol = "slider.horizontal.3"
        settings.topBar.breadcrumbSeparatorSymbol = "chevron.forward"
        settings.topBar.backSymbol = "chevron.backward"
        settings.labels.appearanceTitle = "Look"
        settings.labels.aboutTitle = "Info"

        let configuration = makeConfiguration(settings)
        let symbols = configuration.topBar.symbols
        XCTAssertEqual(symbols.keepOpenOn, "pin.fill")
        XCTAssertEqual(symbols.keepOpenOff, "pin")
        XCTAssertEqual(symbols.settings, "slider.horizontal.3")
        XCTAssertEqual(symbols.breadcrumbSeparator, "chevron.forward")
        XCTAssertEqual(symbols.back, "chevron.backward")
        XCTAssertEqual(configuration.labels.settings.appearanceTitle, "Look")
        XCTAssertEqual(configuration.labels.settings.aboutTitle, "Info")
        XCTAssertEqual(configuration.labels.settings.displayTitle, NookChromeLabels.default.settings.displayTitle)
    }

    func testUnsetSymbolsAndTitlesAreTheFrameworks() {
        let configuration = makeConfiguration(PlaygroundSettings())
        XCTAssertEqual(configuration.topBar.symbols, .default)
        XCTAssertEqual(configuration.labels, .default)
        for symbol in PlaygroundSettings.TopBar.Symbol.allCases {
            XCTAssertNil(PlaygroundSettings.TopBar()[symbol])
        }
        XCTAssertEqual(PlaygroundSettings.Labels.GroupTitle.appearanceTitle.defaultTitle, "Appearance")
    }

    // MARK: - Presets

    private static var themedSettings: PlaygroundSettings {
        var settings = PlaygroundSettings()
        settings.theme.accent = PlaygroundColor(red: 1, green: 0.5, blue: 0)
        settings.theme.tokens[.spaceMD] = 9
        settings.theme.tokens[.bannerCornerRadius] = .reference(.radiusLG, times: 1.5)
        settings.theme.tokens[.labelTertiary] = .adaptive(NookAdaptiveColor(dark: .white(opacity: 0.5), light: .accent))
        settings.theme.tokens[.bannerMessage] = NookFontSpec(role: .typeBody, weight: .semibold, design: .rounded)
        settings.theme.tokens[.statusBanner] = .curve(.easeOut, duration: 0.2)
        settings.theme.tokens[.contentEnter] = NookContentTransitionSpec(blur: 8, scaleX: 0.97, scaleY: 0.97)
        settings.theme.tokens[.open] = .system("Pop", volume: 0.6)
        settings.theme.tokens[.chrome] = NookShadowSpec(radius: 10, y: 4)
        settings.theme.tokens[.stagger] = 0.035
        settings.theme.backdrops.liquidGlass = .liquidGlass(
            .init(
                tint: .accent,
                variant: .clear,
                fallbackMaterial: .hudWindow,
                highlightColor: "#FFEEDD",
                rimWidth: 1.5
            )
        )
        settings.theme.backdrops.solid = .mesh(
            .init(
                width: 2,
                height: 2,
                points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                colors: ["#110000", "#001100", "#000011", "#000000"]
            )
        )
        settings.theme.backdrops.glassShading = .notchFade
        settings.theme.fontWidth = .expanded
        settings.topBar.settingsSymbol = "slider.horizontal.3"
        settings.labels.displayTitle = "Screens"
        return settings
    }

    func testAPresetWithTokenOverridesSurvivesARoundTrip() throws {
        let preset = PlaygroundPreset(settings: Self.themedSettings)
        let text = try PlaygroundPresetCoder.encodeString(preset)
        XCTAssertTrue(text.contains("\"tokens\" : {"), text)
        XCTAssertTrue(text.contains("\"banner.cornerRadius\""), text)
        XCTAssertTrue(text.contains("\"shadow.chrome\""), text)
        let decoded = try PlaygroundPresetCoder.decode(text)
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.settings.theme.nookTheme, preset.settings.theme.nookTheme)
    }

    func testUntouchedNewFieldsStayOutOfAPreset() throws {
        let text = try PlaygroundPresetCoder.encodeString(PlaygroundPreset())
        for key in [
            "tokens", "backdrops", "fontWidth", "soundVolume", "allowsUserAccent", "palette", "\"surface\"",
            "keepOpenOnSymbol", "settingsSymbol", "appearanceTitle", "\"name\"",
        ] {
            XCTAssertFalse(text.contains(key), "\(key) is in an untouched preset")
        }
    }

    func testAPresetNamesTheTokenOfTheWrongKind() {
        let json = ##"""
            { "format": "opennook.playground-preset", "version": 1,
              "settings": { "theme": { "tokens": { "space.md": "#FF0000" } } } }
            """##
        XCTAssertThrowsError(try PlaygroundPresetCoder.decode(json)) { error in
            guard case .invalidValue(let detail)? = error as? PlaygroundPresetError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(detail.hasPrefix("settings.theme.tokens.space.md"), detail)
        }
    }

    func testAPresetSkipsATokenTheFrameworkDoesNotDefine() throws {
        let json = ##"""
            { "format": "opennook.playground-preset", "version": 1,
              "settings": { "theme": { "tokens": { "made.up": 3, "space.md": 7 } } } }
            """##
        XCTAssertEqual(try PlaygroundPresetCoder.decode(json).settings.theme.tokens.ids, ["space.md"])
    }

    // MARK: - Theme file

    func testTheThemeFileCarriesTheTokenOverrides() throws {
        let settings = Self.themedSettings
        let text = try NookThemeCoder.encodeString(settings.theme.nookTheme)
        for id in ["space.md", "banner.cornerRadius", "color.label.tertiary", "sound.open", "shadow.chrome"] {
            XCTAssertTrue(text.contains("\"\(id)\""), "\(id) is not in the theme file")
        }
        XCTAssertTrue(text.contains("\"components\""), text)
        XCTAssertEqual(try NookThemeCoder.decode(text).theme, settings.theme.nookTheme)
    }

    // MARK: - Hand-built pages

    func testAChangedHandBuiltControlNamesItsPage() {
        var settings = PlaygroundSettings()
        XCTAssertNil(settings.pageOverriding(token: "banner.cornerRadius"))
        XCTAssertNil(settings.pageOverriding(token: "shape.chrome.bottomRadius"))

        settings.metrics.bannerCornerRadius = 4
        settings.typography.bannerMessage.weight = .bold
        settings.motion.statusBanner.response = 0.5
        settings.panel.bottomCornerRadius = 30
        XCTAssertEqual(settings.pageOverriding(token: "banner.cornerRadius"), "Panel")
        XCTAssertEqual(settings.pageOverriding(token: "shape.compact.topRadius"), "Panel")
        XCTAssertEqual(settings.pageOverriding(token: "banner.message.font"), "Type and Motion")
        XCTAssertEqual(settings.pageOverriding(token: "motion.statusBanner"), "Type and Motion")
        XCTAssertNil(settings.pageOverriding(token: "space.md"))
    }

    // MARK: - Swift export

    func testTheSwiftExportWritesTokenOverridesBackdropsSymbolsAndTitles() {
        let snippet = PlaygroundSwiftExporter.snippet(for: PlaygroundPreset(settings: Self.themedSettings))
        let expected = [
            "var theme = NookTheme(fontWidth: .expanded)",
            "theme.accent = \"#FF8000\"",
            // Too long for one line, so each breaks one argument per line.
            """
            theme.tokens[NookDimensionID("banner.cornerRadius")] = NookDimension.reference(
                "radius.lg",
                times: 1.5
            )
            """,
            """
            theme.tokens[NookFontID("banner.message.font")] = NookFontSpec(
                role: "type.body",
                weight: .semibold,
                design: .rounded
            )
            """,
            """
            theme.tokens[.labelTertiary] = .adaptive(NookAdaptiveColor(
                dark: .white(opacity: 0.5),
                light: .accent
            ))
            """,
            "theme.tokens[NookAnimationID(\"motion.statusBanner\")] = .curve(.easeOut, duration: 0.2)",
            "theme.tokens[NookDimensionID(\"motion.stagger\")] = 0.035",
            "theme.tokens[NookSoundID(\"sound.open\")] = NookSoundSpec.system(\"Pop\", volume: 0.6)",
            "theme.tokens[NookShadowID(\"shadow.chrome\")] = NookShadowSpec(radius: 10, y: 4)",
            "theme.tokens[NookDimensionID(\"space.md\")] = 9",
            "theme.backdrops.glassShading = .notchFade",
            "configuration.topBar.symbols.settings = \"slider.horizontal.3\"",
            "configuration.labels.settings.displayTitle = \"Screens\"",
        ]
        for line in expected {
            XCTAssertTrue(snippet.contains(line), "missing: \(line)\n\(snippet)")
        }
        // A long value breaks one argument per line.
        XCTAssertTrue(snippet.contains("theme.backdrops.liquidGlass = .liquidGlass(.init(\n"), snippet)
        XCTAssertTrue(snippet.contains("theme.backdrops.solid = .mesh(.init(\n"), snippet)
        XCTAssertTrue(snippet.contains("theme.tokens[NookTransitionID(\"motion.content.enter\")]"), snippet)
    }

    func testValueLiteralsAreTheSwiftAHostWrites() {
        typealias Exporter = PlaygroundSwiftExporter
        XCTAssertEqual(Exporter.literal(NookColorValue.accent), ".accent")
        XCTAssertEqual(
            Exporter.literal(NookColorValue.reference(.labelPrimary, opacity: nil)),
            "\"{color.label.primary}\""
        )
        XCTAssertEqual(
            Exporter.literal(NookColorValue.reference(.accent, opacity: 0.5)),
            ".reference(\"color.accent\", opacity: 0.5)"
        )
        XCTAssertEqual(Exporter.literal(NookColorValue.system(.red)), ".system(.red)")
        XCTAssertEqual(Exporter.literal(NookDimension.token(.spaceMD)), "NookDimension.token(\"space.md\")")
        XCTAssertEqual(Exporter.literal(NookFontSpec.role(.typeBody)), "NookFontSpec.role(\"type.body\")")
        XCTAssertEqual(
            Exporter.literal(NookAnimationSpec.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)),
            ".spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)"
        )
        XCTAssertEqual(
            Exporter.literal(NookAnimationSpec.preset(.snappy, duration: 0.4)),
            ".preset(.snappy, duration: 0.4)"
        )
        XCTAssertEqual(
            Exporter.literal(NookContentTransitionSpec.expandedContentDefault),
            "NookContentTransitionSpec(blur: 6, scaleY: 0.72, anchor: .top)"
        )
        XCTAssertEqual(
            Exporter.literal(NookSoundSpec(.file(URL(fileURLWithPath: "/tmp/a.caf")))),
            "NookSoundSpec(.file(URL(fileURLWithPath: \"/tmp/a.caf\")))"
        )
        XCTAssertEqual(
            Exporter.literal(
                NookBackdropDescription.linearGradient(
                    .init(gradient: NookGradientSpec(colors: ["#101014", "#000000"]))
                )
            ),
            ".linearGradient(.init(gradient: NookGradientSpec(colors: [\"#101014\", \"#000000\"]), start: .top, end: .bottom))"
        )
        XCTAssertEqual(
            Exporter.literal(
                NookGradientSpec(stops: [.init(color: "#FF0000", location: 0), .init(color: "#0000FF", location: 0.8)])
            ),
            "NookGradientSpec(stops: [.init(color: \"#FF0000\", location: 0), .init(color: \"#0000FF\", location: 0.8)])"
        )
        XCTAssertEqual(Exporter.literal(NookUnitPointSpec(x: 0.2, y: 0.3)), "NookUnitPointSpec(x: 0.2, y: 0.3)")
    }

    func testALongCallSplitsAtItsOwnArgumentsOnly() throws {
        let parts = try XCTUnwrap(PlaygroundSwiftExporter.splitCall(#"Head(a: [1, 2], b: "x, (y)", c: f(1, 2))"#))
        XCTAssertEqual(parts.head, "Head")
        XCTAssertEqual(parts.arguments, ["a: [1, 2]", #"b: "x, (y)""#, "c: f(1, 2)"])
        XCTAssertEqual(parts.tail, "")
        XCTAssertNil(PlaygroundSwiftExporter.splitCall("12"))
    }

    // MARK: - Assistant

    private func patch(_ text: String) throws -> AssistantJSON {
        try XCTUnwrap(AssistantJSON(parsing: text))
    }

    func testAPatchOverridesTokensByID() throws {
        var base = PlaygroundPreset()
        base.settings.theme.tokens[.spaceMD] = 9
        let result = try AssistantPatch.apply(
            patch(#"{ "settings": { "theme": { "tokens": { "banner.cornerRadius": 4, "space.md": null } } } }"#),
            to: base
        )
        XCTAssertEqual(result.settings.theme.tokens[.bannerCornerRadius], 4)
        XCTAssertNil(result.settings.theme.tokens[.spaceMD])
    }

    func testAPatchNamingATokenTheRegistryLacksIsRejected() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(
                patch(#"{ "settings": { "theme": { "tokens": { "banner.cornerRadiu": 4 } } } }"#),
                to: PlaygroundPreset()
            )
        ) { error in
            XCTAssertEqual(error as? AssistantPatchError, .unknownToken(id: "banner.cornerRadiu"))
            XCTAssertTrue((error as? AssistantPatchError)?.repairRequest.contains("banner.cornerRadiu") == true)
        }
        XCTAssertThrowsError(
            try AssistantPatch.apply(patch(#"{ "settings": { "theme": { "tokens": 4 } } }"#), to: PlaygroundPreset())
        ) { error in
            guard case .wrongShape(let path, _)? = error as? AssistantPatchError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(path, "settings.theme.tokens")
        }
    }

    func testAPatchWithATokenOfTheWrongKindNamesItsPath() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(
                patch(##"{ "settings": { "theme": { "tokens": { "space.md": "#FF0000" } } } }"##),
                to: PlaygroundPreset()
            )
        ) { error in
            guard case .invalidValue(let detail)? = error as? AssistantPatchError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(detail.contains("settings.theme.tokens.space.md"), detail)
        }
    }

    func testAPatchCanPaintABackdrop() throws {
        let result = try AssistantPatch.apply(
            patch(
                ##"""
                { "settings": { "theme": { "backdrops": {
                  "solid": { "kind": "linearGradient", "stops": ["#101014", "#000000"] } } } } }
                """##
            ),
            to: PlaygroundPreset()
        )
        XCTAssertEqual(
            result.settings.theme.backdrops.solid,
            .linearGradient(.init(gradient: NookGradientSpec(colors: ["#101014", "#000000"])))
        )
    }

    func testEachTokenChangeIsARowThatCanBeSwitchedOff() throws {
        var base = PlaygroundPreset()
        base.settings.theme.tokens[.spaceMD] = 9
        let proposal = try AssistantDiff.proposal(
            base: base,
            patch: patch(
                ##"""
                { "settings": { "theme": { "tokens": {
                  "banner.cornerRadius": 4, "color.destructive": "#FF0000", "space.md": null } } } }
                """##
            ),
            explanation: "",
            notReproduced: []
        )
        XCTAssertEqual(
            proposal.changes.map(\.id),
            [
                // A plain color for a role's token lands in the role, which the catalog lists first.
                "settings.theme.destructive",
                "settings.theme.tokens[banner.cornerRadius]",
                "settings.theme.tokens[space.md]",
            ]
        )
        let corner = try XCTUnwrap(proposal.changes.first { $0.id == "settings.theme.tokens[banner.cornerRadius]" })
        XCTAssertEqual(corner.group, .tokens)
        XCTAssertEqual(corner.title, "banner.cornerRadius")
        XCTAssertEqual(corner.newValue, .number(4, .points))
        XCTAssertEqual(corner.oldValue, .none)

        // Switching the corner off keeps the rest.
        let kept = Set(proposal.changes.map(\.id)).subtracting([corner.id])
        let applied = try proposal.preset(applying: kept)
        XCTAssertNil(applied.settings.theme.tokens[.bannerCornerRadius])
        XCTAssertNil(applied.settings.theme.tokens[.spaceMD])
        XCTAssertEqual(applied.settings.theme.destructive, PlaygroundColor(hex: "#FF0000"))

        // Switching the removal off puts the old override back.
        let restored = try proposal.preset(applying: [corner.id])
        XCTAssertEqual(restored.settings.theme.tokens[.spaceMD], 9)
        XCTAssertEqual(restored.settings.theme.tokens[.bannerCornerRadius], 4)
    }
}
