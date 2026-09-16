// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the MIT License.
// See /LICENSE-MIT-NOOKSURFACE for the modifications license.

import SwiftUI

/// A SwiftUI preference that lets content light a glowing rim around the nook chrome - a
/// peripheral state signal, such as a blue rim while work is running.
///
/// This is the rim's counterpart to ``NookAmbientColorPreferenceKey`` and works the same
/// way: content publishes a color, the surface draws it, and the engine never learns why the
/// color was chosen. It differs in one respect. The ambient wash is read from expanded
/// content only, while the rim is read from everything the chrome hosts - the compact slots,
/// the expanded content, and every companion surface - because a state signal has to stay
/// visible after the nook collapses. Companion content stays mounted in both states, so a
/// companion is a convenient single place to publish from.
///
/// The rim is opt-in: nothing is drawn until some content publishes a non-nil color. When
/// several views publish, the last non-nil value wins.
public struct NookRimGlowPreferenceKey: PreferenceKey {
    public static var defaultValue: Color? { nil }

    public static func reduce(value: inout Color?, nextValue: () -> Color?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Lights the chrome's glowing rim in `color`, or contributes nothing when `color` is
    /// `nil`. See ``NookRimGlowPreferenceKey``; the rim's look comes from
    /// ``Nook/rimGlowStyle``.
    ///
    /// ```swift
    /// MyHomeView()
    ///     .nookRimGlow(model.isSyncing ? .blue : nil)
    /// ```
    public func nookRimGlow(_ color: Color?) -> some View {
        preference(key: NookRimGlowPreferenceKey.self, value: color)
    }
}

/// How the chrome draws its rim while content lights it with
/// `nookRimGlow(_:)`.
///
/// The rim has two layers: a crisp line traced just inside the chrome's edge, and a soft
/// halo that spills past it. The chrome adapts both to the user's accessibility settings on
/// its own - Reduce Motion stills the halo's breathing, Increase Contrast swaps the soft
/// halo for a bolder, fully opaque line, and Reduce Transparency drops the translucent
/// halo - so a style describes the default look only.
public struct NookRimGlowStyle: Equatable, Sendable {
    /// Width, in points, of the crisp line traced just inside the chrome's edge.
    public var lineWidth: CGFloat

    /// Blur radius, in points, of the soft halo that spills past the edge. `0` draws the
    /// line alone. In the notch form the halo fades out across the menu-bar band, so it
    /// never bleeds into the menu bar beside the notch.
    public var glowRadius: CGFloat

    /// Peak strength of the rim, from `0` (invisible) to `1` (fully opaque line).
    public var intensity: Double

    /// Whether the halo breathes while lit - a slow pulse that reads as "in progress" at the
    /// edge of vision. The line itself never pulses, so the signal stays legible. Always off
    /// under Reduce Motion.
    public var pulses: Bool

    /// When `true` and no content publishes a rim color, the rim follows the ambient wash
    /// color (``NookAmbientColorPreferenceKey``) instead, so a host tinting the surface gets
    /// a matching edge for free. Defaults to `false`, so a host that already uses the
    /// ambient wash does not gain a rim it never asked for.
    public var followsAmbientColor: Bool

    public init(
        lineWidth: CGFloat = 1.5,
        glowRadius: CGFloat = 8,
        intensity: Double = 0.9,
        pulses: Bool = true,
        followsAmbientColor: Bool = false
    ) {
        self.lineWidth = lineWidth
        self.glowRadius = glowRadius
        self.intensity = intensity
        self.pulses = pulses
        self.followsAmbientColor = followsAmbientColor
    }

    /// The framework default: a 1.5 pt line with an 8 pt breathing halo.
    public static let standard = NookRimGlowStyle()

    /// The rim color to draw, given what content published. `nil` draws no rim.
    public func color(rimColor: Color?, ambientColor: Color?) -> Color? {
        rimColor ?? (followsAmbientColor ? ambientColor : nil)
    }
}

/// The concrete drawing parameters for a rim, after a ``NookRimGlowStyle`` is adapted to the
/// user's accessibility settings. A pure value so the adaptation is testable without a
/// window.
struct NookRimGlowRendering: Equatable {
    /// Visible width of the crisp inner line.
    var lineWidth: CGFloat
    var lineOpacity: Double
    /// Stroke width fed to the halo before it is blurred.
    var haloWidth: CGFloat
    var haloRadius: CGFloat
    var haloOpacity: Double
    var pulses: Bool

    /// Whether the soft halo is drawn at all.
    var drawsHalo: Bool { haloRadius > 0 && haloOpacity > 0 }

    /// The lowest opacity multiplier a breathing halo dims to.
    static let pulseFloor: Double = 0.45

    static func resolve(
        style: NookRimGlowStyle,
        reduceMotion: Bool,
        increaseContrast: Bool,
        reduceTransparency: Bool
    ) -> NookRimGlowRendering {
        let intensity = min(max(style.intensity, 0), 1)
        let lineWidth = max(style.lineWidth, 0)
        let radius = max(style.glowRadius, 0)

        if increaseContrast {
            // A blurred halo softens exactly the edge Increase Contrast asks to sharpen, and
            // a breathing opacity dips below the contrast the user asked for. Trade both for
            // a solid line twice as heavy.
            return NookRimGlowRendering(
                lineWidth: max(lineWidth, 1) * 2,
                lineOpacity: intensity > 0 ? 1 : 0,
                haloWidth: 0,
                haloRadius: 0,
                haloOpacity: 0,
                pulses: false
            )
        }

        let drawsHalo = !reduceTransparency && radius > 0
        return NookRimGlowRendering(
            lineWidth: lineWidth,
            lineOpacity: intensity,
            haloWidth: drawsHalo ? max(lineWidth * 2, 3) : 0,
            haloRadius: drawsHalo ? radius : 0,
            haloOpacity: drawsHalo ? intensity * 0.85 : 0,
            pulses: drawsHalo && style.pulses && !reduceMotion
        )
    }
}
