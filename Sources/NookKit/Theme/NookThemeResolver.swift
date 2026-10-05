// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookSurface
import SwiftUI

/// The appearance a theme's colors are resolved for.
///
/// Built from the person's preferences with
/// ``NookTheme/context(preferences:systemColorScheme:reduceTransparency:)``, which applies
/// the theme's pins first.
public struct NookThemeContext: Equatable, Sendable {
    /// Whether the chrome is dark.
    public var isDark: Bool
    /// The surface style the chrome paints.
    public var surfaceStyle: NookSurfaceStyle
    /// Whether Reduce Transparency is on.
    public var reduceTransparency: Bool
    /// The person's accent choice. Anything but `.system` replaces the theme's accent when
    /// the theme allows it.
    public var accentPreset: NookAccentPreset

    public init(
        isDark: Bool,
        surfaceStyle: NookSurfaceStyle = .solid,
        reduceTransparency: Bool = false,
        accentPreset: NookAccentPreset = .system
    ) {
        self.isDark = isDark
        self.surfaceStyle = surfaceStyle
        self.reduceTransparency = reduceTransparency
        self.accentPreset = accentPreset
    }
}

extension NookTheme {
    /// `preferences` with the theme's pins applied: a pinned palette, surface, or backdrop
    /// strength replaces the person's, and the person's accent becomes `.system` (the theme's
    /// accent) when ``allowsUserAccent`` is `false`. The person's stored choices are not
    /// touched; this is what the chrome paints with.
    public func effectivePreferences(_ preferences: NookAppearancePreferences) -> NookAppearancePreferences {
        var effective = preferences
        if let palette { effective.chromePalette = palette }
        if let surface { effective.surfaceStyle = surface }
        if let backdropStrength {
            effective.backdropStrength = backdropStrength.isFinite ? min(max(backdropStrength, 0.15), 1) : 1
        }
        if !allowsUserAccent { effective.accentPreset = .system }
        return effective
    }

    /// The appearance to resolve colors for, from the person's preferences with the theme's
    /// pins applied. `systemColorScheme` is the system's appearance, used when the palette
    /// follows the system.
    public func context(
        preferences: NookAppearancePreferences,
        systemColorScheme: ColorScheme,
        reduceTransparency: Bool
    ) -> NookThemeContext {
        let effective = effectivePreferences(preferences)
        let isDark: Bool =
            switch effective.chromePalette {
                case .followSystem: systemColorScheme == .dark
                case .dark: true
                case .light: false
            }
        return NookThemeContext(
            isDark: isDark,
            surfaceStyle: effective.surfaceStyle,
            reduceTransparency: reduceTransparency,
            accentPreset: effective.accentPreset
        )
    }

    /// The color token `id` resolves to in `context`.
    public func color(_ id: NookColorID, in context: NookThemeContext) -> Color {
        NookThemeResolver(theme: self).color(id, in: context)
    }

    /// `color` resolved in `context`, its references looked up in this theme: how a
    /// third party resolves a color it was handed, the `"accent"` placeholder included.
    public func resolve(_ color: NookColorValue, in context: NookThemeContext) -> Color {
        NookThemeResolver(theme: self).resolve(color, in: context, useOverrides: true)
    }

    /// Every token that does not depend on the appearance, resolved: lengths, fonts,
    /// animations, transitions, sounds, and shadows, with the theme's knobs applied.
    public func resolvedTokens() -> NookResolvedTokens {
        NookThemeResolver(theme: self).resolveAll()
    }
}

/// How content leaves or enters the chrome, resolved for SwiftUI. See
/// ``NookContentTransitionSpec``.
public struct NookResolvedContentTransition: Equatable, Sendable {
    public var opacity: Double
    public var blur: CGFloat
    public var scaleX: CGFloat
    public var scaleY: CGFloat
    public var anchor: UnitPoint
    public var offset: CGSize
    /// `nil` follows the surface's own curve.
    public var animation: Animation?
}

/// A theme's appearance-independent tokens, resolved: every number with the knobs applied,
/// every font and animation built. Read a token by id, or a whole chrome group at once
/// (``metrics``, ``typography``, ``motion``, ``style``, ``transitionConfiguration``).
public struct NookResolvedTokens: Sendable {
    let dimensions: [NookDimensionID: Double]
    let fonts: [NookFontID: Font]
    let animations: [NookAnimationID: Animation]
    let transitions: [NookTransitionID: NookResolvedContentTransition]
    let sounds: [NookSoundID: NookSoundSpec]
    let shadows: [NookShadowID: NookShadowSpec]

