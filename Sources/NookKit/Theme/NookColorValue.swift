// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import Foundation
import SwiftUI

/// An sRGB color stored at 8 bits per channel, written as `#RRGGBB` or `#RRGGBBAA`.
///
/// Components are quantized to the precision of the hex string, so a color survives a JSON
/// round trip unchanged. For full precision use ``NookColorValue/srgb(red:green:blue:opacity:)``.
public struct NookRGBA: Hashable, Sendable {
    public private(set) var red: Double
    public private(set) var green: Double
    public private(set) var blue: Double
    public private(set) var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = Self.quantized(red)
        self.green = Self.quantized(green)
        self.blue = Self.quantized(blue)
        self.opacity = Self.quantized(opacity)
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA`, with or without the leading `#`.
    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        // `UInt32(_:radix:)` alone would also take a sign, so check the digits first.
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
            let value = UInt32(digits, radix: 16)
        else {
            return nil
        }
        let bytes = digits.count == 8 ? value : value << 8 | 0xFF
        self.init(
            red: Double(bytes >> 24 & 0xFF) / 255,
            green: Double(bytes >> 16 & 0xFF) / 255,
            blue: Double(bytes >> 8 & 0xFF) / 255,
            opacity: Double(bytes & 0xFF) / 255
        )
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the color is not fully opaque.
    public var hex: String {
        let channels = opacity < 1 ? [red, green, blue, opacity] : [red, green, blue]
        return "#"
            + channels.map { channel in
                let digits = String(Self.byte(channel), radix: 16, uppercase: true)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
    }

    /// The color, in the sRGB color space.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    private static func byte(_ component: Double) -> Int {
        guard component.isFinite else { return 0 }
        return Int((min(max(component, 0), 1) * 255).rounded())
    }

    private static func quantized(_ component: Double) -> Double {
        Double(byte(component)) / 255
    }
}

extension NookRGBA: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = NookRGBA(hex: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "expected a color such as \"#3F8CFA\", found \"\(string)\""
            )
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// A named system color. These adapt to the system appearance, so the framework uses them
/// only where it already did (the status colors); prefer explicit colors elsewhere.
public enum NookSystemColor: String, Codable, Sendable, CaseIterable {
    /// The macOS accent color the person picked in System Settings (`controlAccentColor`).
    case controlAccent
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray

    /// The SwiftUI color.
    public var color: Color {
        switch self {
            case .controlAccent: Color(nsColor: .controlAccentColor)
            case .red: .red
            case .orange: .orange
            case .yellow: .yellow
            case .green: .green
            case .blue: .blue
            case .purple: .purple
            case .pink: .pink
            case .gray: .gray
        }
    }
}

/// The levels of a hierarchical label style. Reserved: see
/// ``NookColorValue/hierarchical(_:)``.
public enum NookHierarchicalLevel: String, Codable, Sendable, CaseIterable {
    case primary
    case secondary
    case tertiary
    case quaternary

    /// The label role a hierarchical color resolves to today.
    public var labelRole: NookColorID {
        switch self {
            case .primary: "color.label.primary"
            case .secondary: "color.label.secondary"
            case .tertiary: "color.label.tertiary"
            case .quaternary: "color.label.quaternary"
        }
    }
}

