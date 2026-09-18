// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import NookSurface
import XCTest

@testable import PlaygroundNookCore

final class PlaygroundSwiftExporterTests: XCTestCase {
    private typealias Exporter = PlaygroundSwiftExporter

    // MARK: - Whole snippets

    func testDefaultsExportAnEmptyConfiguration() {
        XCTAssertEqual(
            Exporter.snippet(for: PlaygroundPreset()),
            """
            import NookApp
            import SwiftUI

            var configuration = NookConfiguration()
            configuration.setHome { MyHomeView() }  // your home view

            // Every other setting is at its default.

            NookApp.main(configuration)

            """
        )
    }

    func testEverySectionAppearsInOrderWhenChanged() {
        XCTAssertEqual(
            Exporter.snippet(for: PlaygroundFixtures.everythingChanged),
            PlaygroundFixtures.everythingChangedSwift
        )
    }

    func testKeepOpenIsNeverExported() {
        var appearance = NookAppearancePreferences()
        appearance.keepNookOpen = true
        XCTAssertEqual(
            Exporter.snippet(for: PlaygroundPreset(appearance: appearance)),
            Exporter.snippet(for: PlaygroundPreset())
        )
    }

    /// Values a slider leaves a hair off the default are not worth a line of code.
    func testValuesEqualToTheDefaultAtExportPrecisionAreLeftOut() {
        var settings = PlaygroundSettings()
        settings.panel.expandedWidth += 0.0001
        settings.metrics.edgePadding -= 0.0001
        settings.rimGlow.intensity += 0.0001
        XCTAssertEqual(
            Exporter.snippet(for: PlaygroundPreset(settings: settings)),
            Exporter.snippet(for: PlaygroundPreset())
        )
    }

    // MARK: - Sections

    func testAppearanceExportsChangedArgumentsInInitializerOrder() {
        let appearance = NookAppearancePreferences(
            chromePalette: .light,
            surfaceStyle: .translucent,
            presentation: .notch,
            hapticFeedbackEnabled: true,
            accentPreset: .rose,
            backdropStrength: 0.6
        )
        XCTAssertEqual(
            Exporter.appearanceLines(appearance),
            [
                "// Launch appearance. It seeds the first run; the user's own Settings choices win.",
                "configuration.preferenceDefaults = NookPreferenceDefaults(",
                "    appearance: NookAppearancePreferences(",
                "        chromePalette: .light,",
                "        surfaceStyle: .translucent,",
                "        presentation: .notch,",
                "        hapticFeedbackEnabled: true,",
                "        accentPreset: .rose,",
                "        backdropStrength: 0.6",
                "    )",
                ")",
            ]
        )
        XCTAssertEqual(Exporter.appearanceLines(.default), [])
        XCTAssertEqual(
            Exporter.appearanceLines(NookAppearancePreferences(accentPreset: .teal))[3],
            "        accentPreset: .teal"
        )
    }

    func testThemeExportsOverridesOnTheLivePalette() {
        var theme = PlaygroundSettings.Theme()
        XCTAssertEqual(Exporter.themeLines(theme), [])

        theme.headerInactiveIcon = PlaygroundColor(red: 1, green: 1, blue: 1, opacity: 0.2)
        theme.accent = PlaygroundColor(red: 0, green: 0.5, blue: 1)
        XCTAssertEqual(
            Exporter.themeLines(theme),
            [
                "// The live palette, which follows the user's palette and accent, with overrides.",
                "configuration.theme = { appState in",
                "    var theme = NookResolvedTheme.live(appState: appState)",
                "    theme.accent = Color(red: 0, green: 0.502, blue: 1)",
                "    theme.headerInactiveIcon = Color(red: 1, green: 1, blue: 1, opacity: 0.2)",
                "    return theme",
                "}",
            ]
        )

        theme = PlaygroundSettings.Theme()
        theme.fontDesign = .monospaced
        XCTAssertEqual(Exporter.themeLines(theme)[3], "    theme.fontDesign = .monospaced")
    }

