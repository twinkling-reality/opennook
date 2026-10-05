// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// The stable, dotted name of one theme token, such as `banner.cornerRadius`.
///
/// Token ids are what a theme file is keyed by. They are deliberately not Swift property
/// names, so renaming a Swift property never breaks a theme someone has saved. Each kind of
/// token has its own id type (``NookColorID``, ``NookDimensionID``, ``NookFontID``,
/// ``NookAnimationID``, ``NookTransitionID``, ``NookSoundID``, ``NookShadowID``), so a color
/// cannot be stored where a length belongs.
public protocol NookTokenIdentifier: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
where RawValue == String {
    init(rawValue: String)
}

extension NookTokenIdentifier {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }
}

/// The id of a color token, such as `color.label.primary`.
public struct NookColorID: NookTokenIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The id of a numeric token: a length, an opacity multiplier, or a duration in seconds,
/// such as `space.md` or `banner.cornerRadius`.
public struct NookDimensionID: NookTokenIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The id of a font token, such as `type.body` or `banner.message.font`.
public struct NookFontID: NookTokenIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The id of an animation token, such as `spring.default` or `motion.statusBanner`.
public struct NookAnimationID: NookTokenIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The id of a content transition token, such as `motion.content.exit`.
public struct NookTransitionID: NookTokenIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The id of a sound token, such as `sound.open`.
public struct NookSoundID: NookTokenIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The id of a shadow token, such as `shadow.chrome`.
public struct NookShadowID: NookTokenIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Coding helpers

/// A coding key made from any string, for the open-ended objects a theme file contains.
struct NookCodingKey: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where Key == NookCodingKey {
    /// Whether the object has a member named `name`.
    func has(_ name: String) -> Bool {
        contains(NookCodingKey(name))
    }

    /// The member named `name` as `T`, or `nil` when it is absent or `null`. A value of the
    /// wrong type still throws, so a malformed file is reported rather than silently reset.
    func optional<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        try decodeIfPresent(type, forKey: NookCodingKey(name))
    }

    /// The member named `name` as `T`; throws when it is absent.
    func required<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try decode(type, forKey: NookCodingKey(name))
    }
}

extension KeyedEncodingContainer where Key == NookCodingKey {
    mutating func put<T: Encodable>(_ value: T, _ name: String) throws {
        try encode(value, forKey: NookCodingKey(name))
    }

    mutating func putIfPresent<T: Encodable>(_ value: T?, _ name: String) throws {
        try encodeIfPresent(value, forKey: NookCodingKey(name))
    }
}

/// Parses `"{some.token}"`, the alias form a theme file uses to point at another token.
func nookParseReference(_ string: String) -> String? {
    let trimmed = string.trimmingCharacters(in: .whitespaces)
    guard trimmed.count > 2, trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
    let inner = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
    return inner.isEmpty ? nil : inner
}

/// `"{id}"`, the alias form of `id`.
func nookReferenceString(_ id: String) -> String {
    "{\(id)}"
}
