// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
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
        XCTAssertEqual(
            Exporter.companionLines([PlaygroundSettings.Companion(id: "chip", kind: .chip)]),
            [
                #"configuration.addCompanion(id: "chip") {"#,
                "    StatusChip()  // your view: a short label",
                "}",
            ]
        )
        XCTAssertEqual(Exporter.companionLines([]), [])
    }

    func testLongCompanionCallsBreakOneArgumentPerLine() {
        var button = PlaygroundSettings.Companion(id: "timer", kind: .button, accessibilityLabel: "Sleep timer")
        button.anchor = .leading
        button.alignment = .start
        button.spacing = 10
        button.visibility = .compact
        button.outline = .circle
        button.backdrop = .glass
        button.backdropColor = PlaygroundColor(red: 1, green: 1, blue: 1, opacity: 0.2)
        XCTAssertEqual(
            Exporter.companionLines([button]),
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
                "    RoundButton()  // your view: a single icon button",
                "}",
            ]
        )
    }

    func testCompanionAnchorShapeAndBackdropLiterals() {
        var companion = PlaygroundSettings.Companion(id: "x", kind: .actions)
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