    func testPanelExportsTheWidthAndOnlyTheStyleValuesThatChanged() {
        var panel = PlaygroundSettings.Panel()
        XCTAssertEqual(Exporter.panelLines(panel), [])

        panel.expandedWidth = 600
        XCTAssertEqual(Exporter.panelLines(panel), ["configuration.expandedWidth = 600"])

        panel.topCornerRadius = 12.5
        panel.insetLeading = 0
        XCTAssertEqual(
            Exporter.panelLines(panel),
            [
                "configuration.expandedWidth = 600",
                "configuration.style = NookConfiguration.defaultStyle",
                "configuration.style?.topCornerRadius = 12.5",
                "configuration.style?.expandedContentInsets.leading = 0",
            ]
        )
    }

    func testTokensExportOnlyChangedValues() {
        var settings = PlaygroundSettings()
        XCTAssertEqual(Exporter.tokenLines(settings), [])

        settings.metrics.topBarHeight = 28
        settings.metrics.bannerCornerRadius = 4
        settings.typography.bannerMessage = PlaygroundSettings.FontSpec(size: 12, weight: .bold)
        settings.typography.headerIcon.weight = .semibold
        settings.motion.statusBanner = PlaygroundSettings.SpringSpec(response: 0.5, dampingFraction: 0.6)
        settings.labels.dismissHelp = "Pr\u{E9}f\u{E9}rences"
        XCTAssertEqual(
            Exporter.tokenLines(settings),
            [
                "configuration.metrics.topBarHeight = 28",
                "configuration.metrics.bannerCornerRadius = 4",
                "configuration.typography.bannerMessage = .system(size: 12, weight: .bold)",
                "configuration.motion.statusBanner = .spring(response: 0.5, dampingFraction: 0.6)",
                "configuration.labels.dismissHelp = \"Pr\u{E9}f\u{E9}rences\"",
            ]
        )
    }

    func testTopBarExportsFlagsWidthTitleAndIcon() {
        var topBar = PlaygroundSettings.TopBar()
        XCTAssertEqual(Exporter.topBarLines(topBar), [])

        topBar.showsTopBar = false
        topBar.showsSettings = false
        topBar.showsStatusBanner = false
        topBar.width = .intrinsic
        topBar.leadingTitle = "Say \"hi\""
        topBar.leadingIcon = "sun.max"
        XCTAssertEqual(
            Exporter.topBarLines(topBar),
            [
                "configuration.topBar.showsTopBar = false",
                "configuration.topBar.showsSettings = false",
                "configuration.topBar.showsStatusBanner = false",
                "configuration.topBar.width = .intrinsic",
                #"configuration.topBar.leadingTitle = { _ in "Say \"hi\"" }"#,
                #"configuration.topBar.leadingIcon = "sun.max""#,
            ]
        )
    }

    func testACompanionWithDefaultsExportsItsIDAndContent() {
        var settings = PlaygroundSettings()
        settings.companions = [PlaygroundSettings.Companion(id: "chip", template: .chip)]
        XCTAssertEqual(
            Exporter.companionLines(settings),
            [
                #"configuration.addCompanion(id: "chip") {"#,
                "    ChipCompanion()",
                "}",
            ]
        )
        XCTAssertEqual(
            Exporter.companionViewLines(settings),
            [
                "struct ChipCompanion: View {",
                "    @Environment(\\.nookResolvedTheme) private var theme",
                "",
                "    var body: some View {",
                "        HStack(spacing: 6) {",
                #"            Image(systemName: "sparkles")"#,
                "                .foregroundStyle(theme.accent)",
                #"            Text("3 new")"#,
                "                .foregroundStyle(theme.primaryLabel)",
                "                .lineLimit(1)",
                "        }",
                "        .font(.system(size: 12, weight: .semibold))",
                "        .padding(.horizontal, 8)",
                "        .accessibilityElement(children: .combine)",
                "    }",
                "}",
            ]
        )
        XCTAssertEqual(Exporter.companionLines(PlaygroundSettings()), [])
        XCTAssertEqual(Exporter.companionViewLines(PlaygroundSettings()), [])
    }

