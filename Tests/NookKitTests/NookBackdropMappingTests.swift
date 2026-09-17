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

/// Pins ``NookBackdropMapping`` to its rendering contract. The mapping is the only
/// producer of ``NookBackdrop`` in the framework; if these change, downstream renders
/// change too - so they're worth pinning explicitly.
final class NookBackdropMappingTests: XCTestCase {
    private func preferences(
        palette: NookChromePalette,
        style: NookSurfaceStyle
    ) -> NookAppearancePreferences {
        NookAppearancePreferences(chromePalette: palette, surfaceStyle: style)
    }

    func testSolidStyleMapsToSolidBlackInDark() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .dark, style: .solid),
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        XCTAssertEqual(backdrop, .solid(.black))
    }

    func testSolidStyleMapsToSolidWhiteInLight() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .light, style: .solid),
            effectiveColorScheme: .light,
            reduceTransparency: false
        )
        XCTAssertEqual(backdrop, .solid(.white))
    }

    /// Reduce Transparency overrides the translucent style - the chrome must avoid
    /// `NSVisualEffectView` entirely.
    func testReduceTransparencyForcesSolidEvenWhenTranslucent() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .dark, style: .translucent),
            effectiveColorScheme: .dark,
            reduceTransparency: true
        )
        XCTAssertEqual(backdrop, .solid(.black), "RT forces a solid fill in any style")
    }

    func testFollowSystemPaletteResolvesAgainstEffectiveScheme() {
        let dark = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .followSystem, style: .solid),
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        XCTAssertEqual(dark, .solid(.black))

        let light = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .followSystem, style: .solid),
            effectiveColorScheme: .light,
            reduceTransparency: false
        )
        XCTAssertEqual(light, .solid(.white))
    }

    func testTranslucentDarkUsesSidebarVibrancyWithDarkDarken() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .dark, style: .translucent),
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        let expected = NookBackdrop.vibrancy(
            .init(
                material: .sidebar,
                blendingMode: .behindWindow,
                darkenOpacity: 0.52
            )
        )
        XCTAssertEqual(backdrop, expected)
    }

    func testTranslucentLightUsesSidebarVibrancyWithLightDarken() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .light, style: .translucent),
            effectiveColorScheme: .light,
            reduceTransparency: false
        )
        let expected = NookBackdrop.vibrancy(
            .init(
                material: .sidebar,
                blendingMode: .behindWindow,
                darkenOpacity: 0.10
            )
        )
        XCTAssertEqual(backdrop, expected)
    }

    func testBackdropStrengthScalesTranslucentDarken() {
        var prefs = preferences(palette: .dark, style: .translucent)
        prefs.backdropStrength = 0.5
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: prefs,
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        let expected = NookBackdrop.vibrancy(
            .init(
                material: .sidebar,
                blendingMode: .behindWindow,
                darkenOpacity: 0.52 * 0.5
            )
        )
        XCTAssertEqual(backdrop, expected)
    }

    /// The framework default - what every host gets before any mapping runs - must be
    /// the solid-black fill so cold-launch rendering matches the historical chrome.
    func testDefaultBackdropIsSolidBlack() {
        XCTAssertEqual(NookBackdrop.solidBlack, .solid(.black))
    }

    // MARK: - Liquid Glass

    /// Dark glass is anchored to the theme with a black tint inside the material plus
    /// the black legibility shading - Apple's adaptive glass must not flip light over a
    /// bright wallpaper while the chrome text stays dark-theme white.
    func testLiquidGlassDarkAnchorsWithBlackTintAndDarken() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .dark, style: .liquidGlass),
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        let expected = NookBackdrop.liquidGlass(
            .init(
                tint: .black,
                tintStrength: 0.30,
                highlightStrength: 0.6,
                shading: .init(
                    gradient: Gradient(colors: [
                        .black.opacity(0.22),
                        .black.opacity(0.22 * 0.4),
                    ])
                )
            )
        )
        XCTAssertEqual(backdrop, expected)
    }

    /// Light glass mirrors the dark anchoring with white: a white tint plus a white
    /// scrim keep the surface light over a dark wallpaper, so light-theme (dark) text
    /// stays legible no matter what sits behind the notch.
    func testLiquidGlassLightAnchorsWithWhiteTintAndScrim() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .light, style: .liquidGlass),
            effectiveColorScheme: .light,
            reduceTransparency: false
        )
        let expected = NookBackdrop.liquidGlass(
            .init(
                tint: .white,
                tintStrength: 0.42,
                highlightStrength: 0.6,
                shading: .init(
                    gradient: Gradient(colors: [
                        .white.opacity(0.38),
                        .white.opacity(0.38 * 0.4),
                    ])
                )
            )
        )
        XCTAssertEqual(backdrop, expected)
    }

    /// Reduce Transparency collapses Liquid Glass to a solid fill too - the glass
    /// material must not render when the user has opted out of translucency.
    func testReduceTransparencyForcesSolidEvenWhenLiquidGlass() {
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: preferences(palette: .dark, style: .liquidGlass),
            effectiveColorScheme: .dark,
            reduceTransparency: true
        )
        XCTAssertEqual(backdrop, .solid(.black), "RT forces a solid fill in any style")
    }

    func testBackdropStrengthScalesLiquidGlassDarken() {
        var prefs = preferences(palette: .dark, style: .liquidGlass)
        prefs.backdropStrength = 0.5
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: prefs,
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        let expected = NookBackdrop.liquidGlass(
            .init(
                tint: .black,
                tintStrength: 0.30 * 0.5,
                highlightStrength: 0.6,
                shading: .init(
                    gradient: Gradient(colors: [
                        .black.opacity(0.22 * 0.5),
                        .black.opacity(0.22 * 0.5 * 0.4),
                    ])
                )
            )
        )
        XCTAssertEqual(backdrop, expected)
    }

    func testBackdropStrengthScalesLiquidGlassLightAnchor() {
        var prefs = preferences(palette: .light, style: .liquidGlass)
        prefs.backdropStrength = 0.5
        let backdrop = NookBackdropMapping.notchBackdrop(
            preferences: prefs,
            effectiveColorScheme: .light,
            reduceTransparency: false
        )
        let expected = NookBackdrop.liquidGlass(
            .init(
                tint: .white,
                tintStrength: 0.42 * 0.5,
                highlightStrength: 0.6,
                shading: .init(
                    gradient: Gradient(colors: [
                        .white.opacity(0.38 * 0.5),
                        .white.opacity(0.38 * 0.5 * 0.4),
                    ])
                )
            )
        )
        XCTAssertEqual(backdrop, expected)
    }

    // MARK: - Notch fade

    private func notchFade(
        palette: NookChromePalette = .dark,
        style: NookSurfaceStyle = .liquidGlass,
        strength: Double = 1,
        reduceTransparency: Bool = false
    ) -> NookBackdrop {
        var prefs = preferences(palette: palette, style: style)
        prefs.backdropStrength = strength
        return NookBackdropMapping.notchBackdrop(
            preferences: prefs,
            effectiveColorScheme: .dark,
            reduceTransparency: reduceTransparency,
            glassShading: .notchFade
        )
    }

    /// The notch fade is clear glass, black at the notch and clear at the bottom.
    func testNotchFadeRunsFromTheNotchColorToClear() {
        XCTAssertEqual(
            notchFade(),
            .liquidGlass(.init(tint: nil, highlightStrength: 0.6, shading: .notchFade(.black, strength: 1)))
        )
        let stops = NookBackdrop.LiquidGlass.Shading.notchFade(.black, strength: 1).gradient.stops
        XCTAssertEqual(stops.first?.color, .black)
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.last?.color, .black.opacity(0))
        XCTAssertEqual(stops.last?.location, 1)
    }

    /// Glass strength scales the fade below the top edge, which always matches the notch.
    func testNotchFadeFollowsGlassStrength() {
        let shading = NookBackdrop.LiquidGlass.Shading.notchFade(.black, strength: 0.5)
        XCTAssertEqual(
            shading.gradient.stops.map(\.color),
            [.black, .black.opacity(0.45), .black.opacity(0.2), .black.opacity(0)]
        )
        XCTAssertEqual(
            notchFade(strength: 0.5),
            .liquidGlass(.init(tint: nil, highlightStrength: 0.6, shading: .notchFade(.black, strength: 0.5)))
        )
    }

    /// Light chrome fades from white, so dark text stays legible at the top.
    func testNotchFadeIsWhiteForLightChrome() {
        XCTAssertEqual(
            notchFade(palette: .light),
            .liquidGlass(.init(tint: nil, highlightStrength: 0.6, shading: .notchFade(.white, strength: 1)))
        )
    }

    /// The shading changes Liquid Glass only: Solid, Translucent, and Reduce Transparency are
    /// the same whatever it is.
    func testNotchFadeLeavesOtherStylesAlone() {
        for style in [NookSurfaceStyle.solid, .translucent] {
            let even = NookBackdropMapping.notchBackdrop(
                preferences: preferences(palette: .dark, style: style),
                effectiveColorScheme: .dark,
                reduceTransparency: false
            )
            XCTAssertEqual(notchFade(style: style), even)
        }
        XCTAssertEqual(notchFade(reduceTransparency: true), .solid(.black))
    }

    /// Companions get their own backdrop only under the notch fade: the same clear glass with an
    /// even tint, never the tall gradient.
    func testCompanionsGetAnEvenGlassOnlyUnderTheNotchFade() {
        func companion(_ shading: NookGlassShading, style: NookSurfaceStyle = .liquidGlass, rt: Bool = false)
            -> NookBackdrop?
        {
            NookBackdropMapping.companionBackdrop(
                preferences: preferences(palette: .dark, style: style),
                effectiveColorScheme: .dark,
                reduceTransparency: rt,
                glassShading: shading
            )
        }
        XCTAssertNil(companion(.even))
        XCTAssertNil(companion(.notchFade, style: .solid))
        XCTAssertNil(companion(.notchFade, style: .translucent))
        XCTAssertNil(companion(.notchFade, rt: true))
        XCTAssertEqual(
            companion(.notchFade),
            .liquidGlass(.init(tint: nil, highlightStrength: 0.6, shading: .uniform(.black.opacity(0.3))))
        )
    }
}
