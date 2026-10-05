// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import SwiftUI

/// One of SwiftUI's named springs.
public enum NookSpringPreset: String, Codable, Sendable, CaseIterable {
    case smooth
    case snappy
    case bouncy
}

/// A timing curve.
public enum NookTimingCurve: String, Codable, Sendable, CaseIterable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
}

/// How springy a theme's motion is: the theme's `motion` knob.
///
/// It transforms every spring the theme resolves. ``standard`` leaves them exactly as
/// written. Timing curves are never changed.
public enum NookMotionScheme: String, Codable, Sendable, CaseIterable {
    /// The springs as written.
    case standard
    /// No overshoot: damping raised to at least critical, bounce to at most zero, and the
    /// named springs drawn as `.smooth`.
    case calm
    /// More overshoot: damping lowered by a fifth, bounce raised.
    case expressive
}

/// An animation in a theme.
///
/// In a theme file:
///
/// ```json
/// { "response": 0.38, "dampingFraction": 0.84 }                 // .spring(response:dampingFraction:)
/// { "response": 0.52, "dampingFraction": 0.88, "blendDuration": 0.12 }
/// { "duration": 0.4, "bounce": 0.15 }                            // .spring(duration:bounce:)
/// { "preset": "snappy", "duration": 0.4, "extraBounce": 0 }      // .snappy(duration:extraBounce:)
/// { "curve": "easeOut", "duration": 0.18 }                       // .easeOut(duration:)
/// { "bezier": [0.2, 0, 0, 1], "duration": 0.3 }                  // .timingCurve
/// "{spring.default}"                                             // another animation token
/// ```
public indirect enum NookAnimationSpec: Equatable, Sendable {
    case spring(response: Double, dampingFraction: Double, blendDuration: Double = 0)
    case springDuration(duration: Double, bounce: Double)
    case preset(NookSpringPreset, duration: Double, extraBounce: Double = 0)
    case curve(NookTimingCurve, duration: Double)
    case bezier(x1: Double, y1: Double, x2: Double, y2: Double, duration: Double)
    case reference(NookAnimationID)

    /// The SwiftUI animation, after `scheme` is applied, or `nil` for a reference, which
    /// only a theme can look up.
    ///
    /// A spring with no blend duration is built with `.spring(response:dampingFraction:)`,
    /// the call the framework's defaults are written with, so they come out equal.
    public func animation(scheme: NookMotionScheme = .standard) -> Animation? {
        switch scheme.applied(to: self) {
            case .spring(let response, let damping, let blend):
                if blend == 0 {
                    return .spring(response: response, dampingFraction: damping)
                }
                return .spring(response: response, dampingFraction: damping, blendDuration: blend)
            case .springDuration(let duration, let bounce):
                return .spring(duration: duration, bounce: bounce)
            case .preset(let preset, let duration, let extraBounce):
                switch preset {
                    case .smooth: return .smooth(duration: duration, extraBounce: extraBounce)
                    case .snappy: return .snappy(duration: duration, extraBounce: extraBounce)
                    case .bouncy: return .bouncy(duration: duration, extraBounce: extraBounce)
                }
            case .curve(let curve, let duration):
                switch curve {
                    case .linear: return .linear(duration: duration)
                    case .easeIn: return .easeIn(duration: duration)
                    case .easeOut: return .easeOut(duration: duration)
                    case .easeInOut: return .easeInOut(duration: duration)
                }
            case .bezier(let x1, let y1, let x2, let y2, let duration):
                return .timingCurve(x1, y1, x2, y2, duration: duration)
            case .reference:
                return nil
        }
    }

    /// The longest time the animation runs, in seconds, where it can be known: the duration
    /// for a timed curve or a duration spring, the response for a response spring.
    public var nominalDuration: Double? {
        switch self {
            case .spring(let response, _, _): response
            case .springDuration(let duration, _): duration
            case .preset(_, let duration, _): duration
            case .curve(_, let duration): duration
            case .bezier(_, _, _, _, let duration): duration
            case .reference: nil
        }
    }
}

