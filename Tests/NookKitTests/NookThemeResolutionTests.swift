// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// `NookTheme` resolution. The standard theme must reproduce every value the chrome used
/// before themes existed; the knobs and tokens must move exactly what they say.
final class NookThemeResolutionTests: XCTestCase {
    // MARK: - The standard theme changes nothing

    func testStandardMetricsEqualTheFrameworkDefaults() {
        let metrics = NookTheme.standard.resolvedTokens().metrics
        XCTAssertEqual(metrics, NookChromeMetrics.default)
        for field in NookResolvedTokens.metricFields {
            XCTAssertEqual(
                metrics[keyPath: field.keyPath],
                NookChromeMetrics.default[keyPath: field.keyPath],
                "\(field.id)"
            )
        }
    }

    func testStandardTypographyEqualsTheFrameworkDefaults() {
        let typography = NookTheme.standard.resolvedTokens().typography
        XCTAssertEqual(typography, NookChromeTypography.default)
        for field in NookResolvedTokens.typographyFields {
            XCTAssertEqual(
                typography[keyPath: field.keyPath],
                NookChromeTypography.default[keyPath: field.keyPath],
                "\(field.id)"
            )
        }
    }

    func testStandardMotionEqualsTheFrameworkDefaults() {
        let motion = NookTheme.standard.resolvedTokens().motion
        XCTAssertEqual(motion, NookChromeMotion.default)
        for field in NookResolvedTokens.motionFields {
            XCTAssertEqual(
                motion[keyPath: field.keyPath],
                NookChromeMotion.default[keyPath: field.keyPath],
                "\(field.id)"
            )
        }
    }

    @MainActor
    func testStandardStyleAndTransitionsEqualTheFrameworkDefaults() {
        let tokens = NookTheme.standard.resolvedTokens()
        XCTAssertEqual(tokens.style, NookConfiguration.defaultStyle)
        let transitions = tokens.transitionConfiguration
        let expected = AppCoordinator.defaultTransitions
        XCTAssertEqual(transitions.openingAnimation, expected.openingAnimation)
        XCTAssertEqual(transitions.closingAnimation, expected.closingAnimation)
        XCTAssertEqual(transitions.conversionAnimation, expected.conversionAnimation)
        XCTAssertEqual(transitions.skipIntermediateHides, expected.skipIntermediateHides)
        XCTAssertNil(transitions.animationDuration)
        XCTAssertNil(transitions.layoutGraceDuration)
    }

    func testStandardSurfaceTokensMatchTheSurfaceToday() {
        let tokens = NookTheme.standard.resolvedTokens()
        // NookView's fixed compact radii and its floating radius (the expanded bottom radius).
        XCTAssertEqual(tokens[.compactTopRadius], 6)
        XCTAssertEqual(tokens[.compactBottomRadius], 14)
        XCTAssertEqual(tokens[.floatingExpandedRadius], NookConfiguration.defaultStyle.bottomCornerRadius)
        // No choreography today: content enters and leaves together, on the surface's curve.
        XCTAssertEqual(tokens[.contentEnterDelay], 0)
        XCTAssertEqual(tokens[.headerDelay], 0)
        XCTAssertEqual(tokens[.stagger], 0)
        for id in [NookTransitionID.contentExit, .contentEnter] {
            let transition = tokens.transition(id)
            XCTAssertEqual(transition.opacity, 0)
            XCTAssertEqual(transition.blur, 6)
            XCTAssertEqual(transition.scaleX, 1)
            XCTAssertEqual(transition.scaleY, 0.72)
            XCTAssertEqual(transition.anchor, .top)
            XCTAssertEqual(transition.offset, .zero)
            XCTAssertNil(transition.animation)
        }
        for id in NookSoundID.allEvents {
            XCTAssertNil(tokens.sound(id), "\(id)")
        }
        XCTAssertNil(tokens.shadow(.chrome))
    }

