// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import SwiftUI

// MARK: - Dimension

/// A number in a theme: a length in points, an opacity multiplier, or a duration in seconds,
/// given as a value or as a reference to another numeric token.
///
/// In a theme file: `12`, `"{radius.lg}"`, or `{"ref": "space.md", "times": 1.5}`.
///
/// Numbers are written at the theme's scale 1. A token whose kind scales (spacing and type
/// with the theme's `scale`, radii with its `radius`) multiplies a number given for it; a
/// reference takes the other token's value, already scaled.
public enum NookDimension: Equatable, Sendable {
    case points(Double)
    case reference(NookDimensionID, times: Double)

    /// A reference to `id`, unmultiplied.
    public static func token(_ id: NookDimensionID) -> NookDimension {
        .reference(id, times: 1)
    }
}

extension NookDimension: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public init(floatLiteral value: Double) {
        self = .points(value)
    }

    public init(integerLiteral value: Int) {
        self = .points(Double(value))
    }
}

extension NookDimension: Codable {
    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let number = try? single.decode(Double.self) {
            self = .points(number)
            return
        }
        if let string = try? single.decode(String.self) {
            guard let id = nookParseReference(string) else {
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "expected a number or a token such as \"{space.md}\", found \"\(string)\""
                )
            }
            self = .reference(NookDimensionID(rawValue: id), times: 1)
            return
        }
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let reference = try container.required(String.self, "ref")
        self = .reference(
            NookDimensionID(rawValue: nookParseReference(reference) ?? reference),
            times: try container.optional(Double.self, "times") ?? 1
        )
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
            case .points(let value):
                var container = encoder.singleValueContainer()
                try container.encode(value)
            case .reference(let id, let times):
                if times == 1 {
                    var container = encoder.singleValueContainer()
                    try container.encode(nookReferenceString(id.rawValue))
                } else {
                    var container = encoder.container(keyedBy: NookCodingKey.self)
                    try container.put(id.rawValue, "ref")
                    try container.put(times, "times")
                }
        }
    }
}

// MARK: - Adaptive number

/// A number that may differ between dark and light chrome: `0.3` or
/// `{"dark": 0.52, "light": 0.10}` in a theme file.
public struct NookAdaptiveNumber: Equatable, Sendable {
    public var dark: Double
    public var light: Double

    public init(dark: Double, light: Double) {
        self.dark = dark
        self.light = light
    }

    /// The same number for both appearances.
    public init(_ value: Double) {
        self.init(dark: value, light: value)
    }

    public func value(isDark: Bool) -> Double {
        isDark ? dark : light
    }
}

extension NookAdaptiveNumber: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public init(floatLiteral value: Double) { self.init(value) }
    public init(integerLiteral value: Int) { self.init(Double(value)) }
}

extension NookAdaptiveNumber: Codable {
    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let number = try? single.decode(Double.self) {
            self.init(number)
            return
        }
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        self.init(
            dark: try container.required(Double.self, "dark"),
            light: try container.required(Double.self, "light")
        )
    }

    public func encode(to encoder: any Encoder) throws {
        if dark == light {
            var container = encoder.singleValueContainer()
            try container.encode(dark)
        } else {
            var container = encoder.container(keyedBy: NookCodingKey.self)
            try container.put(dark, "dark")
            try container.put(light, "light")
        }
    }
}

// MARK: - Unit point

/// A point in a view's unit square: `"top"`, `"bottomTrailing"`, ... or `{"x": 0.5, "y": 0}`
/// in a theme file.
public struct NookUnitPointSpec: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = NookUnitPointSpec(x: 0, y: 0)
    public static let center = NookUnitPointSpec(x: 0.5, y: 0.5)
    public static let leading = NookUnitPointSpec(x: 0, y: 0.5)
    public static let trailing = NookUnitPointSpec(x: 1, y: 0.5)
    public static let top = NookUnitPointSpec(x: 0.5, y: 0)
    public static let bottom = NookUnitPointSpec(x: 0.5, y: 1)
    public static let topLeading = NookUnitPointSpec(x: 0, y: 0)
    public static let topTrailing = NookUnitPointSpec(x: 1, y: 0)
    public static let bottomLeading = NookUnitPointSpec(x: 0, y: 1)
    public static let bottomTrailing = NookUnitPointSpec(x: 1, y: 1)

    /// The named points, by the name a theme file uses.
    static let named: [(name: String, point: NookUnitPointSpec)] = [
        ("center", .center), ("leading", .leading), ("trailing", .trailing), ("top", .top), ("bottom", .bottom),
        ("topLeading", .topLeading), ("topTrailing", .topTrailing), ("bottomLeading", .bottomLeading),
        ("bottomTrailing", .bottomTrailing),
    ]

    /// The SwiftUI unit point.
    public var unitPoint: UnitPoint {
        UnitPoint(x: x, y: y)
    }
}

extension NookUnitPointSpec: Codable {
    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let name = try? single.decode(String.self) {
            guard let match = Self.named.first(where: { $0.name == name }) else {
                let names = Self.named.map(\.name).joined(separator: ", ")
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "expected one of \(names), or an object with \"x\" and \"y\"; found \"\(name)\""
                )
            }
            self = match.point
            return
        }
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        self.init(x: try container.required(Double.self, "x"), y: try container.required(Double.self, "y"))
    }

    public func encode(to encoder: any Encoder) throws {
        if let match = Self.named.first(where: { $0.point == self }) {
            var container = encoder.singleValueContainer()
            try container.encode(match.name)
        } else {
            var container = encoder.container(keyedBy: NookCodingKey.self)
            try container.put(x, "x")
            try container.put(y, "y")
        }
    }
}