    /// The number `id` resolves to, or 0 for an id the framework does not define.
    public subscript(id: NookDimensionID) -> CGFloat {
        CGFloat(dimensions[id] ?? 0)
    }

    /// The font `id` resolves to, or the system font at 13 points for an id the framework
    /// does not define.
    public subscript(id: NookFontID) -> Font {
        fonts[id] ?? .system(size: 13)
    }

    /// The animation `id` resolves to, or `.default` for an id the framework does not define.
    public subscript(id: NookAnimationID) -> Animation {
        animations[id] ?? .default
    }

    /// The transition `id` resolves to, or a plain fade for an id the framework does not define.
    public func transition(_ id: NookTransitionID) -> NookResolvedContentTransition {
        transitions[id]
            ?? NookResolvedContentTransition(
                opacity: 0,
                blur: 0,
                scaleX: 1,
                scaleY: 1,
                anchor: .center,
                offset: .zero,
                animation: nil
            )
    }

    /// The sound for `id`, with the theme's `soundVolume` already applied to its volume, or
    /// `nil` for no sound.
    public func sound(_ id: NookSoundID) -> NookSoundSpec? {
        sounds[id]
    }

    /// The shadow for `id`, or `nil` for none. Its color is resolved with the palette.
    public func shadow(_ id: NookShadowID) -> NookShadowSpec? {
        shadows[id]
    }

    /// The chrome metrics. With ``NookTheme/standard`` this equals ``NookChromeMetrics/default``.
    public var metrics: NookChromeMetrics {
        var metrics = NookChromeMetrics.default
        for field in Self.metricFields {
            metrics[keyPath: field.keyPath] = self[field.id]
        }
        return metrics
    }

    /// The chrome typography. With ``NookTheme/standard`` this equals
    /// ``NookChromeTypography/default``.
    public var typography: NookChromeTypography {
        var typography = NookChromeTypography.default
        for field in Self.typographyFields {
            typography[keyPath: field.keyPath] = self[field.id]
        }
        return typography
    }

    /// The chrome's in-panel motion. With ``NookTheme/standard`` this equals
    /// ``NookChromeMotion/default``.
    public var motion: NookChromeMotion {
        var motion = NookChromeMotion.default
        for field in Self.motionFields {
            motion[keyPath: field.keyPath] = self[field.id]
        }
        return motion
    }

    /// The chrome's shape. With ``NookTheme/standard`` this equals
    /// ``NookConfiguration/defaultStyle``.
    public var style: NookStyle {
        let bottom = self[.chromeBottomRadius]
        let floating = self[.floatingExpandedRadius]
        return NookStyle(
            topCornerRadius: self[.chromeTopRadius],
            bottomCornerRadius: bottom,
            expandedContentInsets: NookEdgeInsets(
                top: self[.chromeInsetTop],
                bottom: self[.chromeInsetBottom],
                leading: self[.chromeInsetLeading],
                trailing: self[.chromeInsetTrailing]
            ),
            compactTopCornerRadius: self[.compactTopRadius],
            compactBottomCornerRadius: self[.compactBottomRadius],
            // The surface's own fallback for the floating card is the expanded bottom radius,
            // which is also this token's default; leave it to the fallback unless it differs.
            floatingExpandedTopCornerRadius: floating == bottom ? nil : floating,
            floatingExpandedBottomCornerRadius: floating == bottom ? nil : floating
        )
    }

    /// The surface's expand, collapse, and conversion curves. With ``NookTheme/standard``
    /// these are the framework's default springs.
    ///
    /// The content transitions come from `motion.content.enter` (expanded content, scaled
    /// vertically) and `motion.compact.transition` (compact slots, scaled horizontally): the
    /// surface plays one transition each way, so `motion.content.exit`, the anchors, offsets,
    /// curves, delays, and stagger of the content tokens are not drawn by the surface yet.
    public var transitionConfiguration: NookTransitionConfiguration {
        let expanded = transition(.contentEnter)
        let compact = transition(.compactContent)
        return NookTransitionConfiguration(
            openingAnimation: self[.transitionOpen],
            closingAnimation: self[.transitionClose],
            conversionAnimation: self[.transitionConvert],
            compactContentTransition: NookContentTransition(
                blurRadius: compact.blur,
                scale: compact.scaleX,
                fades: compact.opacity < 1
            ),
            expandedContentTransition: NookContentTransition(
                blurRadius: expanded.blur,
                scale: expanded.scaleY,
                fades: expanded.opacity < 1
            )
        )
    }