    /// Every field of each chrome group is set by its table exactly once: give each table entry
    /// a distinct value and every field must come out distinct.
    func testTheTablesCoverEveryChromeField() {
        var metrics = NookChromeMetrics.default
        for (index, field) in NookResolvedTokens.metricFields.enumerated() {
            metrics[keyPath: field.keyPath] = CGFloat(1000 + index)
        }
        let metricValues = Mirror(reflecting: metrics).children.compactMap { $0.value as? CGFloat }
        XCTAssertEqual(metricValues.count, NookResolvedTokens.metricFields.count)
        XCTAssertEqual(Set(metricValues).count, metricValues.count)
        XCTAssertTrue(metricValues.allSatisfy { $0 >= 1000 })

        let fonts = NookResolvedTokens.typographyFields
        XCTAssertEqual(Mirror(reflecting: NookChromeTypography.default).children.count, fonts.count)
        XCTAssertEqual(Set(fonts.map(\.keyPath)).count, fonts.count)
        let motion = NookResolvedTokens.motionFields
        XCTAssertEqual(Mirror(reflecting: NookChromeMotion.default).children.count, motion.count)
        XCTAssertEqual(Set(motion.map(\.keyPath)).count, motion.count)

        // The registry defines one token per table entry, in the same order.
        XCTAssertEqual(NookTokenRegistry.metricTokens.map(\.id), NookResolvedTokens.metricFields.map(\.id))
        XCTAssertEqual(NookTokenRegistry.typographyTokens.map(\.id), fonts.map(\.id))
        for field in motion {
            XCTAssertNotNil(NookTokenRegistry.animationsByID[field.id], "\(field.id)")
        }
    }

