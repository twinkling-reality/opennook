// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import SwiftUI

/// Which tier a token belongs to. A theme file lists semantic tokens under `tokens` and
/// component tokens (the chrome's own fields) under `components`.
enum NookTokenTier: Sendable {
    /// A shared value many parts of the chrome default from: a color role, a spacing step.
    case semantic
    /// One part of the chrome: a field of `NookChromeMetrics`, `NookChromeTypography`, or
    /// `NookChromeMotion`.
    case component
}

/// Which theme knob multiplies a number written for a token.
enum NookTokenScaling: Sendable {
    case none
    /// The theme's `scale`.
    case spacing
    /// The theme's `scale`.
    case type
    /// The theme's `radius`.
    case radius
}

/// The range a numeric token is kept in.
enum NookNumberRange: Sendable {
    case length
    case opacity
    case tracking
    case duration

    var bounds: ClosedRange<Double> {
        switch self {
            case .length: 0...10_000
            case .opacity: 0...1
            case .tracking: -100...100
            case .duration: 0...60
        }
    }
}

/// The kind of value a token id names.
enum NookTokenKind: Sendable {
    case color
    case dimension
    case font
    case animation
    case transition
    case sound
    case shadow
}

struct NookDimensionToken: Sendable {
    let id: NookDimensionID
    let tier: NookTokenTier
    let scaling: NookTokenScaling
    let value: NookDimension
    let range: NookNumberRange

    init(
        _ id: NookDimensionID,
        _ tier: NookTokenTier,
        _ scaling: NookTokenScaling,
        _ value: NookDimension,
        _ range: NookNumberRange
    ) {
        self.id = id
        self.tier = tier
        self.scaling = scaling
        self.value = value
        self.range = range
    }
}

struct NookColorToken: Sendable {
    let id: NookColorID
    let tier: NookTokenTier
    let value: NookColorValue

    init(_ id: NookColorID, _ tier: NookTokenTier, _ value: NookColorValue) {
        self.id = id
        self.tier = tier
        self.value = value
    }
}

struct NookFontToken: Sendable {
    let id: NookFontID
    let tier: NookTokenTier
    let value: NookFontSpec

    init(_ id: NookFontID, _ tier: NookTokenTier, _ value: NookFontSpec) {
        self.id = id
        self.tier = tier
        self.value = value
    }
}

struct NookAnimationToken: Sendable {
    let id: NookAnimationID
    let tier: NookTokenTier
    let value: NookAnimationSpec

    init(_ id: NookAnimationID, _ tier: NookTokenTier, _ value: NookAnimationSpec) {
        self.id = id
        self.tier = tier
        self.value = value
    }
}

/// Every token the framework defines, with its default.
///
/// Every default reproduces the value the framework hard-coded before themes existed: with
/// `NookTheme.standard` the resolved metrics, typography, motion, palette, style, and
/// transitions are equal to `NookChromeMetrics.default`, `NookChromeTypography.default`,
/// `NookChromeMotion.default`, `NookResolvedTheme.resolve(preferences:...)`,
/// `NookConfiguration.defaultStyle`, and the coordinator's default transitions. The tests
/// check that field by field.
enum NookTokenRegistry {
    // MARK: Colors

    private static func pair(_ dark: Double, _ light: Double) -> NookColorValue {
        .adaptive(NookAdaptiveColor(dark: .white(opacity: dark), light: .black(opacity: light)))
    }

    static let colorTokens: [NookColorToken] = [
        NookColorToken(.labelPrimary, .semantic, pair(0.95, 0.88)),
        NookColorToken(.labelSecondary, .semantic, pair(0.62, 0.55)),
        NookColorToken(.labelTertiary, .semantic, pair(0.46, 0.42)),
        NookColorToken(.labelQuaternary, .semantic, pair(0.34, 0.32)),
        NookColorToken(
            .fillSubtle,
            .semantic,
            .adaptive(
                NookAdaptiveColor(
                    dark: .white(opacity: 0.055),
                    light: .black(opacity: 0.030),
                    darkSolid: .white(opacity: 0.07),
                    lightSolid: .black(opacity: 0.045),
                    darkReducedTransparency: .white(opacity: 0.12),
                    lightReducedTransparency: .black(opacity: 0.055)
                )
            )
        ),
        NookColorToken(.strokeSubtle, .semantic, pair(0.14, 0.09)),
        NookColorToken(.iconInactive, .semantic, pair(0.42, 0.38)),
        // The theme's `accent` knob stands in for this default; see `NookThemeResolver`.
        NookColorToken(.accent, .semantic, .systemAccent),
        NookColorToken(
            .surface,
            .semantic,
            .adaptive(NookAdaptiveColor(dark: .black(opacity: 1), light: .white(opacity: 1)))
        ),
        NookColorToken(.hoverWash, .semantic, .white(opacity: 1)),
        NookColorToken(.destructive, .semantic, .system(.red)),
        NookColorToken(.warning, .semantic, .system(.orange)),
        NookColorToken(.success, .semantic, .system(.green)),
        NookColorToken(.feedbackTint, .semantic, .systemAccent),
        NookColorToken(.bannerSeverityError, .component, .accent),
        NookColorToken(.bannerSeverityWarning, .component, .accent),
        NookColorToken(.bannerSeverityInfo, .component, .accent),
        NookColorToken(.bannerSeveritySuccess, .component, .accent),
    ]