    func testLongCompanionCallsBreakOneArgumentPerLine() {
        var button = PlaygroundSettings.Companion(id: "timer", template: .button, accessibilityLabel: "Sleep timer")
        button.anchor = .leading
        button.alignment = .start
        button.spacing = 10
        button.visibility = .compact
        button.backdrop = .glass
        button.backdropColor = PlaygroundColor(red: 1, green: 1, blue: 1, opacity: 0.2)
        var settings = PlaygroundSettings()
        settings.companions = [button]
        XCTAssertEqual(
            Exporter.companionLines(settings),
            [
                "configuration.addCompanion(",
                #"    id: "timer","#,
                "    anchor: .leading(alignment: .start),",
                "    spacing: 10,",
                "    visibility: .compact,",
                "    shape: .circle,",
                "    backdrop: .custom(.liquidGlass(.init(tint: Color(red: 1, green: 1, blue: 1, opacity: 0.2)))),",
                #"    accessibilityLabel: "Sleep timer""#,
                ") {",
                "    TimerCompanion()",
                "}",
            ]
        )
    }

    /// The companion defaults come first, then each companion names only what it sets itself.
    func testCompanionDefaultsAndOverridesExport() {
        var settings = PlaygroundSettings()
        settings.companionDefaults.size = .large
        settings.companionDefaults.presence = .slide
        settings.companionDefaults.fade = 0.25
        var pill = PlaygroundSettings.Companion(id: "pill", template: .actions)
        pill.gap = 16
        pill.rowAlignment = .end
        pill.size = .small
        pill.presence = .pop
        pill.stroke = true
        pill.hover = .glow
        settings.companions = [pill]

        XCTAssertEqual(
            Exporter.companionLines(settings),
            [
                "// How every companion looks and appears, unless it says otherwise.",
                "configuration.companionSize = .large",
                "configuration.companionStyle = .faded",
                "configuration.companionPresence = .slide",
                "",
                "configuration.addCompanion(",
                #"    id: "pill","#,
                "    gap: 16,",
                "    rowAlignment: .end,",
                "    style: .standard(fade: .standard, stroke: .hairline, hover: .glow),",
                "    size: .small,",
                "    presence: .pop",
                ") {",
                "    PillCompanion()",
                "}",
            ]
        )
    }

    /// A companion with its own accent builds its palette on the chrome's.
    func testACompanionAccentExportsAThemeOnTheChromes() {
        var settings = PlaygroundSettings()
        var chip = PlaygroundSettings.Companion(id: "chip", template: .chip)
        chip.accent = PlaygroundColor(red: 1, green: 0, blue: 0)
        settings.companions = [chip]
        XCTAssertEqual(
            Exporter.companionLines(settings),
            [
                "let chromeTheme = configuration.theme",
                "configuration.addCompanion(",
                #"    id: "chip","#,
                "    theme: { appState in",
                "        var theme = chromeTheme(appState)",
                "        theme.accent = Color(red: 1, green: 0, blue: 0)",
                "        return theme",
                "    }",
                ") {",
                "    ChipCompanion()",
                "}",
            ]
        )
    }

