// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookSurface
import SwiftUI

/// Maps appearance preferences into a nook backdrop.
///
/// Three outcomes: a solid opaque fill (the `.solid` surface style, or any time Reduce
/// Transparency is on), a frosted vibrancy material with a slight darken pass on top, or
/// a Liquid Glass material tinted and scrimmed toward the resolved theme - each scaled
/// by `backdropStrength`.
public enum NookBackdropMapping {
    /// The chrome's backdrop for `preferences`, with the framework's even Liquid Glass shading.
    public static func notchBackdrop(
        preferences: NookAppearancePreferences,
        effectiveColorScheme: ColorScheme,
        reduceTransparency: Bool
    ) -> NookBackdrop {
        notchBackdrop(
            preferences: preferences,
            effectiveColorScheme: effectiveColorScheme,
            reduceTransparency: reduceTransparency,
            glassShading: .even
        )
    }

    /// The chrome's backdrop for `preferences`, shading Liquid Glass as `glassShading` says.
    ///
    /// `glassShading` only changes Liquid Glass. Solid, Translucent, and Reduce Transparency
    /// give the same backdrop whatever it is.
    public static func notchBackdrop(
        preferences: NookAppearancePreferences,
        effectiveColorScheme: ColorScheme,
        reduceTransparency: Bool,
        glassShading: NookGlassShading
    ) -> NookBackdrop {
        let isDark: Bool =
            switch preferences.chromePalette {
                case .followSystem: effectiveColorScheme == .dark
                case .dark: true
                case .light: false
            }

        // `.solid` and Reduce Transparency both want the same answer: a real opaque
        // color, no visual-effect view. Pure black / white so the chrome reads as the
        // same surface as the physical notch. RT also collapses the translucent styles
        // here - neither glass nor frost should render when the user opted out.
        if preferences.surfaceStyle == .solid || reduceTransparency {
            return .solid(isDark ? .black : .white)
        }

        // `backdropStrength` scales the legibility darken for either translucent style.
        let strength = min(max(preferences.backdropStrength, 0.15), 1)
        switch preferences.surfaceStyle {
            case .translucent:
                // One frosted sidebar material per appearance, with a darken pass so chrome
                // content stays legible over a bright wallpaper.
                let baseDarken = isDark ? 0.52 : 0.10
                return .vibrancy(
                    .init(
                        material: .sidebar,
                        blendingMode: .behindWindow,
                        darkenOpacity: baseDarken * strength
                    )
                )
            case .liquidGlass where glassShading == .notchFade:
                // Clear glass, shaded from the notch's own color at the top to nothing at the
                // bottom. The top matches the hardware notch; strength decides how dark the fade
                // is below it. Light chrome fades from white, so dark text stays legible there.
                return .liquidGlass(
                    .init(
                        tint: nil,
                        highlightStrength: 0.6,
                        shading: .notchFade(isDark ? .black : .white, strength: strength)
                    )
                )
            case .liquidGlass:
                // The glass must be *anchored to the resolved theme*, not left neutral. On
                // macOS 26 Apple's glass material is self-adaptive: it flips its own light/
                // dark treatment from the luminance of whatever sits behind the window,
                // ignoring the pinned `NSAppearance`. Neutral glass under a forced theme
                // therefore breaks whenever the wallpaper disagrees - light chrome text
                // over glass that flipped dark, and vice versa. A theme-colored tint inside
                // the material plus a matching legibility scrim keep the surface's
                // luminance on the theme's side of the contrast budget regardless of the
                // backdrop. The shading runs top-to-bottom and tapers to 40% at the bottom,
                // so the surface reads glassier as it nears the wallpaper. All of this is
                // only a *default*: a host returning `.liquidGlass` from a backdrop
                // resolver supplies its own tint and `Shading` gradient and is never
                // constrained to these curves, directions, or colors.
                if isDark {
                    let topDarken = 0.22 * strength
                    return .liquidGlass(
                        .init(
                            tint: .black,
                            tintStrength: 0.30 * strength,
                            highlightStrength: 0.6,
                            shading: .init(
                                gradient: Gradient(colors: [
                                    .black.opacity(topDarken),
                                    .black.opacity(topDarken * 0.4),
                                ])
                            )
                        )
                    )
                } else {
                    let topLighten = 0.38 * strength
                    return .liquidGlass(
                        .init(
                            tint: .white,
                            tintStrength: 0.42 * strength,
                            highlightStrength: 0.6,
                            shading: .init(
                                gradient: Gradient(colors: [
                                    .white.opacity(topLighten),
                                    .white.opacity(topLighten * 0.4),
                                ])
                            )
                        )
                    )
                }
            case .solid:
                // Unreachable - handled by the guard above. Kept so the switch stays
                // exhaustive without a `default` that would swallow a future style.
                return .solid(isDark ? .black : .white)
        }
    }
}

extension NookBackdropMapping {
    /// The backdrop companions inheriting the chrome's should paint, or `nil` for the chrome's
    /// own.
    ///
    /// `nil` except for Liquid Glass shaded ``NookGlassShading/notchFade``: a fade sized for the
    /// tall chrome would be squeezed into a small pill, black at its top and clear at its
    /// bottom, so companions get the same clear glass with a light, even tint for legibility,
    /// scaled by the same strength.
    public static func companionBackdrop(
        preferences: NookAppearancePreferences,
        effectiveColorScheme: ColorScheme,
        reduceTransparency: Bool,
        glassShading: NookGlassShading
    ) -> NookBackdrop? {
        guard glassShading == .notchFade, preferences.surfaceStyle == .liquidGlass, !reduceTransparency else {
            return nil
        }
        let isDark: Bool =
            switch preferences.chromePalette {
                case .followSystem: effectiveColorScheme == .dark
                case .dark: true
                case .light: false
            }
        let strength = min(max(preferences.backdropStrength, 0.15), 1)
        return .liquidGlass(
            .init(
                tint: nil,
                highlightStrength: 0.6,
                shading: .uniform(isDark ? .black.opacity(0.3 * strength) : .white.opacity(0.4 * strength))
            )
        )
    }
}

/// How the framework shades Liquid Glass, set on ``NookChromeBehavior/glassShading``.
public enum NookGlassShading: Sendable, Equatable, CaseIterable {
    /// Glass tinted toward the theme, with a light darken (or lighten) that eases toward the
    /// bottom. The framework's look since Liquid Glass shipped.
    case even

    /// Black where the panel meets the hardware notch, fading to clear glass at the bottom so
    /// the wallpaper shows through - white instead of black for light chrome. Glass strength
    /// scales how dark the fade is below the top edge. Companions inheriting the chrome's
    /// backdrop get the same clear glass with a light even tint (see
    /// ``NookBackdropMapping/companionBackdrop(preferences:effectiveColorScheme:reduceTransparency:glassShading:)``).
    case notchFade
}
