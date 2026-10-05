// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookSurface
import SwiftUI

/// The whole look of the chrome as one value: a few knobs, the semantic tokens the chrome
/// defaults from, and overrides for any single part. A theme is plain data, so it can be
/// written in Swift or loaded from a JSON file, and written back out.
///
/// The simple case is the knobs:
///
/// ```swift
/// let theme = NookTheme(accent: "#3399FF", radius: .large, fontDesign: .rounded)
/// ```
///
/// Under the knobs are tokens, each named by a stable dotted id. Semantic tokens are shared
/// values (`space.md`, `color.label.secondary`, `type.body`); component tokens are the
/// individual fields of `NookChromeMetrics`, `NookChromeTypography`, and `NookChromeMotion`,
/// each of which defaults from a semantic token or stays a fixed value:
///
/// ```swift
/// var theme = NookTheme()
/// theme.tokens[.spaceMD] = 9                         // every gap that defaults to it
/// theme.tokens[.bannerCornerRadius] = .token(.radiusLG)
/// theme.tokens[.destructive] = "#FF453A"
/// ```
///
/// ``standard`` reproduces the framework's chrome exactly: every value it resolves to is the
/// value the chrome used before themes existed.
///
/// What the person picks in Settings (palette, surface, accent, backdrop strength) still wins
/// unless the theme pins it: ``palette``, ``surface``, and ``backdropStrength`` pin those when
/// set, and ``allowsUserAccent`` decides whether the person's accent replaces ``accent``.
public struct NookTheme: Equatable, Sendable {
    /// A display name, for a theme someone picks from a list.
    public var name: String?

    // MARK: Knobs

    /// The accent: `color.accent`, which interactive controls are tinted with. Defaults to
    /// the macOS accent. The person's own accent choice replaces it unless
    /// ``allowsUserAccent`` is `false`.
    public var accent: NookColorValue
    /// Whether the person's accent choice in Settings replaces ``accent``. Their "System"
    /// choice always means ``accent``.
    public var allowsUserAccent: Bool
    /// Pins the chrome to dark, light, or the system appearance. `nil` (the default) leaves it
    /// to the person.
    public var palette: NookChromePalette?
    /// Pins the surface to solid, translucent, or Liquid Glass. `nil` (the default) leaves it to
    /// the person.
    public var surface: NookSurfaceStyle?
    /// Pins the backdrop strength, 0.15...1. `nil` (the default) leaves it to the person.
    public var backdropStrength: Double?
    /// How round corners are: multiplies every radius token and radius written for the chrome.
    public var radius: NookRadiusScale
    /// Multiplies spacing and type sizes, 0.5...2. Sizes tied to the notch and the menu bar
    /// (the top bar's height, the compact slots, icon frames) are not scaled.
    public var scale: Double
    /// The font design cascaded over the chrome's text.
    public var fontDesign: NookFontDesign
    /// The font width cascaded over the chrome's text.
    public var fontWidth: NookFontWidth
    /// How springy motion is. ``NookMotionScheme/standard`` leaves every curve as written.
    public var motion: NookMotionScheme
    /// Multiplies every sound's volume, 0...1.
    public var soundVolume: Double
    /// Whether the person may turn the theme's sounds off.
    public var allowsUserSoundToggle: Bool

    // MARK: Tokens

    /// Token overrides, semantic and component alike. Empty means every token has its
    /// default.
    public var tokens: NookThemeTokens
    /// Backdrops for each surface style. Empty means the framework's own.
    public var backdrops: NookThemeBackdrops

    public init(
        name: String? = nil,
        accent: NookColorValue = .systemAccent,
        allowsUserAccent: Bool = true,
        palette: NookChromePalette? = nil,
        surface: NookSurfaceStyle? = nil,
        backdropStrength: Double? = nil,
        radius: NookRadiusScale = .standard,
        scale: Double = 1,
        fontDesign: NookFontDesign = .default,
        fontWidth: NookFontWidth = .standard,
        motion: NookMotionScheme = .standard,
        soundVolume: Double = 1,
        allowsUserSoundToggle: Bool = true,
        tokens: NookThemeTokens = NookThemeTokens(),
        backdrops: NookThemeBackdrops = NookThemeBackdrops()
    ) {
        self.name = name
        self.accent = accent
        self.allowsUserAccent = allowsUserAccent
        self.palette = palette
        self.surface = surface
        self.backdropStrength = backdropStrength
        self.radius = radius
        self.scale = scale
        self.fontDesign = fontDesign
        self.fontWidth = fontWidth
        self.motion = motion
        self.soundVolume = soundVolume
        self.allowsUserSoundToggle = allowsUserSoundToggle
        self.tokens = tokens
        self.backdrops = backdrops
    }