    // MARK: Numbers

    static let semanticDimensionTokens: [NookDimensionToken] = [
        NookDimensionToken(.spaceXXS, .semantic, .spacing, 2, .length),
        NookDimensionToken(.spaceXS, .semantic, .spacing, 4, .length),
        NookDimensionToken(.spaceSM, .semantic, .spacing, 6, .length),
        NookDimensionToken(.spaceMD, .semantic, .spacing, 8, .length),
        NookDimensionToken(.spaceLG, .semantic, .spacing, 10, .length),
        NookDimensionToken(.spaceXL, .semantic, .spacing, 12, .length),
        NookDimensionToken(.spaceXXL, .semantic, .spacing, 16, .length),
        NookDimensionToken(.radiusSM, .semantic, .radius, 6, .length),
        NookDimensionToken(.radiusMD, .semantic, .radius, 10, .length),
        NookDimensionToken(.radiusLG, .semantic, .radius, 12, .length),
        NookDimensionToken(.typeSize2XS, .semantic, .type, 8, .length),
        NookDimensionToken(.typeSizeXS, .semantic, .type, 9, .length),
        NookDimensionToken(.typeSizeSM, .semantic, .type, 10, .length),
        NookDimensionToken(.typeSizeMD, .semantic, .type, 11, .length),
        NookDimensionToken(.typeSizeLG, .semantic, .type, 12, .length),
        NookDimensionToken(.typeSizeXL, .semantic, .type, 13, .length),
        NookDimensionToken(.typeSize2XL, .semantic, .type, 14, .length),
        NookDimensionToken(.typeSizeDisplay, .semantic, .type, 24, .length),
        NookDimensionToken(.chromeTopRadius, .semantic, .none, 19, .length),
        NookDimensionToken(.chromeBottomRadius, .semantic, .radius, 24, .length),
        NookDimensionToken(.chromeInsetTop, .semantic, .none, 0, .length),
        NookDimensionToken(.chromeInsetBottom, .semantic, .none, 8, .length),
        NookDimensionToken(.chromeInsetLeading, .semantic, .none, 8, .length),
        NookDimensionToken(.chromeInsetTrailing, .semantic, .none, 8, .length),
        NookDimensionToken(.compactTopRadius, .semantic, .none, 6, .length),
        NookDimensionToken(.compactBottomRadius, .semantic, .none, 14, .length),
        NookDimensionToken(.floatingExpandedRadius, .semantic, .radius, .token(.chromeBottomRadius), .length),
        NookDimensionToken(.contentEnterDelay, .semantic, .none, 0, .duration),
        NookDimensionToken(.headerDelay, .semantic, .none, 0, .duration),
        NookDimensionToken(.stagger, .semantic, .none, 0, .duration),
    ]

    static let dimensionTokens: [NookDimensionToken] = semanticDimensionTokens + metricTokens

    // MARK: Fonts

    static let semanticFontTokens: [NookFontToken] = [
        NookFontToken(.typeBody, .semantic, NookFontSpec(size: .token(.typeSizeMD), weight: .regular)),
        NookFontToken(.typeGlyph, .semantic, NookFontSpec(size: .token(.typeSizeMD), weight: .semibold)),
        NookFontToken(.typeLabel, .semantic, NookFontSpec(size: .token(.typeSizeMD), weight: .medium)),
        NookFontToken(.typeCaption, .semantic, NookFontSpec(size: .token(.typeSizeSM), weight: .regular)),
    ]

    static let fontTokens: [NookFontToken] = semanticFontTokens + typographyTokens

    // MARK: Animations