    /// Items export as real controls: glyph buttons styled once for the group, a button with
    /// changes of its own styled on its own, and the framework's chrome controls and actions.
    func testCompanionContentExportsItsItems() {
        var leave = PlaygroundSettings.Item(symbol: "phone.down.fill", title: "Leave", action: .collapse)
        leave.tint = PlaygroundColor(red: 1, green: 1, blue: 1)
        leave.fill = .color
        leave.fillColor = PlaygroundColor(red: 1, green: 0, blue: 0)
        leave.fade = 0.5
        leave.size = .surface
        var call = PlaygroundSettings.Companion(
            id: "call-controls",
            items: [
                PlaygroundSettings.Item(symbol: "mic.fill", title: "Mute"),
                PlaygroundSettings.Item(symbol: "gearshape", title: "Options", action: .settings),
                leave,
            ]
        )
        call.size = .large
        var column = PlaygroundSettings.Companion(id: "2 controls", template: .controls)
        column.anchor = .trailing
        var settings = PlaygroundSettings()
        settings.companions = [call, column, PlaygroundSettings.Companion(id: "", template: .empty)]

        XCTAssertEqual(
            Exporter.companionViewLines(settings),
            [
                "struct CallControlsCompanion: View {",
                "    @Environment(\\.nookChromeActions) private var chromeActions",
                "",
                "    var body: some View {",
                "        HStack(spacing: 4) {",
                #"            Button("Mute", systemImage: "mic.fill") {}  // your action"#,
                #"            Button("Options", systemImage: "gearshape") { chromeActions.toggleSettings() }"#,
                #"            Button("Leave", systemImage: "phone.down.fill") { chromeActions.collapse() }"#,
                "                .buttonStyle(",
                "                    .nookGlyph(",
                "                        size: .surface,",
                "                        foreground: Color(red: 1, green: 1, blue: 1),",
                "                        fill: .color(Color(red: 1, green: 0, blue: 0)),",
                "                        fade: .init(end: 0.5)",
                "                    )",
                "                )",
                "        }",
                "        .buttonStyle(.nookGlyph)",
                "    }",
                "}",
                "",
                "struct Item2ControlsCompanion: View {",
                "    var body: some View {",
                "        VStack(spacing: 2) {",
                "            NookKeepOpenButton()",
                "            NookSettingsButton()",
                "        }",
                "    }",
                "}",
            ]
        )
        // The empty companion is hidden in the playground, so it is left out with a note.
        let calls = Exporter.companionLines(settings)
        XCTAssertTrue(calls.contains(#"// "" holds nothing yet, so it is left out."#), "\(calls)")
        XCTAssertFalse(calls.contains { $0.contains("ItemCompanion()") })
    }

    /// A label shows only what it has, the way the playground draws it: an icon in its color or
    /// the accent, and its text when it has some.
    func testLabelsExportWhatThePlaygroundShows() {
        var icon = PlaygroundSettings.Item(type: .label, symbol: "bolt.fill")
        icon.tint = PlaygroundColor(red: 1, green: 0, blue: 1)
        let lines = Exporter.itemLines(icon, indent: 0, containerStyled: false)
        XCTAssertEqual(
            lines,
            [
                "HStack(spacing: 6) {",
                #"    Image(systemName: "bolt.fill")"#,
                "        .foregroundStyle(Color(red: 1, green: 0, blue: 1))",
                "}",
                ".font(.system(size: 12, weight: .semibold))",
                ".padding(.horizontal, 8)",
                ".accessibilityElement(children: .combine)",
            ]
        )
        XCTAssertFalse(lines.contains { $0.contains("Label") }, "no placeholder title")

        let text = PlaygroundSettings.Item(type: .label, title: "Live")
        XCTAssertEqual(
            Exporter.itemLines(text, indent: 0, containerStyled: false).prefix(4),
            [
                "HStack(spacing: 6) {",
                #"    Text("Live")"#,
                "        .foregroundStyle(theme.primaryLabel)",
                "        .lineLimit(1)",
            ]
        )
    }

    /// A color fill with no color of its own uses the companion's accent, as the playground does.
    func testAnAccentFillExportsTheThemesAccent() {
        var button = PlaygroundSettings.Item(symbol: "star.fill", title: "Star")
        button.fill = .color
        var settings = PlaygroundSettings()
        settings.companions = [PlaygroundSettings.Companion(id: "star", items: [button])]
        XCTAssertEqual(Exporter.glyphStyleArguments(button), ["fill: .color(theme.accent)"])
        XCTAssertEqual(
            Exporter.companionViewLines(settings).prefix(3),
            ["struct StarCompanion: View {", "    @Environment(\\.nookResolvedTheme) private var theme", ""]
        )
    }

    /// A companion of buttons that are surfaces of their own draws no surface, and says so.
    func testSurfaceButtonsExportThePlainStyle() {
        var leave = PlaygroundSettings.Item(symbol: "phone.down.fill", title: "Leave", action: .collapse)
        leave.size = .surface
        var settings = PlaygroundSettings()
        settings.companions = [PlaygroundSettings.Companion(id: "leave", items: [leave])]
        XCTAssertEqual(
            Exporter.companionLines(settings),
            [
                #"configuration.addCompanion(id: "leave", style: .plain) {"#,
                "    LeaveCompanion()",
                "}",
            ]
        )
        XCTAssertEqual(Exporter.styleLiteral(.plain), ".plain")
    }

    func testCompanionViewNamesAreUniqueSwiftTypes() {
        let companions = ["sleep-timer", "sleep timer", "home", "", "9 lives", "café"].map {
            PlaygroundSettings.Companion(id: $0)
        }
        XCTAssertEqual(
            Exporter.companionViewNames(companions),
            [
                "SleepTimerCompanion",
                "SleepTimerCompanion2",
                "HomeCompanion",
                "ItemCompanion",
                "Item9LivesCompanion",
                "ItemCafCompanion",
            ]
        )
    }

    func testStyleLiteralsNamePresetsAndListDifferences() {
        XCTAssertEqual(Exporter.styleLiteral(.standard), ".standard")
        XCTAssertEqual(Exporter.styleLiteral(.faded), ".faded")
        XCTAssertEqual(Exporter.styleLiteral(.raised), ".raised")
        XCTAssertEqual(
            Exporter.styleLiteral(NookStandardCompanionStyle(fade: .init(end: 0.4), shadow: .soft)),
            ".standard(fade: .init(end: 0.4), shadow: .soft)"
        )
        XCTAssertEqual(Exporter.styleLiteral(NookStandardCompanionStyle(fade: .toClear)), ".standard(fade: .toClear)")
        XCTAssertEqual(Exporter.fadeLiteral(0.25), ".standard")
    }

    func testCompanionAnchorShapeAndBackdropLiterals() {
        var companion = PlaygroundSettings.Companion(id: "x", template: .actions)
        XCTAssertEqual(Exporter.anchorLiteral(companion), ".below")
        companion.anchor = .trailing
        XCTAssertEqual(Exporter.anchorLiteral(companion), ".trailing")
        companion.alignment = .end
        XCTAssertEqual(Exporter.anchorLiteral(companion), ".trailing(alignment: .end)")

        XCTAssertEqual(Exporter.shapeLiteral(companion), ".capsule")
        companion.outline = .roundedRectangle
        companion.cornerRadius = 7.25
        XCTAssertEqual(Exporter.shapeLiteral(companion), ".roundedRectangle(cornerRadius: 7.25)")

        XCTAssertEqual(Exporter.backdropLiteral(companion), ".inherit")
        companion.backdrop = .none
        XCTAssertEqual(Exporter.backdropLiteral(companion), ".none")
        companion.backdrop = .solid
        companion.backdropColor = PlaygroundColor(red: 0, green: 0, blue: 0)
        XCTAssertEqual(Exporter.backdropLiteral(companion), ".custom(.solid(Color(red: 0, green: 0, blue: 0)))")
    }

    func testRimGlowExportsChangedArgumentsWithAHint() {
        var rimGlow = PlaygroundSettings.RimGlow()
        XCTAssertEqual(Exporter.effectLines(rimGlow: rimGlow, scrollEdgeFade: .init()), [])

        rimGlow.glowRadius = 14
        rimGlow.intensity = 0.75
        rimGlow.followsAmbientColor = true
        XCTAssertEqual(
            Exporter.effectLines(rimGlow: rimGlow, scrollEdgeFade: .init()),
            [
                "// The rim shows while chrome content lights it: .nookRimGlow(isBusy ? .blue : nil)",
                "configuration.rimGlow = NookRimGlowStyle(glowRadius: 14, intensity: 0.75, followsAmbientColor: true)",
            ]
        )
    }

    func testScrollEdgeFadeExportsStandardOrItsDifferences() {
        func exported(_ fade: PlaygroundSettings.ScrollEdgeFade) -> String? {
            Exporter.effectLines(rimGlow: .init(), scrollEdgeFade: fade).last
        }
        var fade = PlaygroundSettings.ScrollEdgeFade()
        XCTAssertNil(exported(fade), "off by default")

        fade.isEnabled = true
        XCTAssertEqual(exported(fade), "configuration.scrollEdgeFade = .standard")
        XCTAssertEqual(
            Exporter.effectLines(rimGlow: .init(), scrollEdgeFade: fade).first,
            "// Scroll views opt in with .nookScrollEdgeFade(axes:)."
        )

        fade.top = false
        fade.bottom = false
        XCTAssertEqual(exported(fade), "configuration.scrollEdgeFade = NookScrollEdgeFade(edges: .horizontal)")

        fade.leading = false
        fade.length = 28
        XCTAssertEqual(
            exported(fade),
            "configuration.scrollEdgeFade = NookScrollEdgeFade(edges: .trailing, length: 28)"
        )

        fade.top = true
        XCTAssertEqual(
            exported(fade),
            "configuration.scrollEdgeFade = NookScrollEdgeFade(edges: [.top, .trailing], length: 28)"
        )

        fade.trailing = false
        fade.top = false
        XCTAssertEqual(exported(fade), "configuration.scrollEdgeFade = NookScrollEdgeFade(edges: [], length: 28)")

        fade = PlaygroundSettings.ScrollEdgeFade()
        fade.isEnabled = true
        fade.length = 40
        XCTAssertEqual(exported(fade), "configuration.scrollEdgeFade = NookScrollEdgeFade(length: 40)")
    }

    func testHoverBehaviorExportsTheSmallestOptionSetLiteral() {
        var behavior = PlaygroundSettings.Behavior()
        XCTAssertEqual(Exporter.behaviorLines(behavior), [])
        behavior.hoverHaptics = true
        XCTAssertEqual(
            Exporter.behaviorLines(behavior),
            ["configuration.chromeBehavior.hoverBehavior = .hapticFeedback"]
        )
        behavior.hoverKeepsVisible = true
        XCTAssertEqual(Exporter.behaviorLines(behavior), ["configuration.chromeBehavior.hoverBehavior = .all"])
        behavior.hoverHaptics = false
        XCTAssertEqual(Exporter.behaviorLines(behavior), ["configuration.chromeBehavior.hoverBehavior = .keepVisible"])
    }

    func testGlassShadingExportsOnlyWhenChanged() {
        var behavior = PlaygroundSettings.Behavior()
        behavior.glassShading = .notchFade
        XCTAssertEqual(Exporter.behaviorLines(behavior), ["configuration.chromeBehavior.glassShading = .notchFade"])
        XCTAssertEqual(behavior.glassShading.nookShading, .notchFade)
        XCTAssertEqual(PlaygroundSettings().chromeBehavior.glassShading, .even)
    }

    // MARK: - Literals

    func testStringLiteralsEscapeWhatALiteralCannotHold() {
        XCTAssertEqual(Exporter.stringLiteral("plain"), #""plain""#)
        XCTAssertEqual(Exporter.stringLiteral(#"say "hi""#), #""say \"hi\"""#)
        XCTAssertEqual(Exporter.stringLiteral(#"C:\dir \(name)"#), #""C:\\dir \\(name)""#)
        XCTAssertEqual(Exporter.stringLiteral("a\nb\tc\rd\0"), #""a\nb\tc\rd\0""#)
        XCTAssertEqual(Exporter.stringLiteral("zero\u{200B}width\u{7}"), #""zero\u{200B}width\u{7}""#)
        XCTAssertEqual(Exporter.stringLiteral("line\u{2028}break"), #""line\u{2028}break""#)
        XCTAssertEqual(Exporter.stringLiteral("caf\u{E9} \u{1F600}"), "\"caf\u{E9} \u{1F600}\"")
    }

    func testNumbersRoundToThreeDecimalsWithoutTrailingZeros() {
        XCTAssertEqual(Exporter.number(8), "8")
        XCTAssertEqual(Exporter.number(0.5), "0.5")
        XCTAssertEqual(Exporter.number(10.25), "10.25")
        XCTAssertEqual(Exporter.number(1.0 / 3), "0.333")
        XCTAssertEqual(Exporter.number(2.0 / 3), "0.667")
        XCTAssertEqual(Exporter.number(0.99999), "1")
        XCTAssertEqual(Exporter.number(-0.0001), "0")
        XCTAssertEqual(Exporter.number(-2.5), "-2.5")
        XCTAssertEqual(Exporter.number(1520), "1520")
    }

    func testColorLiteralsOmitFullOpacity() {
        XCTAssertEqual(Exporter.literal(PlaygroundColor(red: 1, green: 0, blue: 0)), "Color(red: 1, green: 0, blue: 0)")
        XCTAssertEqual(
            Exporter.literal(PlaygroundColor(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.4)),
            "Color(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.4)"
        )
    }
}
