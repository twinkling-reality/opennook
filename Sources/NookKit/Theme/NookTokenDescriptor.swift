// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import SwiftUI

/// One token the framework defines, described well enough for a tool to list and edit every
/// token without a table of its own: the id, the kind of value it holds, its tier, its default,
/// and for a number, which knob scales it and the range it is kept in.
///
/// ```swift
/// for token in NookTokenDescriptor.all where token.kind == .dimension {
///     print(token.id, token.defaultValue as Any)
/// }
/// let banner = NookTokenDescriptor.named("banner.cornerRadius")
/// ```
///
/// The list is read from the same registry the resolver uses, so it always matches what a theme
/// file accepts.
public struct NookTokenDescriptor: Equatable, Sendable, Identifiable {
    /// The kind of value a token holds. A token's override in ``NookThemeTokens`` must be of
    /// its kind.
    public enum Kind: String, Sendable, CaseIterable {
        /// A ``NookColorValue``.
        case color
        /// A ``NookDimension``: a length, an opacity, a tracking, or a duration.
        case dimension
        /// A ``NookFontSpec``.
        case font
        /// A ``NookAnimationSpec``.
        case animation
        /// A ``NookContentTransitionSpec``.
        case transition
        /// A ``NookSoundSpec``. Every sound defaults to none.
        case sound
        /// A ``NookShadowSpec``. Every shadow defaults to none.
        case shadow
    }

    /// Where a theme file lists the token.
    public enum Tier: String, Sendable, CaseIterable {
        /// A shared value many parts of the chrome default from, listed under `tokens`.
        case semantic
        /// One part of the chrome, listed under `components`.
        case component
    }

    /// Which theme knob multiplies a number written for the token.
    public enum Scaling: String, Sendable, CaseIterable {
        /// No knob: the number is used as written.
        case none
        /// The theme's ``NookTheme/scale``.
        case spacing
        /// The theme's ``NookTheme/scale``.
        case type
        /// The theme's ``NookTheme/radius``.
        case radius
    }

    /// What a numeric token counts, and the range its resolved value is kept in.
    public enum Unit: String, Sendable, CaseIterable {
        /// A length in points, 0...10000.
        case points
        /// An opacity multiplier, 0...1.
        case opacity
        /// Letter spacing in points, -100...100.
        case tracking
        /// A duration in seconds, 0...60.
        case seconds

        /// The range a resolved value is clamped to.
        public var bounds: ClosedRange<Double> {
            range.bounds
        }

        var range: NookNumberRange {
            switch self {
                case .points: .length
                case .opacity: .opacity
                case .tracking: .tracking
                case .seconds: .duration
            }
        }

        init(_ range: NookNumberRange) {
            switch range {
                case .length: self = .points
                case .opacity: self = .opacity
                case .tracking: self = .tracking
                case .duration: self = .seconds
            }
        }
    }

    /// The token's stable dotted id, such as `banner.cornerRadius`.
    public let id: String
    public let kind: Kind
    public let tier: Tier
    /// The value the token has when a theme does not override it, or `nil` for a sound or a
    /// shadow, which default to none. A default may refer to another token, as
    /// `banner.cornerRadius` refers to `radius.md`.
    public let defaultValue: NookTokenValue?
    /// The knob that multiplies a number written for a dimension token. ``Scaling/none`` for
    /// every other kind.
    public let scaling: Scaling
    /// What a dimension token counts. `nil` for every other kind.
    public let unit: Unit?

    /// The id's first component, such as `banner` for `banner.cornerRadius`: how a list of
    /// tokens is grouped.
    public var group: String {
        String(id.prefix { $0 != "." })
    }

    /// Every token the framework defines, colors first, then numbers, fonts, animations,
    /// transitions, sounds, and shadows, each in the order the registry lists them.
    public static let all: [NookTokenDescriptor] = NookTokenRegistry.allIDs.map { entry in
        describe(id: entry.id, kind: entry.kind, tier: entry.tier)
    }

    private static let byID: [String: NookTokenDescriptor] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// The token named `id`, or `nil` when the framework defines none. An id that was renamed
    /// finds the token under its new name, as a theme file does.
    public static func named(_ id: String) -> NookTokenDescriptor? {
        guard let current = NookTokenRenames.currentID(for: id) else { return nil }
        return byID[current]
    }