    static let animationTokens: [NookAnimationToken] = [
        NookAnimationToken(.springSnappy, .semantic, .spring(response: 0.26, dampingFraction: 0.82)),
        NookAnimationToken(.springDefault, .semantic, .spring(response: 0.34, dampingFraction: 0.86)),
        NookAnimationToken(.springGentle, .semantic, .spring(response: 0.38, dampingFraction: 0.84)),
        NookAnimationToken(.curveQuick, .semantic, .curve(.easeOut, duration: 0.18)),
        NookAnimationToken(
            .transitionOpen,
            .semantic,
            .spring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.12)
        ),
        NookAnimationToken(
            .transitionClose,
            .semantic,
            .spring(response: 0.46, dampingFraction: 0.93, blendDuration: 0.10)
        ),
        NookAnimationToken(
            .transitionConvert,
            .semantic,
            .spring(response: 0.54, dampingFraction: 0.86, blendDuration: 0.12)
        ),
        NookAnimationToken(.viewModeChange, .component, .reference(.springGentle)),
        NookAnimationToken(.leadingClusterBack, .component, .spring(response: 0.34, dampingFraction: 0.85)),
        NookAnimationToken(.leadingClusterHover, .component, .reference(.springSnappy)),
        NookAnimationToken(.statusBanner, .component, .reference(.springDefault)),
        NookAnimationToken(.breadcrumb, .component, .reference(.curveQuick)),
        NookAnimationToken(.settingsDisclosure, .component, .spring(response: 0.30, dampingFraction: 0.86)),
        NookAnimationToken(.moduleSwitch, .component, .curve(.easeInOut, duration: 0.22)),
        NookAnimationToken(.activityCard, .component, .spring(response: 0.36, dampingFraction: 0.86)),
    ]

    // MARK: Transitions, sounds, shadows

    static let transitionTokens: [(id: NookTransitionID, value: NookContentTransitionSpec)] = [
        (.contentExit, .expandedContentDefault),
        (.contentEnter, .expandedContentDefault),
    ]

    /// Sound events. Every one defaults to no sound.
    static let soundTokens: [NookSoundID] = NookSoundID.allEvents

    /// Shadows. Every one defaults to none.
    static let shadowTokens: [NookShadowID] = [.chrome]

    // MARK: Lookups

    static let colorsByID: [NookColorID: NookColorToken] = Dictionary(
        uniqueKeysWithValues: colorTokens.map { ($0.id, $0) }
    )
    static let dimensionsByID: [NookDimensionID: NookDimensionToken] = Dictionary(
        uniqueKeysWithValues: dimensionTokens.map { ($0.id, $0) }
    )
    static let fontsByID: [NookFontID: NookFontToken] = Dictionary(
        uniqueKeysWithValues: fontTokens.map { ($0.id, $0) }
    )
    static let animationsByID: [NookAnimationID: NookAnimationToken] = Dictionary(
        uniqueKeysWithValues: animationTokens.map { ($0.id, $0) }
    )
    static let transitionsByID: [NookTransitionID: NookContentTransitionSpec] = Dictionary(
        uniqueKeysWithValues: transitionTokens.map { ($0.id, $0.value) }
    )

    /// Every token id the framework defines, with its kind and tier.
    static let allIDs: [(id: String, kind: NookTokenKind, tier: NookTokenTier)] = {
        var ids: [(id: String, kind: NookTokenKind, tier: NookTokenTier)] = []
        ids += colorTokens.map { ($0.id.rawValue, .color, $0.tier) }
        ids += dimensionTokens.map { ($0.id.rawValue, .dimension, $0.tier) }
        ids += fontTokens.map { ($0.id.rawValue, .font, $0.tier) }
        ids += animationTokens.map { ($0.id.rawValue, .animation, $0.tier) }
        ids += transitionTokens.map { ($0.id.rawValue, .transition, .semantic) }
        ids += soundTokens.map { ($0.rawValue, .sound, .semantic) }
        ids += shadowTokens.map { ($0.rawValue, .shadow, .semantic) }
        return ids
    }()

    static let entriesByID: [String: (kind: NookTokenKind, tier: NookTokenTier)] = Dictionary(
        uniqueKeysWithValues: allIDs.map { ($0.id, (kind: $0.kind, tier: $0.tier)) }
    )

    /// The kind and tier of the token named `id`, or `nil` when the framework defines none.
    static func entry(for id: String) -> (kind: NookTokenKind, tier: NookTokenTier)? {
        entriesByID[id]
    }
}