extension NookMotionScheme {
    /// `spec` with this scheme applied. ``standard`` returns it unchanged.
    func applied(to spec: NookAnimationSpec) -> NookAnimationSpec {
        switch self {
            case .standard:
                return spec
            case .calm:
                switch spec {
                    case .spring(let response, let damping, let blend):
                        return .spring(response: response, dampingFraction: max(damping, 1), blendDuration: blend)
                    case .springDuration(let duration, let bounce):
                        return .springDuration(duration: duration, bounce: min(bounce, 0))
                    case .preset(_, let duration, let extraBounce):
                        return .preset(.smooth, duration: duration, extraBounce: min(extraBounce, 0))
                    default:
                        return spec
                }
            case .expressive:
                switch spec {
                    case .spring(let response, let damping, let blend):
                        return .spring(
                            response: response,
                            dampingFraction: max(damping * 0.8, 0.3),
                            blendDuration: blend
                        )
                    case .springDuration(let duration, let bounce):
                        return .springDuration(duration: duration, bounce: min(bounce + 0.15, 0.9))
                    case .preset(let preset, let duration, let extraBounce):
                        return .preset(preset, duration: duration, extraBounce: min(extraBounce + 0.1, 0.5))
                    default:
                        return spec
                }
        }
    }
}

extension NookAnimationSpec: Codable {
    public init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let string = try? single.decode(String.self) {
            guard let id = nookParseReference(string) else {
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "expected an animation token such as \"{spring.default}\" or an animation "
                        + "object, found \"\(string)\""
                )
            }
            self = .reference(NookAnimationID(rawValue: id))
            return
        }
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        if let response = try container.optional(Double.self, "response") {
            self = .spring(
                response: response,
                dampingFraction: try container.optional(Double.self, "dampingFraction") ?? 0.825,
                blendDuration: try container.optional(Double.self, "blendDuration") ?? 0
            )
        } else if let preset = try container.optional(NookSpringPreset.self, "preset") {
            self = .preset(
                preset,
                duration: try container.optional(Double.self, "duration") ?? 0.5,
                extraBounce: try container.optional(Double.self, "extraBounce") ?? 0
            )
        } else if let curve = try container.optional(NookTimingCurve.self, "curve") {
            self = .curve(curve, duration: try container.optional(Double.self, "duration") ?? 0.35)
        } else if let points = try container.optional([Double].self, "bezier") {
            guard points.count == 4 else {
                throw DecodingError.dataCorruptedError(
                    forKey: NookCodingKey("bezier"),
                    in: container,
                    debugDescription: "expected four control point values, x1, y1, x2, y2"
                )
            }
            self = .bezier(
                x1: points[0],
                y1: points[1],
                x2: points[2],
                y2: points[3],
                duration: try container.optional(Double.self, "duration") ?? 0.35
            )
        } else if let duration = try container.optional(Double.self, "duration") {
            self = .springDuration(duration: duration, bounce: try container.optional(Double.self, "bounce") ?? 0)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "expected an animation: an object with \"response\", \"duration\", "
                        + "\"preset\", \"curve\", or \"bezier\""
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if case .reference(let id) = self {
            var container = encoder.singleValueContainer()
            try container.encode(nookReferenceString(id.rawValue))
            return
        }
        var container = encoder.container(keyedBy: NookCodingKey.self)
        switch self {
            case .spring(let response, let damping, let blend):
                try container.put(response, "response")
                try container.put(damping, "dampingFraction")
                if blend != 0 { try container.put(blend, "blendDuration") }
            case .springDuration(let duration, let bounce):
                try container.put(duration, "duration")
                try container.put(bounce, "bounce")
            case .preset(let preset, let duration, let extraBounce):
                try container.put(preset, "preset")
                try container.put(duration, "duration")
                if extraBounce != 0 { try container.put(extraBounce, "extraBounce") }
            case .curve(let curve, let duration):
                try container.put(curve, "curve")
                try container.put(duration, "duration")
            case .bezier(let x1, let y1, let x2, let y2, let duration):
                try container.put([x1, y1, x2, y2], "bezier")
                try container.put(duration, "duration")
            case .reference:
                break
        }
    }
}

