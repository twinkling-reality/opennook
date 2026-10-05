// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Kai Azim - DynamicNotchKit (original)
// Copyright (c) 2026 Glendon Chin - OpenNook modifications
//
// Licensed under the MIT License.
// Original kit license: /ThirdPartyLicenses/DynamicNotchKit.txt
// Modifications license: /LICENSE-MIT-NOOKSURFACE

import AppKit
import SwiftUI

/// A peripheral cue the chrome can play along its perimeter - a one-shot signal the user
/// catches at the edge of vision without having to look directly at the notch.
///
/// Trigger one with ``Nook/playFeedback(_:tint:duration:repeats:)``, or
/// ``Nook/playFeedback(_:style:duration:repeats:)`` to restyle it. Modeled as an enum so
/// new effects can be added without reshaping call sites.
public enum NookFeedback: String, CaseIterable, Codable, Sendable {
    /// A bright band sweeping the chrome's perimeter from the leading to the trailing edge.
    /// The most legible peripheral cue against the dark notch arch - a moving highlight that
    /// grazes the eye without reading as a notification badge.
    case shimmer

    /// No peripheral feedback.
    case none

    /// The whole perimeter brightening and fading in place, with no sweep. Also what
    /// ``shimmer`` becomes under Reduce Motion.
    case pulse
}

/// How a peripheral feedback cue looks: its color, the band it sweeps, its line, its glow,
/// and how it blends with the chrome.
///
/// ``standard`` is the built-in look in the system accent color. The defaults read as added
/// light on a dark chrome; on a light chrome, pick a darker color and a `.normal`
/// ``blendMode``, since `.plusLighter` cannot darken.
///
/// ```swift
/// nook.playFeedback(.shimmer, style: NookFeedbackStyle(color: .green, glow: nil))
/// ```
public struct NookFeedbackStyle: Equatable, Sendable {
    /// The cue's color: the shimmer band's edges, the glow (unless ``Glow/color`` says
    /// otherwise), and the whole line for ``NookFeedback/pulse`` and under Reduce Motion.
    public var color: Color

    /// The bright center of the shimmer band. White at 75% by default; `nil` runs the band
    /// in ``color`` alone.
    public var coreColor: Color?

    /// A gradient that replaces the shimmer band's built-in stops, laid across the band from
    /// its leading to its trailing edge. Start and end it on `.clear` so the band has soft
    /// ends. `nil` (the default) builds the band from ``color`` and ``coreColor``.
    public var bandGradient: Gradient?

    /// The width of the stroke traced along the outline. The chrome clips the outer half, so
    /// the visible line is half this wide. 6 by default.
    public var lineWidth: CGFloat

    /// The line width used by ``NookFeedback/pulse`` and by the shimmer under Reduce Motion.
    /// 4 by default.
    public var pulseLineWidth: CGFloat

    /// A soft blurred stroke that swells with the cue, or `nil` for none.
    public var glow: Glow?

    /// How the cue composites over the chrome. `.plusLighter` (the default) adds light.
    public var blendMode: BlendMode

    /// A feedback look. Every parameter defaults to the built-in look; negative widths are
    /// treated as 0.
    public init(
        color: Color = Color(nsColor: .controlAccentColor),
        coreColor: Color? = .white.opacity(0.75),
        bandGradient: Gradient? = nil,
        lineWidth: CGFloat = 6,
        pulseLineWidth: CGFloat = 4,
        glow: Glow? = .standard,
        blendMode: BlendMode = .plusLighter
    ) {
        self.color = color
        self.coreColor = coreColor
        self.bandGradient = bandGradient
        self.lineWidth = max(lineWidth, 0)
        self.pulseLineWidth = max(pulseLineWidth, 0)
        self.glow = glow
        self.blendMode = blendMode
    }

    /// The built-in look, in the system accent color.
    public static let standard = NookFeedbackStyle()

    /// The soft blurred stroke behind a cue.
    public struct Glow: Equatable, Sendable {
        /// The glow's color, or `nil` (the default) for the style's color at 55%.
        public var color: Color?
        /// The stroke's width before the blur. 8 by default.
        public var width: CGFloat
        /// The blur radius. 3 by default.
        public var radius: CGFloat

        /// A glow `width` wide, blurred by `radius`, in `color` or the style's color.
        public init(color: Color? = nil, width: CGFloat = 8, radius: CGFloat = 3) {
            self.color = color
            self.width = max(width, 0)
            self.radius = max(radius, 0)
        }

        /// The built-in glow.
        public static let standard = Glow()
    }

    /// The colors of the shimmer band, leading edge to trailing edge.
    var resolvedBandGradient: Gradient {
        if let bandGradient { return bandGradient }
        let highlight = color.opacity(0.95)
        return Gradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: highlight, location: 0.42),
            .init(color: coreColor ?? highlight, location: 0.5),
            .init(color: highlight, location: 0.58),
            .init(color: .clear, location: 1.0),
        ])
    }

    /// The glow's color with its fallback applied.
    func resolvedGlowColor(_ glow: Glow) -> Color {
        glow.color ?? color.opacity(0.55)
    }
}