    private static func describe(id: String, kind: NookTokenKind, tier: NookTokenTier) -> NookTokenDescriptor {
        let publicTier: Tier = tier == .semantic ? .semantic : .component
        switch kind {
            case .color:
                let token = NookTokenRegistry.colorsByID[NookColorID(rawValue: id)]
                return NookTokenDescriptor(
                    id: id,
                    kind: .color,
                    tier: publicTier,
                    defaultValue: token.map { .color($0.value) },
                    scaling: .none,
                    unit: nil
                )
            case .dimension:
                let token = NookTokenRegistry.dimensionsByID[NookDimensionID(rawValue: id)]
                let scaling: Scaling =
                    switch token?.scaling ?? .none {
                        case .none: .none
                        case .spacing: .spacing
                        case .type: .type
                        case .radius: .radius
                    }
                return NookTokenDescriptor(
                    id: id,
                    kind: .dimension,
                    tier: publicTier,
                    defaultValue: token.map { .dimension($0.value) },
                    scaling: scaling,
                    unit: token.map { Unit($0.range) } ?? .points
                )
            case .font:
                let token = NookTokenRegistry.fontsByID[NookFontID(rawValue: id)]
                return NookTokenDescriptor(
                    id: id,
                    kind: .font,
                    tier: publicTier,
                    defaultValue: token.map { .font($0.value) },
                    scaling: .none,
                    unit: nil
                )
            case .animation:
                let token = NookTokenRegistry.animationsByID[NookAnimationID(rawValue: id)]
                return NookTokenDescriptor(
                    id: id,
                    kind: .animation,
                    tier: publicTier,
                    defaultValue: token.map { .animation($0.value) },
                    scaling: .none,
                    unit: nil
                )
            case .transition:
                let value = NookTokenRegistry.transitionsByID[NookTransitionID(rawValue: id)]
                return NookTokenDescriptor(
                    id: id,
                    kind: .transition,
                    tier: publicTier,
                    defaultValue: value.map { .transition($0) },
                    scaling: .none,
                    unit: nil
                )
            case .sound:
                return NookTokenDescriptor(
                    id: id,
                    kind: .sound,
                    tier: publicTier,
                    defaultValue: nil,
                    scaling: .none,
                    unit: nil
                )
            case .shadow:
                return NookTokenDescriptor(
                    id: id,
                    kind: .shadow,
                    tier: publicTier,
                    defaultValue: nil,
                    scaling: .none,
                    unit: nil
                )
        }
    }
}

// MARK: - Values

/// A token's value, as whichever kind the token holds: what ``NookThemeTokens`` stores for an
/// id when the id's kind is only known at run time.
public enum NookTokenValue: Equatable, Sendable {
    case color(NookColorValue)
    case dimension(NookDimension)
    case font(NookFontSpec)
    case animation(NookAnimationSpec)
    case transition(NookContentTransitionSpec)
    case sound(NookSoundSpec)
    case shadow(NookShadowSpec)

    /// The kind of token this value fits.
    public var kind: NookTokenDescriptor.Kind {
        switch self {
            case .color: .color
            case .dimension: .dimension
            case .font: .font
            case .animation: .animation
            case .transition: .transition
            case .sound: .sound
            case .shadow: .shadow
        }
    }
}

extension NookThemeTokens {
    /// The override for the token named `id`, as a value of its kind, or `nil` when the theme
    /// leaves it at its default or the framework defines no such token.
    public func value(for id: String) -> NookTokenValue? {
        guard let descriptor = NookTokenDescriptor.named(id) else { return nil }
        let id = descriptor.id
        switch descriptor.kind {
            case .color: return colors[NookColorID(rawValue: id)].map { .color($0) }
            case .dimension: return dimensions[NookDimensionID(rawValue: id)].map { .dimension($0) }
            case .font: return fonts[NookFontID(rawValue: id)].map { .font($0) }
            case .animation: return animations[NookAnimationID(rawValue: id)].map { .animation($0) }
            case .transition: return transitions[NookTransitionID(rawValue: id)].map { .transition($0) }
            case .sound: return sounds[NookSoundID(rawValue: id)].map { .sound($0) }
            case .shadow: return shadows[NookShadowID(rawValue: id)].map { .shadow($0) }
        }
    }

    /// Overrides the token named `id` with `value`, or removes its override when `value` is
    /// `nil`.
    ///
    /// - Returns: `false`, changing nothing, when the framework defines no token named `id` or
    ///   `value` is not of the token's kind.
    @discardableResult
    public mutating func setValue(_ value: NookTokenValue?, for id: String) -> Bool {
        guard let descriptor = NookTokenDescriptor.named(id) else { return false }
        let id = descriptor.id
        guard let value else {
            switch descriptor.kind {
                case .color: colors[NookColorID(rawValue: id)] = nil
                case .dimension: dimensions[NookDimensionID(rawValue: id)] = nil
                case .font: fonts[NookFontID(rawValue: id)] = nil
                case .animation: animations[NookAnimationID(rawValue: id)] = nil
                case .transition: transitions[NookTransitionID(rawValue: id)] = nil
                case .sound: sounds[NookSoundID(rawValue: id)] = nil
                case .shadow: shadows[NookShadowID(rawValue: id)] = nil
            }
            return true
        }
        guard value.kind == descriptor.kind else { return false }
        switch value {
            case .color(let color): colors[NookColorID(rawValue: id)] = color
            case .dimension(let dimension): dimensions[NookDimensionID(rawValue: id)] = dimension
            case .font(let font): fonts[NookFontID(rawValue: id)] = font
            case .animation(let animation): animations[NookAnimationID(rawValue: id)] = animation
            case .transition(let transition): transitions[NookTransitionID(rawValue: id)] = transition
            case .sound(let sound): sounds[NookSoundID(rawValue: id)] = sound
            case .shadow(let shadow): shadows[NookShadowID(rawValue: id)] = shadow
        }
        return true
    }
}