/// A color in a theme: a literal, a reference to another color token, or a pair that
/// adapts to the chrome's appearance.
///
/// In a theme file a color is written as:
///
/// - `"#3399FF"` or `"#3399FFCC"`: an 8-bit sRGB color.
/// - `{"white": 0.95}` / `{"black": 0.88}`: white or black at an opacity, the explicit form
///   the framework's own palette uses.
/// - `{"srgb": [0.2, 0.78, 0.73], "opacity": 1}`: sRGB at full precision.
/// - `{"system": "red"}`: a ``NookSystemColor``.
/// - `"accent"`: the host's accent, whatever it resolves to. The placeholder a third party
///   uses to say "use the host accent".
/// - `"{color.label.primary}"` or `{"ref": "color.accent", "opacity": 0.6}`: another color
///   token, optionally at an opacity.
/// - `{"dark": ..., "light": ...}`: a ``NookAdaptiveColor``.
///
/// A string literal in Swift takes the same forms: `let accent: NookColorValue = "#3399FF"`.
public indirect enum NookColorValue: Equatable, Sendable {
    /// An 8-bit sRGB color.
    case hex(NookRGBA)
    /// sRGB at full precision, built with `Color(red:green:blue:opacity:)`.
    case srgb(red: Double, green: Double, blue: Double, opacity: Double)
    /// `Color.white` at `opacity` (`Color.white` itself at 1).
    case white(opacity: Double)
    /// `Color.black` at `opacity` (`Color.black` itself at 1).
    case black(opacity: Double)
    /// A named system color.
    case system(NookSystemColor)
    /// Another color token, multiplied by `opacity` when one is given.
    case reference(NookColorID, opacity: Double?)
    /// A color that differs between dark and light chrome, and optionally on a solid surface.
    case adaptive(NookAdaptiveColor)
    /// Reserved. A hierarchical label style (`.primary`, `.secondary`, ...) would only render
    /// with vibrancy if the chrome's content were drawn inside its material, which it is not:
    /// the backdrop is a sibling behind the content. Until that changes this resolves to the
    /// matching explicit label role's default, ``NookHierarchicalLevel/labelRole``, and a theme file that
    /// uses it gets a warning.
    case hierarchical(NookHierarchicalLevel)

    /// The theme's accent, whatever it resolves to (`"accent"` in a theme file).
    public static let accent = NookColorValue.reference("color.accent", opacity: nil)

    /// The macOS accent color (`controlAccentColor`), the framework's default accent.
    public static let systemAccent = NookColorValue.system(.controlAccent)

    /// Parses the string forms: `#RRGGBB[AA]`, `accent`, `white`, `black`, and `{token.id}`.
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed == "accent" {
            self = .accent
        } else if trimmed == "white" {
            self = .white(opacity: 1)
        } else if trimmed == "black" {
            self = .black(opacity: 1)
        } else if let id = nookParseReference(trimmed) {
            self = .reference(NookColorID(rawValue: id), opacity: nil)
        } else if let rgba = NookRGBA(hex: trimmed) {
            self = .hex(rgba)
        } else {
            return nil
        }
    }
}

extension NookColorValue: ExpressibleByStringLiteral {
    /// A color from a string literal in one of the forms ``init(string:)`` reads. Traps on any
    /// other text, since a literal is a programming error caught the first time it runs.
    public init(stringLiteral value: String) {
        guard let color = NookColorValue(string: value) else {
            preconditionFailure(
                "NookColorValue: \"\(value)\" is not a color. Use \"#RRGGBB\", \"accent\", or \"{token.id}\"."
            )
        }
        self = color
    }
}

