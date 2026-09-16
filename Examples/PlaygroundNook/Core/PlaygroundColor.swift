// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import SwiftUI

/// An sRGB color the playground can store, export, and compare. `Color` itself is neither
/// `Codable` nor reliably comparable once it has been through a color picker.
///
/// Components are kept at 8 bits per channel, the precision of the `#RRGGBBAA` string it is
/// stored as, so a color survives a JSON round trip unchanged.
public struct PlaygroundColor: Hashable, Sendable {
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

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
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

    private static func byte(_ component: Double) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }

    private static func quantized(_ component: Double) -> Double {
        Double(byte(component)) / 255
    }
}

extension PlaygroundColor: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = PlaygroundColor(hex: string) else {
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