/// Token overrides as one flat JSON object keyed by token id, semantic and component tokens
/// alike, each value in the form a theme file writes it:
///
/// ```json
/// { "banner.cornerRadius": 12, "color.label.secondary": "#FFFFFFA8", "shadow.chrome": { "radius": 8, "y": 3 } }
/// ```
///
/// Decoding reads an id the framework renamed as its new name and skips an id it does not
/// define, and a `null` member, as a theme file's `tokens` do. A value of the wrong kind
/// throws, naming its path.
extension NookThemeTokens: Codable {
    public init(from decoder: any Decoder) throws {
        self.init()
        try decodeMembers(of: decoder.container(keyedBy: NookCodingKey.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        try encodeMembers(in: .semantic, into: &container)
        try encodeMembers(in: .component, into: &container)
    }
}

// MARK: - Resolved values

/// A token's value under a theme, with references followed and the knobs applied: what the
/// chrome actually draws.
public enum NookResolvedTokenValue: Equatable, Sendable {
    case color(Color)
    /// The number, with ``NookTheme/scale`` or ``NookTheme/radius`` applied and kept in range.
    case dimension(Double)
    /// The font with no role or reference left: its size is the size drawn, with the theme's
    /// scale applied.
    case font(NookFontSpec)
    /// The animation with references followed and the theme's motion scheme applied.
    case animation(NookAnimationSpec)
    /// The transition, its animation reference, if any, followed.
    case transition(NookContentTransitionSpec)
    /// The sound with the theme's sound volume applied, or `nil` for none.
    case sound(NookSoundSpec?)
    /// The shadow, or `nil` for none.
    case shadow(NookShadowSpec?)
}

extension NookTheme {
    /// The value the token named `id` resolves to under this theme in `context`, or `nil` when
    /// the framework defines no such token. A tool shows it beside an override, so a person
    /// sees what a reference or a knob comes to.
    ///
    /// ```swift
    /// let context = theme.context(preferences: .default, systemColorScheme: .dark, reduceTransparency: false)
    /// if case .dimension(let radius) = theme.resolvedValue(for: "banner.cornerRadius", in: context) { ... }
    /// ```
    public func resolvedValue(for id: String, in context: NookThemeContext) -> NookResolvedTokenValue? {
        guard let descriptor = NookTokenDescriptor.named(id) else { return nil }
        let id = descriptor.id
        let resolver = NookThemeResolver(theme: self)
        switch descriptor.kind {
            case .color:
                return .color(resolver.color(NookColorID(rawValue: id), in: context))
            case .dimension:
                return .dimension(resolver.dimension(NookDimensionID(rawValue: id)))
            case .font:
                let spec = resolver.fontSpec(NookFontID(rawValue: id))
                return .font(
                    NookFontSpec(
                        size: .points(spec.size),
                        weight: spec.weight,
                        design: spec.design,
                        width: spec.width,
                        family: spec.family,
                        monospacedDigits: spec.monospacedDigits
                    )
                )
            case .animation:
                return .animation(motion.applied(to: resolver.animationSpec(NookAnimationID(rawValue: id))))
            case .transition:
                let transitionID = NookTransitionID(rawValue: id)
                var spec =
                    tokens.transitions[transitionID] ?? NookTokenRegistry.transitionsByID[transitionID]
                    ?? NookContentTransitionSpec()
                if case .reference(let reference)? = spec.animation {
                    spec.animation = motion.applied(to: resolver.animationSpec(reference))
                } else if let animation = spec.animation {
                    spec.animation = motion.applied(to: animation.clampedForPlayback)
                }
                return .transition(spec)
            case .sound:
                guard let sound = tokens.sounds[NookSoundID(rawValue: id)] else { return .sound(nil) }
                var played = sound
                played.volume = sound.effectiveVolume(masterVolume: soundVolume)
                return .sound(played)
            case .shadow:
                return .shadow(tokens.shadows[NookShadowID(rawValue: id)])
        }
    }
}