/// How content leaves or enters the chrome: the state it animates from (entering) or to
/// (leaving), and the curve.
///
/// The framework's expanded content today fades, blurs by 6, and shrinks vertically to 72%
/// from the top edge, on the surface's own expand and collapse curve; that is
/// ``expandedContentDefault``. A theme describes another, for example:
///
/// ```json
/// "motion.content.exit":  { "opacity": 0, "blur": 8, "scale": 0.97, "animation": { "curve": "easeOut", "duration": 0.16 } },
/// "motion.content.enter": { "opacity": 0, "blur": 8, "scale": 0.97, "animation": { "curve": "easeOut", "duration": 0.3 } },
/// "motion.content.enterDelay": 0.16, "motion.header.delay": 0.3, "motion.stagger": 0.035
/// ```
public struct NookContentTransitionSpec: Equatable, Sendable {
    /// Opacity at the hidden end, 0...1.
    public var opacity: Double
    /// Blur radius at the hidden end, in points.
    public var blur: Double
    public var scaleX: Double
    public var scaleY: Double
    /// The point scaling is anchored to.
    public var anchor: NookUnitPointSpec
    public var offsetX: Double
    public var offsetY: Double
    /// The curve. `nil` follows the surface's own expand and collapse curve.
    public var animation: NookAnimationSpec?

    public init(
        opacity: Double = 0,
        blur: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        anchor: NookUnitPointSpec = .center,
        offsetX: Double = 0,
        offsetY: Double = 0,
        animation: NookAnimationSpec? = nil
    ) {
        self.opacity = opacity
        self.blur = blur
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.anchor = anchor
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.animation = animation
    }

    /// Today's expanded content transition: fade, blur 6, vertical scale 0.72 from the top,
    /// on the surface's curve (`NookView`'s expanded content transition).
    public static let expandedContentDefault = NookContentTransitionSpec(
        opacity: 0,
        blur: 6,
        scaleY: 0.72,
        anchor: .top
    )

    /// Today's compact slot transition: fade, blur 6, horizontal scale from 0, on the
    /// surface's curve (`NookContentTransition.standardCompact`).
    public static let compactContentDefault = NookContentTransitionSpec(
        opacity: 0,
        blur: 6,
        scaleX: 0
    )

    /// The peek content's transition: fade, blur 4, vertical scale 0.9 from the top, on the
    /// peek curve (`NookContentTransition.standardPeek`).
    public static let peekContentDefault = NookContentTransitionSpec(
        opacity: 0,
        blur: 4,
        scaleY: 0.9,
        anchor: .top
    )
}

extension NookContentTransitionSpec: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let scale = try container.optional(Double.self, "scale")
        self.init(
            opacity: try container.optional(Double.self, "opacity") ?? 0,
            blur: try container.optional(Double.self, "blur") ?? 0,
            scaleX: try container.optional(Double.self, "scaleX") ?? scale ?? 1,
            scaleY: try container.optional(Double.self, "scaleY") ?? scale ?? 1,
            anchor: try container.optional(NookUnitPointSpec.self, "anchor") ?? .center,
            offsetX: try container.optional(Double.self, "offsetX") ?? 0,
            offsetY: try container.optional(Double.self, "offsetY") ?? 0,
            animation: try container.optional(NookAnimationSpec.self, "animation")
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        try container.put(opacity, "opacity")
        if blur != 0 { try container.put(blur, "blur") }
        if scaleX == scaleY {
            if scaleX != 1 { try container.put(scaleX, "scale") }
        } else {
            try container.put(scaleX, "scaleX")
            try container.put(scaleY, "scaleY")
        }
        if anchor != .center { try container.put(anchor, "anchor") }
        if offsetX != 0 { try container.put(offsetX, "offsetX") }
        if offsetY != 0 { try container.put(offsetY, "offsetY") }
        try container.putIfPresent(animation, "animation")
    }
}