    /// The wash behind expanded content that lights the chrome with `nookAmbientColor(_:)`.
    /// With ``NookTheme/standard`` this equals `NookAmbientWash.standard`.
    public var ambientWash: NookAmbientWash {
        NookAmbientWash(
            opacities: [
                Double(self[.ambientWashTop]), Double(self[.ambientWashUpper]), Double(self[.ambientWashLower]),
                Double(self[.ambientWashBottom]),
            ]
        )
    }

    /// The standard theme's tokens: every value the chrome used before themes existed.
    public static let standard = NookTheme.standard.resolvedTokens()
}

/// A problem found while resolving a theme: a token that refers to one the framework does not
/// define, or tokens that refer to each other in a loop. The token falls back to its default.
struct NookThemeResolutionIssue: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case unknownReference(String)
        case cycle
        case wrongKind
    }

    let id: String
    let kind: Kind
}

/// Resolves one theme. Holds the memo and the in-progress set that catches reference loops,
/// so it is made, used, and dropped within one call.
final class NookThemeResolver {
    let theme: NookTheme
    private(set) var issues: [NookThemeResolutionIssue] = []

    private var dimensionCache: [NookDimensionID: Double] = [:]
    private var fontCache: [NookFontID: NookResolvedFontSpec] = [:]
    private var animationCache: [NookAnimationID: NookAnimationSpec] = [:]
    private var inProgress: Set<String> = []

    init(theme: NookTheme) {
        self.theme = theme
    }

    // MARK: Knobs

    private var scale: Double {
        theme.scale.isFinite ? min(max(theme.scale, 0.5), 2) : 1
    }

    private var radiusFactor: Double {
        let factor = theme.radius.factor
        return factor.isFinite ? min(max(factor, 0), 4) : 1
    }

    private func multiplier(_ scaling: NookTokenScaling) -> Double {
        switch scaling {
            case .none: 1
            case .spacing, .type: scale
            case .radius: radiusFactor
        }
    }

    private func note(_ id: String, _ kind: NookThemeResolutionIssue.Kind) {
        let issue = NookThemeResolutionIssue(id: id, kind: kind)
        if !issues.contains(issue) { issues.append(issue) }
    }

    /// Runs `body` with `key` marked in progress; returns `nil` when `key` is already in
    /// progress, which is a reference loop.
    private func guarded<T>(_ key: String, id: String, _ body: () -> T) -> T? {
        guard inProgress.insert(key).inserted else {
            note(id, .cycle)
            return nil
        }
        defer { inProgress.remove(key) }
        return body()
    }

    // MARK: Numbers

    func dimension(_ id: NookDimensionID, useOverrides: Bool = true) -> Double {
        if useOverrides, let cached = dimensionCache[id] { return cached }
        guard let token = NookTokenRegistry.dimensionsByID[id] else {
            note(id.rawValue, .unknownReference(id.rawValue))
            return 0
        }
        let override = useOverrides ? theme.tokens.dimensions[id] : nil
        let resolved =
            guarded("d:" + id.rawValue, id: id.rawValue) {
                evaluate(override ?? token.value, scaling: token.scaling, useOverrides: useOverrides)
            } ?? evaluate(token.value, scaling: token.scaling, useOverrides: false)
        let bounds = token.range.bounds
        let value = resolved.isFinite ? min(max(resolved, bounds.lowerBound), bounds.upperBound) : 0
        if useOverrides { dimensionCache[id] = value }
        return value
    }

    private func evaluate(_ value: NookDimension, scaling: NookTokenScaling, useOverrides: Bool) -> Double {
        switch value {
            case .points(let points):
                return points * multiplier(scaling)
            case .reference(let reference, let times):
                guard let current = NookTokenRenames.currentID(for: reference.rawValue),
                    NookTokenRegistry.dimensionsByID[NookDimensionID(rawValue: current)] != nil
                else {
                    note(reference.rawValue, .unknownReference(reference.rawValue))
                    return 0
                }
                return dimension(NookDimensionID(rawValue: current), useOverrides: useOverrides) * times
        }
    }

    // MARK: Fonts

    func fontSpec(_ id: NookFontID, useOverrides: Bool = true) -> NookResolvedFontSpec {
        if useOverrides, let cached = fontCache[id] { return cached }
        guard let token = NookTokenRegistry.fontsByID[id] else {
            note(id.rawValue, .unknownReference(id.rawValue))
            return NookResolvedFontSpec(size: 13 * scale)
        }
        let override = useOverrides ? theme.tokens.fonts[id] : nil
        let resolved =
            guarded("f:" + id.rawValue, id: id.rawValue) {
                resolve(override ?? token.value, useOverrides: useOverrides)
            } ?? resolve(token.value, useOverrides: false)
        if useOverrides { fontCache[id] = resolved }
        return resolved
    }