    func testTokenIDsAreUnique() {
        let ids = NookTokenRegistry.allIDs.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - The standard palette is the framework's palette

    /// The palette exactly as the framework resolved it before themes existed.
    private func legacyPalette(
        preferences: NookAppearancePreferences,
        scheme: ColorScheme,
        reduceTransparency: Bool
    ) -> NookResolvedTheme {
        let isDark: Bool =
            switch preferences.chromePalette {
                case .followSystem: scheme == .dark
                case .dark: true
                case .light: false
            }
        let trueSolid = preferences.surfaceStyle == .solid
        let isSolid = trueSolid || reduceTransparency
        if isDark {
            return NookResolvedTheme(
                primaryLabel: Color.white.opacity(0.95),
                secondaryLabel: Color.white.opacity(0.62),
                tertiaryLabel: Color.white.opacity(0.46),
                quaternaryLabel: Color.white.opacity(0.34),
                subtleFill: Color.white.opacity(isSolid ? (trueSolid ? 0.07 : 0.12) : 0.055),
                subtleStroke: Color.white.opacity(0.14),
                headerInactiveIcon: Color.white.opacity(0.42),
                accent: preferences.accentPreset.color()
            )
        }
        return NookResolvedTheme(
            primaryLabel: Color.black.opacity(0.88),
            secondaryLabel: Color.black.opacity(0.55),
            tertiaryLabel: Color.black.opacity(0.42),
            quaternaryLabel: Color.black.opacity(0.32),
            subtleFill: Color.black.opacity(isSolid ? (trueSolid ? 0.045 : 0.055) : 0.030),
            subtleStroke: Color.black.opacity(0.09),
            headerInactiveIcon: Color.black.opacity(0.38),
            accent: preferences.accentPreset.color()
        )
    }

    func testStandardPaletteEqualsTheFrameworkPaletteEverywhere() {
        for palette in NookChromePalette.allCases {
            for surface in NookSurfaceStyle.allCases {
                for accent in NookAccentPreset.allCases {
                    for scheme in [ColorScheme.dark, .light] {
                        for reduceTransparency in [false, true] {
                            let preferences = NookAppearancePreferences(
                                chromePalette: palette,
                                surfaceStyle: surface,
                                accentPreset: accent
                            )
                            let expected = legacyPalette(
                                preferences: preferences,
                                scheme: scheme,
                                reduceTransparency: reduceTransparency
                            )
                            let resolved = NookResolvedTheme.resolve(
                                preferences: preferences,
                                effectiveColorScheme: scheme,
                                reduceTransparency: reduceTransparency
                            )
                            XCTAssertEqual(
                                resolved,
                                expected,
                                "\(palette) \(surface) \(accent) \(scheme) RT \(reduceTransparency)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testNewColorRolesDefaultToTheColorsTheChromeUses() {
        let theme = NookTheme.standard
        let dark = NookThemeContext(isDark: true)
        let light = NookThemeContext(isDark: false)
        XCTAssertEqual(theme.color(.surface, in: dark), Color.black)
        XCTAssertEqual(theme.color(.surface, in: light), Color.white)
        XCTAssertEqual(theme.color(.hoverWash, in: dark), Color.white)
        XCTAssertEqual(theme.color(.hoverWash, in: light), Color.white)
        XCTAssertEqual(theme.color(.destructive, in: dark), Color.red)
        XCTAssertEqual(theme.color(.warning, in: light), Color.orange)
        XCTAssertEqual(theme.color(.success, in: dark), Color.green)
        XCTAssertEqual(theme.color(.feedbackTint, in: dark), Color(nsColor: .controlAccentColor))
    }

    // MARK: - Knobs

    func testScaleMovesSpacingAndTypeButNotNotchSizes() {
        let tokens = NookTheme(scale: 1.5).resolvedTokens()
        XCTAssertEqual(tokens[.spaceMD], 12)
        XCTAssertEqual(tokens.metrics.edgePadding, 12)  // {space.md}
        XCTAssertEqual(tokens.metrics.bannerContentVerticalPadding, 10.5)  // 7 at scale 1
        XCTAssertEqual(tokens.metrics.topBarHeight, 24)
        XCTAssertEqual(tokens.metrics.compactSlotSize, 24)
        XCTAssertEqual(tokens.metrics.headerIconSize, 24)
        XCTAssertEqual(tokens.metrics.bannerStrokeOpacity, 0.65)
        XCTAssertEqual(tokens.metrics.bannerCornerRadius, 10)  // radii follow the radius knob
        XCTAssertEqual(tokens.typography.bannerMessage, Font.system(size: 15.75, weight: .medium))
        XCTAssertEqual(tokens.typography.headerIcon, Font.system(size: 16.5, weight: .semibold))
        XCTAssertEqual(NookTheme(scale: 9).resolvedTokens()[.spaceMD], 16, "scale is kept within 0.5...2")
    }

    func testRadiusMovesRadiiOnly() {
        let tokens = NookTheme(radius: .factor(2)).resolvedTokens()
        XCTAssertEqual(tokens.metrics.bannerCornerRadius, 20)
        XCTAssertEqual(tokens.metrics.headerIconCornerRadius, 14)
        XCTAssertEqual(tokens.metrics.shortcutKeyCapCornerRadius, 12)
        XCTAssertEqual(tokens.style.bottomCornerRadius, 48)
        XCTAssertEqual(tokens.style.topCornerRadius, 19)
        XCTAssertEqual(tokens[.floatingExpandedRadius], 48)
        XCTAssertEqual(tokens.metrics.edgePadding, 8)
        XCTAssertEqual(NookTheme(radius: .none).resolvedTokens().metrics.bannerCornerRadius, 0)
    }

    func testMotionSchemeMovesSpringsButNotCurves() {
        let calm = NookTheme(motion: .calm).resolvedTokens().motion
        XCTAssertEqual(calm.statusBanner, Animation.spring(response: 0.34, dampingFraction: 1))
        XCTAssertEqual(calm.breadcrumb, Animation.easeOut(duration: 0.18))
    }

    func testFontDesignAndWidthKnobs() {
        let theme = NookTheme(fontDesign: .rounded, fontWidth: .condensed)
        let palette = NookResolvedTheme.resolve(
            theme: theme,
            preferences: .default,
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        XCTAssertEqual(palette.fontDesign, .rounded)
        XCTAssertEqual(theme.fontWidth.width, .condensed)
    }

    // MARK: - Tokens

    func testASemanticOverrideReachesEveryFieldThatDefaultsFromIt() {
        var theme = NookTheme()
        theme.tokens[.spaceMD] = 9
        let metrics = theme.resolvedTokens().metrics
        XCTAssertEqual(metrics.edgePadding, 9)
        XCTAssertEqual(metrics.bannerRowSpacing, 9)
        XCTAssertEqual(metrics.shelfChipPadding, 9)
        XCTAssertEqual(metrics.trailingClusterSpacing, 4)
    }

    func testComponentOverridesTakeNumbersAndReferences() {
        var theme = NookTheme(scale: 2)
        theme.tokens[.bannerCornerRadius] = .token(.radiusLG)
        theme.tokens[.bannerRowSpacing] = 3  // written at scale 1
        theme.tokens[.bannerStrokeOpacity] = .reference(.headerIconHoverLabelOpacity, times: 0.5)
        let metrics = theme.resolvedTokens().metrics
        XCTAssertEqual(metrics.bannerCornerRadius, 12)
        XCTAssertEqual(metrics.bannerRowSpacing, 6)
        XCTAssertEqual(metrics.bannerStrokeOpacity, 0.46)
    }

    func testFontOverridesStartFromTheirRole() {
        var theme = NookTheme()
        theme.tokens[.typeBody] = NookFontSpec(size: 12, weight: .regular)
        theme.tokens[.bannerMessage] = NookFontSpec(role: .typeBody, weight: .semibold, design: .rounded)
        let typography = theme.resolvedTokens().typography
        XCTAssertEqual(typography.topBarLabel, Font.system(size: 12, weight: .regular))
        XCTAssertEqual(typography.placeholderBody, Font.system(size: 12, weight: .regular))
        XCTAssertEqual(typography.bannerMessage, Font.system(size: 12, weight: .semibold, design: .rounded))
        XCTAssertEqual(typography.headerIcon, Font.system(size: 11, weight: .semibold))
    }

    /// The motion fields routed through `NookChromeMotion` later have tokens of their own,
    /// with today's curves as the standard values, and a theme can set them.
    func testRoutedMotionFieldsAreTokenized() {
        XCTAssertEqual(NookAnimationID.settingsDisclosure.rawValue, "motion.settingsDisclosure")
        XCTAssertEqual(NookAnimationID.moduleSwitch.rawValue, "motion.moduleSwitch")
        XCTAssertEqual(NookAnimationID.activityCard.rawValue, "motion.activityCard")

        let standard = NookTheme.standard.resolvedTokens().motion
        XCTAssertEqual(standard.settingsDisclosure, Animation.spring(response: 0.30, dampingFraction: 0.86))
        XCTAssertEqual(standard.moduleSwitch, Animation.easeInOut(duration: 0.22))
        XCTAssertEqual(standard.activityCard, Animation.spring(response: 0.36, dampingFraction: 0.86))

        var theme = NookTheme()
        theme.tokens[.settingsDisclosure] = .reference(.springSnappy)
        theme.tokens[.moduleSwitch] = .curve(.linear, duration: 0.5)
        theme.tokens[.activityCard] = .spring(response: 0.2, dampingFraction: 0.7)
        let motion = theme.resolvedTokens().motion
        XCTAssertEqual(motion.settingsDisclosure, Animation.spring(response: 0.26, dampingFraction: 0.82))
        XCTAssertEqual(motion.moduleSwitch, Animation.linear(duration: 0.5))
        XCTAssertEqual(motion.activityCard, Animation.spring(response: 0.2, dampingFraction: 0.7))

        // The calm scheme moves the springs and leaves the module switch's curve alone.
        let calm = NookTheme(motion: .calm).resolvedTokens().motion
        XCTAssertEqual(calm.settingsDisclosure, Animation.spring(response: 0.30, dampingFraction: 1))
        XCTAssertEqual(calm.moduleSwitch, Animation.easeInOut(duration: 0.22))
    }

    func testAnimationOverridesFollowReferences() {
        var theme = NookTheme()
        theme.tokens[.springDefault] = .spring(response: 0.3, dampingFraction: 0.9)
        theme.tokens[.viewModeChange] = .reference(.springDefault)
        let motion = theme.resolvedTokens().motion
        XCTAssertEqual(motion.statusBanner, Animation.spring(response: 0.3, dampingFraction: 0.9))
        XCTAssertEqual(motion.viewModeChange, Animation.spring(response: 0.3, dampingFraction: 0.9))
    }

    func testChoreographyTokensExpressAStaggeredEntrance() {
        var theme = NookTheme()
        theme.tokens[.contentExit] = NookContentTransitionSpec(
            blur: 8,
            scaleX: 0.97,
            scaleY: 0.97,
            animation: .curve(.easeOut, duration: 0.16)
        )
        theme.tokens[.contentEnter] = NookContentTransitionSpec(
            blur: 8,
            scaleX: 0.97,
            scaleY: 0.97,
            animation: .curve(.easeOut, duration: 0.3)
        )
        theme.tokens[.contentEnterDelay] = 0.16
        theme.tokens[.headerDelay] = 0.3
        theme.tokens[.stagger] = 0.035
        let tokens = theme.resolvedTokens()
        XCTAssertEqual(tokens.transition(.contentExit).animation, Animation.easeOut(duration: 0.16))
        XCTAssertEqual(tokens.transition(.contentEnter).scaleX, 0.97)
        XCTAssertEqual(tokens[.contentEnterDelay], 0.16)
        XCTAssertEqual(tokens[.headerDelay], 0.3)
        XCTAssertEqual(tokens[.stagger], 0.035)
        theme.tokens[.stagger] = -1
        XCTAssertEqual(theme.resolvedTokens()[.stagger], 0, "durations are never negative")
    }

    func testSoundsTakeTheThemeVolume() {
        var theme = NookTheme(soundVolume: 0.5)
        theme.tokens[.open] = .system("Pop", volume: 0.8)
        theme.tokens[.finish] = .system("Glass")
        let tokens = theme.resolvedTokens()
        XCTAssertEqual(tokens.sound(.open), .system("Pop", volume: 0.4))
        XCTAssertEqual(tokens.sound(.finish), .system("Glass", volume: 0.5))
        XCTAssertNil(tokens.sound(.close))
    }

    func testReferenceLoopsFallBackToDefaults() {
        var theme = NookTheme()
        theme.tokens[.spaceMD] = .token(.spaceLG)
        theme.tokens[.spaceLG] = .token(.spaceMD)
        theme.tokens[.labelPrimary] = "{color.label.secondary}"
        theme.tokens[.labelSecondary] = "{color.label.primary}"
        theme.tokens[.springDefault] = .reference(.statusBanner)
        let resolver = NookThemeResolver(theme: theme)
        let tokens = resolver.resolveAll()
        XCTAssertEqual(tokens[.spaceLG], 8, "space.lg -> space.md -> loop, so space.md falls back to 8")
        XCTAssertEqual(tokens[.spaceMD], 8)
        XCTAssertEqual(tokens.motion.statusBanner, Animation.spring(response: 0.34, dampingFraction: 0.86))
        _ = resolver.color(.labelPrimary, in: NookThemeContext(isDark: true))
        XCTAssertTrue(resolver.issues.contains { $0.kind == .cycle })
    }

    func testUnknownReferencesFallBack() {
        var theme = NookTheme()
        theme.tokens[.bannerCornerRadius] = .token("radius.huge")
        theme.tokens[.labelPrimary] = "{color.nope}"
        let resolver = NookThemeResolver(theme: theme)
        XCTAssertEqual(resolver.resolveAll().metrics.bannerCornerRadius, 0)
        XCTAssertEqual(resolver.color(.labelPrimary, in: NookThemeContext(isDark: true)), Color.clear)
        XCTAssertTrue(resolver.issues.contains { $0.kind == .unknownReference("radius.huge") })
        XCTAssertTrue(resolver.issues.contains { $0.kind == .unknownReference("color.nope") })
    }

    // MARK: - Colors, accent, and pins

    func testColorReferencesAndThePlaceholderAccent() {
        var theme = NookTheme(accent: "#3399FF")
        theme.tokens[.strokeSubtle] = .reference(.accent, opacity: 0.5)
        theme.tokens[.labelQuaternary] = .hierarchical(.secondary)
        let context = NookThemeContext(isDark: true)
        let accent = NookRGBA(hex: "#3399FF")!.color
        XCTAssertEqual(theme.color(.accent, in: context), accent)
        XCTAssertEqual(theme.color(.strokeSubtle, in: context), accent.opacity(0.5))
        XCTAssertEqual(theme.color(.labelQuaternary, in: context), Color.white.opacity(0.62))
    }

    func testThePersonsAccentWinsUnlessTheThemeLocksIt() {
        let open = NookTheme(accent: "#3399FF")
        let teal = NookThemeContext(isDark: true, accentPreset: .teal)
        XCTAssertEqual(open.color(.accent, in: teal), NookAccentPreset.teal.color())
        XCTAssertEqual(
            open.color(.accent, in: NookThemeContext(isDark: true, accentPreset: .system)),
            NookRGBA(hex: "#3399FF")!.color,
            "the person's System choice means the theme's accent"
        )
        let locked = NookTheme(accent: "#3399FF", allowsUserAccent: false)
        let lockedContext = locked.context(
            preferences: NookAppearancePreferences(accentPreset: .teal),
            systemColorScheme: .dark,
            reduceTransparency: false
        )
        XCTAssertEqual(locked.color(.accent, in: lockedContext), NookRGBA(hex: "#3399FF")!.color)
    }

    func testPinsReplaceThePersonsChoicesWithoutTouchingThem() {
        let theme = NookTheme(palette: .light, surface: .liquidGlass, backdropStrength: 0.05)
        let preferences = NookAppearancePreferences(
            chromePalette: .dark,
            surfaceStyle: .solid,
            accentPreset: .rose,
            backdropStrength: 0.8
        )
        let effective = theme.effectivePreferences(preferences)
        XCTAssertEqual(effective.chromePalette, .light)
        XCTAssertEqual(effective.surfaceStyle, .liquidGlass)
        XCTAssertEqual(effective.backdropStrength, 0.15, "a pinned strength is kept within 0.15...1")
        XCTAssertEqual(effective.accentPreset, .rose)
        XCTAssertEqual(NookTheme.standard.effectivePreferences(preferences), preferences)

        let palette = NookResolvedTheme.resolve(
            theme: theme,
            preferences: preferences,
            effectiveColorScheme: .dark,
            reduceTransparency: false
        )
        XCTAssertEqual(palette.primaryLabel, Color.black.opacity(0.88), "pinned light")
        XCTAssertEqual(palette.subtleFill, Color.black.opacity(0.030), "pinned glass, not the person's solid")
    }

    // MARK: - Coding

    func testTheStandardThemeEncodesAsAnEmptyObject() throws {
        let data = try JSONEncoder().encode(NookTheme.standard)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")
        XCTAssertEqual(try JSONDecoder().decode(NookTheme.self, from: data), .standard)
    }

    func testAThemeRoundTripsWithTokensAndComponentsInTheirSections() throws {
        var theme = NookTheme(
            name: "Graphite",
            accent: "#3399FF",
            allowsUserAccent: false,
            palette: .dark,
            surface: .liquidGlass,
            backdropStrength: 0.8,
            radius: .large,
            scale: 1.05,
            fontDesign: .rounded,
            fontWidth: .condensed,
            motion: .calm,
            soundVolume: 0.5,
            allowsUserSoundToggle: false
        )
        theme.tokens[.labelSecondary] = .adaptive(
            NookAdaptiveColor(dark: .white(opacity: 0.66), light: .black(opacity: 0.55))
        )
        theme.tokens[.spaceMD] = 9
        theme.tokens[.springDefault] = .spring(response: 0.3, dampingFraction: 0.9)
        theme.tokens[.bannerCornerRadius] = .token(.radiusLG)
        theme.tokens[.bannerMessage] = NookFontSpec(size: .token(.typeSizeMD), weight: .semibold)
        theme.tokens[.contentEnter] = NookContentTransitionSpec(blur: 8, scaleX: 0.97, scaleY: 0.97)
        theme.tokens[.open] = .system("Pop")
        theme.tokens[.chrome] = NookShadowSpec()
        theme.backdrops.liquidGlass = .liquidGlass(.init(tint: "accent"))
        theme.backdrops.glassShading = .notchFade

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(theme)
        XCTAssertEqual(try JSONDecoder().decode(NookTheme.self, from: data), theme)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tokens = try XCTUnwrap(object["tokens"] as? [String: Any])
        let components = try XCTUnwrap(object["components"] as? [String: Any])
        XCTAssertEqual(
            Set(tokens.keys),
            [
                "color.label.secondary", "space.md", "spring.default", "motion.content.enter", "sound.open",
                "shadow.chrome",
            ]
        )
        XCTAssertEqual(Set(components.keys), ["banner.cornerRadius", "banner.message.font"])
        XCTAssertEqual(object["radius"] as? String, "large")
    }

    func testDecodingIgnoresUnknownMembersAndIdsAndReadsEitherSection() throws {
        let json = #"""
            {
              "future": true,
              "scale": 1.2,
              "tokens": { "space.md": 9, "space.huge": 99, "banner.cornerRadius": 4 },
              "components": { "sound.open": null, "motion.statusBanner": "{spring.snappy}" }
            }
            """#
        let theme = try JSONDecoder().decode(NookTheme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.scale, 1.2)
        XCTAssertEqual(theme.tokens[.spaceMD], 9)
        XCTAssertEqual(theme.tokens[.bannerCornerRadius], 4)
        XCTAssertEqual(theme.tokens[.statusBanner], .reference(.springSnappy))
        XCTAssertNil(theme.tokens[.open])
        XCTAssertEqual(theme.tokens.count, 3)
    }

    func testAValueOfTheWrongTypeStillThrows() {
        let json = #"{"tokens": {"space.md": "wide"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(NookTheme.self, from: Data(json.utf8)))
    }

    func testRenamesAreFollowedAndRemovalsSkipped() {
        var renames: [String: String?] = ["space.medium": "space.mid", "space.mid": "space.md"]
        renames["space.gone"] = .some(nil)
        XCTAssertEqual(NookTokenRenames.currentID(for: "space.medium", renames: renames), "space.md")
        XCTAssertNil(NookTokenRenames.currentID(for: "space.gone", renames: renames))
        XCTAssertEqual(NookTokenRenames.currentID(for: "space.md", renames: renames), "space.md")
        XCTAssertNil(
            NookTokenRenames.currentID(for: "a", renames: ["a": "b", "b": "a"]),
            "a rename loop reads as removed"
        )
    }
}