    /// The framework's own look. Every value it resolves to is the one the chrome used before
    /// themes existed.
    public static let standard = NookTheme()
}

// MARK: - Radius

/// How round a theme's corners are.
public enum NookRadiusScale: Equatable, Sendable {
    /// Square corners.
    case none
    case small
    /// The framework's radii.
    case standard
    case large
    /// Radii multiplied by this factor, 0...4.
    case factor(Double)

    /// The multiplier this scale applies.
    public var factor: Double {
        switch self {
            case .none: 0
            case .small: 0.6
            case .standard: 1
            case .large: 1.4
            case .factor(let value): value
        }
    }

    private static let named: [(name: String, scale: NookRadiusScale)] = [
        ("none", .none), ("small", .small), ("standard", .standard), ("large", .large),
    ]
}

extension NookRadiusScale: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .factor(number)
            return
        }
        let name = try container.decode(String.self)
        guard let match = Self.named.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected none, small, standard, large, or a number; found \"\(name)\""
            )
        }
        self = match.scale
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let match = Self.named.first(where: { $0.scale == self }) {
            try container.encode(match.name)
        } else {
            try container.encode(factor)
        }
    }
}

// MARK: - Tokens

/// A theme's token overrides, keyed by token id. A token that is not here has its default.
///
/// Subscript with an id of the token's kind; assigning `nil` removes the override:
///
/// ```swift
/// tokens[.labelSecondary] = .adaptive(.init(dark: .white(opacity: 0.66), light: .black(opacity: 0.55)))
/// tokens[.spaceMD] = 9
/// tokens[.bannerMessage] = NookFontSpec(role: .typeBody, weight: .semibold)
/// tokens[.statusBanner] = .reference(.springSnappy)
/// tokens[.open] = .system("Pop")
/// ```
public struct NookThemeTokens: Equatable, Sendable {
    var colors: [NookColorID: NookColorValue] = [:]
    var dimensions: [NookDimensionID: NookDimension] = [:]
    var fonts: [NookFontID: NookFontSpec] = [:]
    var animations: [NookAnimationID: NookAnimationSpec] = [:]
    var transitions: [NookTransitionID: NookContentTransitionSpec] = [:]
    var sounds: [NookSoundID: NookSoundSpec] = [:]
    var shadows: [NookShadowID: NookShadowSpec] = [:]

    public init() {}

    public subscript(id: NookColorID) -> NookColorValue? {
        get { colors[id] }
        set { colors[id] = newValue }
    }

    public subscript(id: NookDimensionID) -> NookDimension? {
        get { dimensions[id] }
        set { dimensions[id] = newValue }
    }

    public subscript(id: NookFontID) -> NookFontSpec? {
        get { fonts[id] }
        set { fonts[id] = newValue }
    }

    public subscript(id: NookAnimationID) -> NookAnimationSpec? {
        get { animations[id] }
        set { animations[id] = newValue }
    }

    public subscript(id: NookTransitionID) -> NookContentTransitionSpec? {
        get { transitions[id] }
        set { transitions[id] = newValue }
    }

    public subscript(id: NookSoundID) -> NookSoundSpec? {
        get { sounds[id] }
        set { sounds[id] = newValue }
    }

    public subscript(id: NookShadowID) -> NookShadowSpec? {
        get { shadows[id] }
        set { shadows[id] = newValue }
    }

    /// The number of overrides.
    public var count: Int {
        colors.count + dimensions.count + fonts.count + animations.count + transitions.count + sounds.count
            + shadows.count
    }

    /// `true` when every token has its default.
    public var isEmpty: Bool { count == 0 }

    /// Every overridden id, as written in a theme file.
    public var ids: [String] {
        var ids: [String] = []
        ids += colors.keys.map(\.rawValue)
        ids += dimensions.keys.map(\.rawValue)
        ids += fonts.keys.map(\.rawValue)
        ids += animations.keys.map(\.rawValue)
        ids += transitions.keys.map(\.rawValue)
        ids += sounds.keys.map(\.rawValue)
        ids += shadows.keys.map(\.rawValue)
        return ids.sorted()
    }
}

// MARK: - Backdrops

/// The backdrop a theme paints for each surface style the person can pick. `nil` paints the
/// framework's own for that style.
public struct NookThemeBackdrops: Equatable, Sendable {
    public var solid: NookBackdropDescription?
    public var translucent: NookBackdropDescription?
    public var liquidGlass: NookBackdropDescription?
    /// How the framework's own Liquid Glass is shaded. `nil` leaves it to the chrome behavior.
    public var glassShading: NookGlassShading?

