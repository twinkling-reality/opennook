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
        reduceTransparency: Bool = false,
        state: NookState = .expanded
    ) -> NookBackdrop {
        var prefs = preferences(palette: palette, style: style)
        prefs.backdropStrength = strength
        return NookBackdropMapping.notchBackdrop(
            preferences: prefs,
            effectiveColorScheme: .dark,
            reduceTransparency: reduceTransparency,
            glassShading: .notchFade,
            state: state
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

    /// Collapsed, the fade has nowhere to run: the panel is the notch's own height and mostly
    /// behind the camera, so all a gradient could shade is the two small wings either side. The
    /// chrome goes flat notch color instead - the look the fade was after in the first place.
    func testNotchFadeGoesSolidWhileCollapsed() {
        XCTAssertEqual(notchFade(state: .compact), .solid(.black))
        XCTAssertEqual(notchFade(palette: .light, state: .compact), .solid(.white))
        XCTAssertNotEqual(notchFade(state: .compact), notchFade(state: .expanded))
    }

    /// Glass strength scales the fade, not the collapsed chrome: the notch is the notch at any
    /// strength, so the collapsed color is flat and opaque whatever the slider says.
    func testCollapsedNotchFadeIgnoresGlassStrength() {
        XCTAssertEqual(notchFade(strength: 0.15, state: .compact), .solid(.black))
        XCTAssertEqual(notchFade(strength: 0.5, state: .compact), .solid(.black))
    }

    /// The state is the notch fade's business alone. Every other combination - the default even
    /// glass, and any style under either shading - maps to one backdrop for the whole chrome,
    /// exactly as it did before the mapping could tell the states apart.
    func testStateOnlyMovesTheNotchFade() {
        for shading in NookGlassShading.allCases {
            for style in NookSurfaceStyle.allCases {
                for palette in [NookChromePalette.dark, .light, .followSystem] {
                    for reduceTransparency in [false, true] {
                        func map(_ state: NookState) -> NookBackdrop {
                            NookBackdropMapping.notchBackdrop(
                                preferences: preferences(palette: palette, style: style),
                                effectiveColorScheme: .dark,
                                reduceTransparency: reduceTransparency,
                                glassShading: shading,
                                state: state
                            )
                        }
                        let label = "\(shading) \(style) \(palette) rt:\(reduceTransparency)"
                        let movesWithState =
                            shading == .notchFade && style == .liquidGlass && !reduceTransparency
                        if movesWithState {
                            XCTAssertNotEqual(map(.compact), map(.expanded), label)
                        } else {
                            XCTAssertEqual(map(.compact), map(.expanded), label)
                        }
                        XCTAssertEqual(
                            map(.expanded),
                            NookBackdropMapping.notchBackdrop(
                                preferences: preferences(palette: palette, style: style),
                                effectiveColorScheme: .dark,
                                reduceTransparency: reduceTransparency,
                                glassShading: shading
                            ),
                            "\(label): omitting the state means the expanded chrome"
                        )
                    }
                }
            }
        }
    }

    /// The default shading is frozen: with no `glassShading` at all, the mapping answers exactly
    /// what it always has, in every state.
    func testUnshadedHostsGetTodaysRenderingInEveryState() {
        for style in NookSurfaceStyle.allCases {
            for palette in [NookChromePalette.dark, .light, .followSystem] {
                let prefs = preferences(palette: palette, style: style)
                let today = NookBackdropMapping.notchBackdrop(
                    preferences: prefs,
                    effectiveColorScheme: .dark,
                    reduceTransparency: false
                )
                for state in [NookState.compact, .expanded, .hidden] {
                    XCTAssertEqual(
                        NookBackdropMapping.notchBackdrop(
                            preferences: prefs,
                            effectiveColorScheme: .dark,
                            reduceTransparency: false,
                            glassShading: NookChromeBehavior.default.glassShading,
                            state: state
                        ),
                        today,
                        "\(style) \(palette) \(state)"
                    )
                }
            }
        }
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

    /// The companion override exists to keep a tall fade out of a small pill. Collapsed there is
    /// no fade - the chrome is flat notch color - so companions go back to inheriting it and the
    /// pill beside the chrome matches the chrome.
    func testCollapsedCompanionsInheritTheChrome() {
        func companion(_ state: NookState) -> NookBackdrop? {
            NookBackdropMapping.companionBackdrop(
                preferences: preferences(palette: .dark, style: .liquidGlass),
                effectiveColorScheme: .dark,
                reduceTransparency: false,
                glassShading: .notchFade,
                state: state
            )
        }
        XCTAssertNil(companion(.compact))
        XCTAssertNotNil(companion(.expanded))
    }
}