    private func resolve(_ spec: NookFontSpec, useOverrides: Bool) -> NookResolvedFontSpec {
        var base: NookResolvedFontSpec?
        if let role = spec.role {
            if let current = NookTokenRenames.currentID(for: role.rawValue),
                NookTokenRegistry.fontsByID[NookFontID(rawValue: current)] != nil
            {
                base = fontSpec(NookFontID(rawValue: current), useOverrides: useOverrides)
            } else {
                note(role.rawValue, .unknownReference(role.rawValue))
            }
        }
        let size =
            spec.size.map { evaluate($0, scaling: .type, useOverrides: useOverrides) } ?? base?.size ?? 13 * scale
        return NookResolvedFontSpec(
            size: size.isFinite ? min(max(size, 1), 200) : 13,
            weight: spec.weight ?? base?.weight,
            design: spec.design ?? base?.design,
            width: spec.width ?? base?.width,
            family: spec.family ?? base?.family,
            monospacedDigits: spec.monospacedDigits ?? base?.monospacedDigits
        )
    }

    // MARK: Animations

    /// The animation `id` resolves to, with every reference followed. The motion scheme is
    /// applied when it is built, not here.
    func animationSpec(_ id: NookAnimationID, useOverrides: Bool = true) -> NookAnimationSpec {
        if useOverrides, let cached = animationCache[id] { return cached }
        guard let token = NookTokenRegistry.animationsByID[id] else {
            note(id.rawValue, .unknownReference(id.rawValue))
            return .curve(.easeInOut, duration: 0.35)
        }
        let override = useOverrides ? theme.tokens.animations[id] : nil
        let resolved =
            guarded("a:" + id.rawValue, id: id.rawValue) {
                follow(override ?? token.value, useOverrides: useOverrides)
            } ?? follow(token.value, useOverrides: false)
        if useOverrides { animationCache[id] = resolved }
        return resolved
    }

    private func follow(_ spec: NookAnimationSpec, useOverrides: Bool) -> NookAnimationSpec {
        guard case .reference(let reference) = spec else { return spec.clampedForPlayback }
        guard let current = NookTokenRenames.currentID(for: reference.rawValue),
            NookTokenRegistry.animationsByID[NookAnimationID(rawValue: current)] != nil
        else {
            note(reference.rawValue, .unknownReference(reference.rawValue))
            return .curve(.easeInOut, duration: 0.35)
        }
        return animationSpec(NookAnimationID(rawValue: current), useOverrides: useOverrides)
    }

    func animation(_ id: NookAnimationID) -> Animation {
        animationSpec(id).animation(scheme: theme.motion) ?? .default
    }

    private func animation(for spec: NookAnimationSpec?) -> Animation? {
        guard let spec else { return nil }
        return follow(spec, useOverrides: true).animation(scheme: theme.motion)
    }

    // MARK: Transitions

    func transition(_ id: NookTransitionID) -> NookResolvedContentTransition {
        let spec = theme.tokens.transitions[id] ?? NookTokenRegistry.transitionsByID[id] ?? NookContentTransitionSpec()
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        return NookResolvedContentTransition(
            opacity: clamp(spec.opacity, 0...1, 0),
            blur: CGFloat(clamp(spec.blur, 0...100, 0)),
            scaleX: CGFloat(clamp(spec.scaleX, 0...4, 1)),
            scaleY: CGFloat(clamp(spec.scaleY, 0...4, 1)),
            anchor: spec.anchor.unitPoint,
            offset: CGSize(width: clamp(spec.offsetX, -1000...1000, 0), height: clamp(spec.offsetY, -1000...1000, 0)),
            animation: animation(for: spec.animation)
        )
    }

    // MARK: Colors

    func color(_ id: NookColorID, in context: NookThemeContext, useOverrides: Bool = true) -> Color {
        guard let token = NookTokenRegistry.colorsByID[id] else {
            note(id.rawValue, .unknownReference(id.rawValue))
            return .clear
        }
        // The accent's default is the theme's `accent` knob, and the person's own accent
        // replaces both when the theme allows it.
        if id == .accent, theme.allowsUserAccent, context.accentPreset != .system {
            return context.accentPreset.color()
        }
        let defaultValue = id == .accent && useOverrides ? theme.accent : token.value
        let value = (useOverrides ? theme.tokens.colors[id] : nil) ?? defaultValue
        return guarded("c:" + id.rawValue, id: id.rawValue) {
            resolve(value, in: context, useOverrides: useOverrides)
        } ?? resolve(token.value, in: context, useOverrides: false)
    }