    public init(
        solid: NookBackdropDescription? = nil,
        translucent: NookBackdropDescription? = nil,
        liquidGlass: NookBackdropDescription? = nil,
        glassShading: NookGlassShading? = nil
    ) {
        self.solid = solid
        self.translucent = translucent
        self.liquidGlass = liquidGlass
        self.glassShading = glassShading
    }

    /// The description for `style`, if the theme has one.
    public subscript(style: NookSurfaceStyle) -> NookBackdropDescription? {
        switch style {
            case .solid: solid
            case .translucent: translucent
            case .liquidGlass: liquidGlass
        }
    }

    /// `true` when every style uses the framework's backdrop.
    public var isEmpty: Bool { self == NookThemeBackdrops() }
}

extension NookThemeBackdrops: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let shading = try container.optional(String.self, "glassShading")
        let glassShading: NookGlassShading?
        switch shading {
            case nil: glassShading = nil
            case "even": glassShading = .even
            case "notchFade": glassShading = .notchFade
            case let other?:
                throw DecodingError.dataCorruptedError(
                    forKey: NookCodingKey("glassShading"),
                    in: container,
                    debugDescription: "expected even or notchFade, found \"\(other)\""
                )
        }
        self.init(
            solid: try container.optional(NookBackdropDescription.self, "solid"),
            translucent: try container.optional(NookBackdropDescription.self, "translucent"),
            liquidGlass: try container.optional(NookBackdropDescription.self, "liquidGlass"),
            glassShading: glassShading
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        try container.putIfPresent(solid, "solid")
        try container.putIfPresent(translucent, "translucent")
        try container.putIfPresent(liquidGlass, "liquidGlass")
        switch glassShading {
            case .even: try container.put("even", "glassShading")
            case .notchFade: try container.put("notchFade", "glassShading")
            case nil: break
        }
    }
}

// MARK: - Coding

extension NookTheme: Codable {
    /// The top-level members a theme file may have, besides the `format` and `version` of
    /// the envelope.
    static let memberNames: Set<String> = [
        "name", "accent", "allowsUserAccent", "palette", "surface", "backdropStrength", "radius", "scale",
        "fontDesign", "fontWidth", "motion", "soundVolume", "allowsUserSoundToggle", "tokens", "components",
        "backdrops",
    ]

    /// Decodes tolerantly: a missing member has its default, and an unknown member or token id
    /// is ignored. A value of the wrong type still throws, naming its path. `NookThemeCoder`
    /// adds the envelope check and reports what was ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let fallback = NookTheme()
        self.init(
            name: try container.optional(String.self, "name"),
            accent: try container.optional(NookColorValue.self, "accent") ?? fallback.accent,
            allowsUserAccent: try container.optional(Bool.self, "allowsUserAccent") ?? fallback.allowsUserAccent,
            palette: try container.optional(NookChromePalette.self, "palette"),
            surface: try container.optional(NookSurfaceStyle.self, "surface"),
            backdropStrength: try container.optional(Double.self, "backdropStrength"),
            radius: try container.optional(NookRadiusScale.self, "radius") ?? fallback.radius,
            scale: try container.optional(Double.self, "scale") ?? fallback.scale,
            fontDesign: try container.optional(NookFontDesign.self, "fontDesign") ?? fallback.fontDesign,
            fontWidth: try container.optional(NookFontWidth.self, "fontWidth") ?? fallback.fontWidth,
            motion: try container.optional(NookMotionScheme.self, "motion") ?? fallback.motion,
            soundVolume: try container.optional(Double.self, "soundVolume") ?? fallback.soundVolume,
            allowsUserSoundToggle: try container.optional(Bool.self, "allowsUserSoundToggle")
                ?? fallback.allowsUserSoundToggle,
            tokens: NookThemeTokens(),
            backdrops: try container.optional(NookThemeBackdrops.self, "backdrops") ?? NookThemeBackdrops()
        )
        for section in ["tokens", "components"] where container.has(section) {
            let members = try container.nestedContainer(keyedBy: NookCodingKey.self, forKey: NookCodingKey(section))
            try tokens.decodeMembers(of: members)
        }
    }

    /// Encodes only what differs from ``standard``, so a theme file lists exactly what it
    /// changes. Semantic tokens go under `tokens`, the chrome's own fields under `components`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        let fallback = NookTheme()
        try container.putIfPresent(name, "name")
        if accent != fallback.accent { try container.put(accent, "accent") }
        if allowsUserAccent != fallback.allowsUserAccent { try container.put(allowsUserAccent, "allowsUserAccent") }
        try container.putIfPresent(palette, "palette")
        try container.putIfPresent(surface, "surface")
        try container.putIfPresent(backdropStrength, "backdropStrength")
        if radius != fallback.radius { try container.put(radius, "radius") }
        if scale != fallback.scale { try container.put(scale, "scale") }
        if fontDesign != fallback.fontDesign { try container.put(fontDesign, "fontDesign") }
        if fontWidth != fallback.fontWidth { try container.put(fontWidth, "fontWidth") }
        if motion != fallback.motion { try container.put(motion, "motion") }
        if soundVolume != fallback.soundVolume { try container.put(soundVolume, "soundVolume") }
        if allowsUserSoundToggle != fallback.allowsUserSoundToggle {
            try container.put(allowsUserSoundToggle, "allowsUserSoundToggle")
        }
        for (section, tier) in [("tokens", NookTokenTier.semantic), ("components", .component)] {
            guard tokens.hasMembers(in: tier) else { continue }
            var members = container.nestedContainer(keyedBy: NookCodingKey.self, forKey: NookCodingKey(section))
            try tokens.encodeMembers(in: tier, into: &members)
        }
        if !backdrops.isEmpty { try container.put(backdrops, "backdrops") }
    }
}

