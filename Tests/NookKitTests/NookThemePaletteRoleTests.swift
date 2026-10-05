// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// The palette roles the chrome's status and hover colors now come from, and the per-part
/// chrome colors. Every default is the color the chrome drew before, so nothing changes until
/// a theme or a host palette says so.
final class NookThemePaletteRoleTests: XCTestCase {
    private func palette(_ theme: NookTheme = .standard, isDark: Bool = true) -> NookResolvedTheme {
        NookResolvedTheme.resolve(
            theme: theme,
            preferences: NookAppearancePreferences(chromePalette: isDark ? .dark : .light),
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
    }

    func testAHandBuiltPaletteGetsTheColorsTheChromeUsedBefore() {
        let theme = NookResolvedTheme(
            primaryLabel: .white,
            secondaryLabel: .white,
            tertiaryLabel: .white,
            quaternaryLabel: .white,
            subtleFill: .white,
            subtleStroke: .white,
            headerInactiveIcon: .white
        )
        XCTAssertEqual(theme.hoverWash, Color.white)
        XCTAssertEqual(theme.destructive, Color.red)
        XCTAssertEqual(theme.warning, Color.orange)
        XCTAssertEqual(theme.success, Color.green)
    }

    func testTheStandardPaletteHasTheSameRolesInBothAppearances() {
        for isDark in [true, false] {
            let resolved = palette(isDark: isDark)
            XCTAssertEqual(resolved.hoverWash, Color.white)
            XCTAssertEqual(resolved.destructive, Color.red)
            XCTAssertEqual(resolved.warning, Color.orange)
            XCTAssertEqual(resolved.success, Color.green)
        }
    }

    func testAThemeRecolorsTheRoles() {
        var theme = NookTheme()
        theme.tokens[.destructive] = "#FF453A"
        theme.tokens[.hoverWash] = .adaptive(NookAdaptiveColor(dark: .white(opacity: 1), light: .black(opacity: 1)))
        XCTAssertEqual(palette(theme).destructive, NookRGBA(hex: "#FF453A")!.color)
        XCTAssertEqual(palette(theme, isDark: true).hoverWash, Color.white)
        XCTAssertEqual(palette(theme, isDark: false).hoverWash, Color.black)
    }

    func testChromeColorsDefaultToThePalette() {
        let colors = NookChromeColors.default
        for severity in NookStatusSeverity.allCases {
            XCTAssertNil(colors.bannerSeverity(severity))
        }
        XCTAssertEqual(NookTheme.standard.chromeColors(in: NookThemeContext(isDark: true)), .default)
    }

    func testAThemeColorsTheBannerBySeverity() {
        var theme = NookTheme()
        theme.tokens[.bannerSeverityError] = "{color.destructive}"
        theme.tokens[.bannerSeverityWarning] = "{color.warning}"
        let colors = theme.chromeColors(in: NookThemeContext(isDark: true))
        XCTAssertEqual(colors.bannerSeverity(.error), Color.red)
        XCTAssertEqual(colors.bannerSeverity(.warning), Color.orange)
        XCTAssertNil(colors.bannerSeverity(.info))
        XCTAssertNil(colors.bannerSeverity(.success))
    }

    func testTheBannerSeverityTokensDefaultToTheAccent() {
        let context = NookThemeContext(isDark: true, accentPreset: .violet)
        let theme = NookTheme.standard
        XCTAssertEqual(theme.color(.bannerSeverityError, in: context), NookAccentPreset.violet.color())
        XCTAssertEqual(theme.color(.bannerSeveritySuccess, in: context), theme.color(.accent, in: context))
    }

    @MainActor
    func testTheGlyphButtonWashFollowsThePaletteUnlessSet() {
        XCTAssertNil(NookGlyphButtonStyle().washColor)
        XCTAssertEqual(NookGlyphButtonStyle.nookGlyph(washColor: .black).washColor, .black)
    }
}