    func resolve(_ value: NookColorValue, in context: NookThemeContext, useOverrides: Bool) -> Color {
        switch value {
            case .hex(let rgba):
                return rgba.color
            case .srgb(let red, let green, let blue, let opacity):
                return Color(red: red, green: green, blue: blue, opacity: opacity)
            case .white(let opacity):
                return opacity == 1 ? Color.white : Color.white.opacity(opacity)
            case .black(let opacity):
                return opacity == 1 ? Color.black : Color.black.opacity(opacity)
            case .system(let system):
                return system.color
            case .reference(let reference, let opacity):
                guard let current = NookTokenRenames.currentID(for: reference.rawValue),
                    NookTokenRegistry.colorsByID[NookColorID(rawValue: current)] != nil
                else {
                    note(reference.rawValue, .unknownReference(reference.rawValue))
                    return .clear
                }
                let color = color(NookColorID(rawValue: current), in: context, useOverrides: useOverrides)
                return opacity.map { color.opacity($0) } ?? color
            case .adaptive(let adaptive):
                let variant = adaptive.variant(
                    isDark: context.isDark,
                    isSolidSurface: context.surfaceStyle == .solid,
                    reduceTransparency: context.reduceTransparency
                )
                return resolve(variant, in: context, useOverrides: useOverrides)
            case .hierarchical(let level):
                // The label role's own default, so a role written as its hierarchical level
                // does not refer to itself.
                let role = NookTokenRegistry.colorsByID[level.labelRole]?.value ?? .white(opacity: 1)
                return resolve(role, in: context, useOverrides: false)
        }
    }

    // MARK: Everything

    func resolveAll() -> NookResolvedTokens {
        var dimensions: [NookDimensionID: Double] = [:]
        for token in NookTokenRegistry.dimensionTokens {
            dimensions[token.id] = dimension(token.id)
        }
        var fonts: [NookFontID: Font] = [:]
        for token in NookTokenRegistry.fontTokens {
            fonts[token.id] = fontSpec(token.id).font
        }
        var animations: [NookAnimationID: Animation] = [:]
        for token in NookTokenRegistry.animationTokens {
            animations[token.id] = animation(token.id)
        }
        var transitions: [NookTransitionID: NookResolvedContentTransition] = [:]
        for token in NookTokenRegistry.transitionTokens {
            transitions[token.id] = transition(token.id)
        }
        var sounds: [NookSoundID: NookSoundSpec] = [:]
        for (id, sound) in theme.tokens.sounds where NookTokenRegistry.soundTokens.contains(id) {
            var played = sound
            played.volume = sound.effectiveVolume(masterVolume: theme.soundVolume)
            sounds[id] = played
        }
        var shadows: [NookShadowID: NookShadowSpec] = [:]
        for (id, shadow) in theme.tokens.shadows where NookTokenRegistry.shadowTokens.contains(id) {
            shadows[id] = shadow
        }
        return NookResolvedTokens(
            dimensions: dimensions,
            fonts: fonts,
            animations: animations,
            transitions: transitions,
            sounds: sounds,
            shadows: shadows
        )
    }
}

extension NookAnimationSpec {
    /// The spec with every number kept where SwiftUI can play it.
    var clampedForPlayback: NookAnimationSpec {
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        switch self {
            case .spring(let response, let damping, let blend):
                return .spring(
                    response: clamp(response, 0.01...10, 0.5),
                    dampingFraction: clamp(damping, 0.01...2, 0.825),
                    blendDuration: clamp(blend, 0...10, 0)
                )
            case .springDuration(let duration, let bounce):
                return .springDuration(duration: clamp(duration, 0.01...10, 0.5), bounce: clamp(bounce, -1...1, 0))
            case .preset(let preset, let duration, let extraBounce):
                return .preset(
                    preset,
                    duration: clamp(duration, 0.01...10, 0.5),
                    extraBounce: clamp(extraBounce, -1...1, 0)
                )
            case .curve(let curve, let duration):
                return .curve(curve, duration: clamp(duration, 0...10, 0.35))
            case .bezier(let x1, let y1, let x2, let y2, let duration):
                return .bezier(
                    x1: clamp(x1, 0...1, 0.25),
                    y1: clamp(y1, -2...3, 0.1),
                    x2: clamp(x2, 0...1, 0.25),
                    y2: clamp(y2, -2...3, 1),
                    duration: clamp(duration, 0...10, 0.35)
                )
            case .reference:
                return self
        }
    }
}