extension NookThemeTokens {
    /// The tier a theme file lists `id` under. An id the framework does not define is listed
    /// with the semantic tokens.
    static func tier(of id: String) -> NookTokenTier {
        NookTokenRegistry.entry(for: id)?.tier ?? .semantic
    }

    func hasMembers(in tier: NookTokenTier) -> Bool {
        ids.contains { Self.tier(of: $0) == tier }
    }

    func encodeMembers(in tier: NookTokenTier, into container: inout KeyedEncodingContainer<NookCodingKey>) throws {
        func include(_ id: String) -> Bool { Self.tier(of: id) == tier }
        for (id, value) in colors where include(id.rawValue) { try container.put(value, id.rawValue) }
        for (id, value) in dimensions where include(id.rawValue) { try container.put(value, id.rawValue) }
        for (id, value) in fonts where include(id.rawValue) { try container.put(value, id.rawValue) }
        for (id, value) in animations where include(id.rawValue) { try container.put(value, id.rawValue) }
        for (id, value) in transitions where include(id.rawValue) { try container.put(value, id.rawValue) }
        for (id, value) in sounds where include(id.rawValue) { try container.put(value, id.rawValue) }
        for (id, value) in shadows where include(id.rawValue) { try container.put(value, id.rawValue) }
    }

    /// Reads every member of a `tokens` or `components` object whose id the framework
    /// defines, by the kind that id names. Members it does not know, and `null` members, are
    /// skipped.
    mutating func decodeMembers(of container: KeyedDecodingContainer<NookCodingKey>) throws {
        for key in container.allKeys {
            guard let id = NookTokenRenames.currentID(for: key.stringValue),
                let entry = NookTokenRegistry.entry(for: id),
                try !container.decodeNil(forKey: key)
            else { continue }
            switch entry.kind {
                case .color: colors[NookColorID(rawValue: id)] = try container.decode(NookColorValue.self, forKey: key)
                case .dimension:
                    dimensions[NookDimensionID(rawValue: id)] = try container.decode(NookDimension.self, forKey: key)
                case .font: fonts[NookFontID(rawValue: id)] = try container.decode(NookFontSpec.self, forKey: key)
                case .animation:
                    animations[NookAnimationID(rawValue: id)] = try container.decode(
                        NookAnimationSpec.self,
                        forKey: key
                    )
                case .transition:
                    transitions[NookTransitionID(rawValue: id)] = try container.decode(
                        NookContentTransitionSpec.self,
                        forKey: key
                    )
                case .sound: sounds[NookSoundID(rawValue: id)] = try container.decode(NookSoundSpec.self, forKey: key)
                case .shadow:
                    shadows[NookShadowID(rawValue: id)] = try container.decode(NookShadowSpec.self, forKey: key)
            }
        }
    }
}

/// Token ids that were renamed or removed. A theme file that uses an old id still loads: a
/// renamed id is read as its new one, a removed id is skipped, and both are reported.
///
/// Every id the framework has ever shipped is listed in
/// `Tests/NookKitTests/Fixtures/theme-token-ids.txt`; a test fails when one of them is
/// neither defined nor listed here, so removing or renaming a token always means an entry
/// in ``map``.
enum NookTokenRenames {
    /// Old id to new id, or to `nil` for a token that was removed.
    static let map: [String: String?] = [:]

    /// The id `id` is read as today: itself, its new name, or `nil` when it was removed.
    static func currentID(for id: String, renames: [String: String?] = map) -> String? {
        var current = id
        var seen: Set<String> = [id]
        while let next = renames[current] {
            guard let next, seen.insert(next).inserted else { return nil }
            current = next
        }
        return current
    }
}