// MARK: - Gradient

/// A gradient: colors at locations from 0 to 1.
///
/// In a theme file, a list of colors spread evenly (`["#101014", "#000000"]`) or of stops
/// (`[{"color": "#101014", "location": 0}, {"color": {"black": 1}, "location": 0.8}]`).
public struct NookGradientSpec: Equatable, Sendable {
    public struct Stop: Equatable, Sendable {
        public var color: NookColorValue
        /// 0...1, or `nil` to spread the stops without one evenly.
        public var location: Double?

        public init(color: NookColorValue, location: Double? = nil) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// Colors spread evenly from 0 to 1.
    public init(colors: [NookColorValue]) {
        self.init(stops: colors.map { Stop(color: $0) })
    }

    /// Each stop's location, with missing ones spread evenly from 0 to 1.
    public var resolvedLocations: [Double] {
        let count = stops.count
        return stops.enumerated().map { index, stop in
            stop.location ?? (count > 1 ? Double(index) / Double(count - 1) : 0)
        }
    }
}

extension NookGradientSpec.Stop: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: NookCodingKey.self), container.has("color") {
            self.init(
                color: try container.required(NookColorValue.self, "color"),
                location: try container.optional(Double.self, "location")
            )
        } else {
            self.init(color: try NookColorValue(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        guard let location else {
            try color.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: NookCodingKey.self)
        try container.put(color, "color")
        try container.put(location, "location")
    }
}

extension NookGradientSpec: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: NookCodingKey.self), container.has("stops") {
            self.init(stops: try container.required([Stop].self, "stops"))
        } else {
            self.init(stops: try [Stop](from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try stops.encode(to: encoder)
    }
}

// MARK: - Shadow

/// A shadow cast by a surface's outline.
///
/// In a theme file: `{"color": {"black": 0.35}, "radius": 8, "x": 0, "y": 3}`.
public struct NookShadowSpec: Equatable, Sendable {
    public var color: NookColorValue
    public var radius: Double
    public var x: Double
    public var y: Double

    public init(color: NookColorValue = .black(opacity: 0.35), radius: Double = 8, x: Double = 0, y: Double = 3) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

extension NookShadowSpec: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let fallback = NookShadowSpec()
        self.init(
            color: try container.optional(NookColorValue.self, "color") ?? fallback.color,
            radius: try container.optional(Double.self, "radius") ?? fallback.radius,
            x: try container.optional(Double.self, "x") ?? fallback.x,
            y: try container.optional(Double.self, "y") ?? fallback.y
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        try container.put(color, "color")
        try container.put(radius, "radius")
        if x != 0 { try container.put(x, "x") }
        try container.put(y, "y")
    }
}

// MARK: - Sound

/// A sound a theme plays for a chrome event. Describes the sound only; nothing plays it yet.
///
/// In a theme file:
///
/// ```json
/// { "system": "Glass", "volume": 0.6 }        // NSSound(named:) - a system sound by name
/// { "resource": "pop.caf" }                   // a resource in the app's main bundle
/// { "file": "/Users/me/Sounds/pop.caf" }      // a file path or file URL
/// ```
public struct NookSoundSpec: Equatable, Sendable {
    /// Where the sound comes from.
    public enum Source: Equatable, Sendable {
        /// A system sound, looked up with `NSSound(named:)`, such as `"Glass"` or `"Pop"`.
        case system(String)
        /// A resource in the app's main bundle, by file name.
        case resource(String)
        /// A sound file.
        case file(URL)
    }

    public var source: Source
    /// 0...1, multiplied by the theme's `soundVolume`. `nil` is full volume.
    public var volume: Double?

    public init(_ source: Source, volume: Double? = nil) {
        self.source = source
        self.volume = volume
    }

    /// A system sound by name.
    public static func system(_ name: String, volume: Double? = nil) -> NookSoundSpec {
        NookSoundSpec(.system(name), volume: volume)
    }

    /// The volume to play at under a theme whose `soundVolume` is `masterVolume`, 0...1.
    public func effectiveVolume(masterVolume: Double) -> Double {
        let own = volume ?? 1
        let product = (own.isFinite ? own : 1) * (masterVolume.isFinite ? masterVolume : 1)
        return min(max(product, 0), 1)
    }
}

extension NookSoundSpec: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let volume = try container.optional(Double.self, "volume")
        if let name = try container.optional(String.self, "system") {
            self.init(.system(name), volume: volume)
        } else if let name = try container.optional(String.self, "resource") {
            self.init(.resource(name), volume: volume)
        } else if let path = try container.optional(String.self, "file") {
            let url = path.hasPrefix("file:") ? URL(string: path) : URL(fileURLWithPath: path)
            guard let url else {
                throw DecodingError.dataCorruptedError(
                    forKey: NookCodingKey("file"),
                    in: container,
                    debugDescription: "expected a file path or a file URL, found \"\(path)\""
                )
            }
            self.init(.file(url), volume: volume)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "expected a sound: an object with \"system\", \"resource\", or \"file\""
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        switch source {
            case .system(let name): try container.put(name, "system")
            case .resource(let name): try container.put(name, "resource")
            case .file(let url): try container.put(url.isFileURL ? url.path : url.absoluteString, "file")
        }
        try container.putIfPresent(volume, "volume")
    }
}