extension NookColorValue: Codable {
    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) {
            guard let color = NookColorValue(string: string) else {
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "expected a color such as \"#3F8CFA\", \"accent\", or \"{color.accent}\", "
                        + "found \"\(string)\""
                )
            }
            self = color
            return
        }
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        if let opacity = try container.optional(Double.self, "white") {
            self = .white(opacity: opacity)
        } else if let opacity = try container.optional(Double.self, "black") {
            self = .black(opacity: opacity)
        } else if let components = try container.optional([Double].self, "srgb") {
            guard components.count == 3 else {
                throw DecodingError.dataCorruptedError(
                    forKey: NookCodingKey("srgb"),
                    in: container,
                    debugDescription: "expected three components, red, green, and blue"
                )
            }
            let opacity = try container.optional(Double.self, "opacity") ?? 1
            self = .srgb(red: components[0], green: components[1], blue: components[2], opacity: opacity)
        } else if let system = try container.optional(NookSystemColor.self, "system") {
            self = .system(system)
        } else if let reference = try container.optional(String.self, "ref") {
            let id = nookParseReference(reference) ?? reference
            self = .reference(NookColorID(rawValue: id), opacity: try container.optional(Double.self, "opacity"))
        } else if let level = try container.optional(NookHierarchicalLevel.self, "hierarchical") {
            self = .hierarchical(level)
        } else if container.has("dark") || container.has("light") {
            self = .adaptive(try NookAdaptiveColor(from: decoder))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "expected a color: a \"#RRGGBB\" string, or an object with \"white\", "
                        + "\"black\", \"srgb\", \"system\", \"ref\", or \"dark\" and \"light\""
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
            case .hex(let rgba):
                var container = encoder.singleValueContainer()
                try container.encode(rgba.hex)
            case .srgb(let red, let green, let blue, let opacity):
                var container = encoder.container(keyedBy: NookCodingKey.self)
                try container.put([red, green, blue], "srgb")
                if opacity != 1 { try container.put(opacity, "opacity") }
            case .white(let opacity):
                var container = encoder.container(keyedBy: NookCodingKey.self)
                try container.put(opacity, "white")
            case .black(let opacity):
                var container = encoder.container(keyedBy: NookCodingKey.self)
                try container.put(opacity, "black")
            case .system(let system):
                var container = encoder.container(keyedBy: NookCodingKey.self)
                try container.put(system, "system")
            case .reference(let id, let opacity):
                if let opacity {
                    var container = encoder.container(keyedBy: NookCodingKey.self)
                    try container.put(id.rawValue, "ref")
                    try container.put(opacity, "opacity")
                } else {
                    var container = encoder.singleValueContainer()
                    try container.encode(self == .accent ? "accent" : nookReferenceString(id.rawValue))
                }
            case .adaptive(let adaptive):
                try adaptive.encode(to: encoder)
            case .hierarchical(let level):
                var container = encoder.container(keyedBy: NookCodingKey.self)
                try container.put(level, "hierarchical")
        }
    }
}

/// A color that differs between dark and light chrome.
///
/// The `solid` variants apply when the person picked the solid surface; the
/// `reducedTransparency` variants when Reduce Transparency forces a translucent surface solid.
/// Each falls back to the plain variant for its appearance (a reduced-transparency variant
/// falls back to the solid one first). This is how the framework's subtle fill gets a touch
/// more contrast on an opaque panel.
public struct NookAdaptiveColor: Equatable, Sendable, Codable {
    public var dark: NookColorValue
    public var light: NookColorValue
    public var darkSolid: NookColorValue?
    public var lightSolid: NookColorValue?
    public var darkReducedTransparency: NookColorValue?
    public var lightReducedTransparency: NookColorValue?

    public init(
        dark: NookColorValue,
        light: NookColorValue,
        darkSolid: NookColorValue? = nil,
        lightSolid: NookColorValue? = nil,
        darkReducedTransparency: NookColorValue? = nil,
        lightReducedTransparency: NookColorValue? = nil
    ) {
        self.dark = dark
        self.light = light
        self.darkSolid = darkSolid
        self.lightSolid = lightSolid
        self.darkReducedTransparency = darkReducedTransparency
        self.lightReducedTransparency = lightReducedTransparency
    }

    /// The variant for an appearance: `isDark`, whether the person picked the solid surface,
    /// and whether Reduce Transparency is on.
    public func variant(isDark: Bool, isSolidSurface: Bool, reduceTransparency: Bool) -> NookColorValue {
        let base = isDark ? dark : light
        let solid = isDark ? darkSolid : lightSolid
        if isSolidSurface { return solid ?? base }
        if reduceTransparency {
            return (isDark ? darkReducedTransparency : lightReducedTransparency) ?? solid ?? base
        }
        return base
    }
}
