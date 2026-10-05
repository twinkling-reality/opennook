// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import SwiftUI

/// A font weight a theme can store.
public enum NookFontWeight: String, Codable, Sendable, CaseIterable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    /// The SwiftUI weight.
    public var weight: Font.Weight {
        switch self {
            case .ultraLight: .ultraLight
            case .thin: .thin
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            case .black: .black
        }
    }
}

/// A system font design a theme can store.
public enum NookFontDesign: String, Codable, Sendable, CaseIterable {
    case `default`
    case rounded
    case serif
    case monospaced

    /// The SwiftUI design.
    public var design: Font.Design {
        switch self {
            case .default: .default
            case .rounded: .rounded
            case .serif: .serif
            case .monospaced: .monospaced
        }
    }
}

/// A font width a theme can store.
public enum NookFontWidth: String, Codable, Sendable, CaseIterable {
    case compressed
    case condensed
    case standard
    case expanded

    /// The SwiftUI width.
    public var width: Font.Width {
        switch self {
            case .compressed: .compressed
            case .condensed: .condensed
            case .standard: .standard
            case .expanded: .expanded
        }
    }
}

/// A font in a theme: a size and the traits to draw it with, optionally starting from a
/// type role such as `type.body`.
///
/// In a theme file a font is `"{type.glyph}"` (a role as it is), or an object:
///
/// ```json
/// { "role": "type.body", "weight": "semibold" }
/// { "size": "{type.size.md}", "weight": "medium", "design": "rounded" }
/// { "size": 11, "family": "SF Mono", "monospacedDigits": true }
/// ```
///
/// A member left out comes from the role, if there is one. A size given as a number is at
/// the theme's scale 1: the theme's `scale` knob multiplies it.
public struct NookFontSpec: Equatable, Sendable {
    /// The type role this font starts from, such as `type.body`.
    public var role: NookFontID?
    /// The point size at scale 1, or a reference to a type size such as `type.size.md`.
    public var size: NookDimension?
    public var weight: NookFontWeight?
    /// A design that overrides the one the chrome cascades (the theme's `fontDesign`).
    public var design: NookFontDesign?
    public var width: NookFontWidth?
    /// A font family to use instead of the system font. A family that is not installed falls
    /// back to the system font.
    public var family: String?
    public var monospacedDigits: Bool?

    public init(
        role: NookFontID? = nil,
        size: NookDimension? = nil,
        weight: NookFontWeight? = nil,
        design: NookFontDesign? = nil,
        width: NookFontWidth? = nil,
        family: String? = nil,
        monospacedDigits: Bool? = nil
    ) {
        self.role = role
        self.size = size
        self.weight = weight
        self.design = design
        self.width = width
        self.family = family
        self.monospacedDigits = monospacedDigits
    }

    /// A font that is a type role, unchanged.
    public static func role(_ role: NookFontID) -> NookFontSpec {
        NookFontSpec(role: role)
    }
}

extension NookFontSpec: Codable {
    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) {
            guard let id = nookParseReference(string) else {
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription:
                        "expected a type role such as \"{type.body}\" or a font object, found \"\(string)\""
                )
            }
            self.init(role: NookFontID(rawValue: id))
            return
        }
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let role = try container.optional(String.self, "role").map {
            NookFontID(rawValue: nookParseReference($0) ?? $0)
        }
        self.init(
            role: role,
            size: try container.optional(NookDimension.self, "size"),
            weight: try container.optional(NookFontWeight.self, "weight"),
            design: try container.optional(NookFontDesign.self, "design"),
            width: try container.optional(NookFontWidth.self, "width"),
            family: try container.optional(String.self, "family"),
            monospacedDigits: try container.optional(Bool.self, "monospacedDigits")
        )
    }

    public func encode(to encoder: any Encoder) throws {
        if let role, self == NookFontSpec(role: role) {
            var container = encoder.singleValueContainer()
            try container.encode(nookReferenceString(role.rawValue))
            return
        }
        var container = encoder.container(keyedBy: NookCodingKey.self)
        try container.putIfPresent(role?.rawValue, "role")
        try container.putIfPresent(size, "size")
        try container.putIfPresent(weight, "weight")
        try container.putIfPresent(design, "design")
        try container.putIfPresent(width, "width")
        try container.putIfPresent(family, "family")
        try container.putIfPresent(monospacedDigits, "monospacedDigits")
    }
}

/// A font whose size and traits are settled: no role or reference left to look up.
struct NookResolvedFontSpec: Equatable, Sendable {
    var size: Double
    var weight: NookFontWeight?
    var design: NookFontDesign?
    var width: NookFontWidth?
    var family: String?
    var monospacedDigits: Bool?

    /// The SwiftUI font, built with the same call the framework's default fonts use, so the
    /// default fonts come out equal to the ones written by hand: `.system(size:)` with no
    /// weight, `.system(size:weight:)` with one, `.system(size:weight:design:)` with a design.
    var font: Font {
        let pointSize = CGFloat(size)
        var font: Font
        if let family {
            font = .custom(family, size: pointSize)
            if let weight { font = font.weight(weight.weight) }
        } else if let design {
            font = .system(size: pointSize, weight: (weight ?? .regular).weight, design: design.design)
        } else if let weight {
            font = .system(size: pointSize, weight: weight.weight)
        } else {
            font = .system(size: pointSize)
        }
        if let width { font = font.width(width.width) }
        if monospacedDigits == true { font = font.monospacedDigit() }
        return font
    }
}
