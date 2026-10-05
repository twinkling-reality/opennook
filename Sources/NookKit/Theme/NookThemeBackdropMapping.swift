// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookSurface
import SwiftUI

extension NookTheme {
    /// The backdrop the theme paints for the chrome in `context`, or `nil` for the framework's
    /// own (``NookBackdropMapping``).
    ///
    /// The theme's description for the surface style in `context` decides: none, or
    /// ``NookBackdropDescription/framework``, is the framework's. Under Reduce Transparency a
    /// vibrancy or glass description is the framework's too, which paints the surface solid.
    /// A ``NookBackdropDescription/custom(id:fallback:)`` backdrop is looked up in
    /// `customBackdrops` by id, and falls back to its `fallback` when no view is registered.
    @MainActor
    public func backdrop(
        in context: NookBackdropContext,
        customBackdrops: [String: NookChromeBehavior.BackdropResolver] = [:]
    ) -> NookBackdrop? {
        guard let description = backdrops[context.preferences.surfaceStyle] else { return nil }
        return backdrop(for: description, in: context, customBackdrops: customBackdrops)
    }

    /// `description` as a `NookBackdrop` in `context`, or `nil` for the framework's own.
    @MainActor
    public func backdrop(
        for description: NookBackdropDescription,
        in context: NookBackdropContext,
        customBackdrops: [String: NookChromeBehavior.BackdropResolver] = [:]
    ) -> NookBackdrop? {
        let colors = NookThemeContext(
            isDark: context.colorScheme == .dark,
            surfaceStyle: context.preferences.surfaceStyle,
            reduceTransparency: context.reduceTransparency,
            accentPreset: allowsUserAccent ? context.preferences.accentPreset : .system
        )
        let isDark = colors.isDark
        let strength = context.preferences.clampedBackdropStrength
        func color(_ value: NookColorValue) -> Color { resolve(value, in: colors) }
        func gradient(_ spec: NookGradientSpec, opacity: Double = 1) -> Gradient {
            Gradient(
                stops: zip(spec.stops, spec.resolvedLocations).map { stop, location in
                    let resolved = color(stop.color)
                    return Gradient.Stop(color: opacity == 1 ? resolved : resolved.opacity(opacity), location: location)
                }
            )
        }

        switch description {
            case .framework:
                return nil
            case .solid(let fill):
                return .solid(color(fill))
            case .vibrancy(let vibrancy):
                guard !context.reduceTransparency else { return nil }
                let scale = vibrancy.scalesWithStrength ? strength : 1
                return .vibrancy(
                    NookBackdrop.Vibrancy(
                        material: vibrancy.material.visualEffectMaterial,
                        blendingMode: vibrancy.blending.visualEffectBlending,
                        darkenOpacity: CGFloat(vibrancy.darken.value(isDark: isDark) * scale),
                        darkenColor: vibrancy.darkenColor.map(color) ?? .black
                    )
                )
            case .liquidGlass(let glass):
                guard !context.reduceTransparency else { return nil }
                let scale = glass.scalesWithStrength ? strength : 1
                return .liquidGlass(
                    NookBackdrop.LiquidGlass(
                        tint: glass.tint.map(color),
                        tintStrength: CGFloat(glass.tintStrength.value(isDark: isDark) * scale),
                        highlightStrength: CGFloat(glass.highlight),
                        shading: glass.shading.map { shading in
                            NookBackdrop.LiquidGlass.Shading(
                                gradient: gradient(shading.gradient, opacity: scale),
                                startPoint: shading.start.unitPoint,
                                endPoint: shading.end.unitPoint
                            )
                        },
                        variant: glass.variant == .clear ? .clear : .regular,
                        fallbackMaterial: glass.fallbackMaterial?.visualEffectMaterial ?? .hudWindow,
                        highlightColor: glass.highlightColor.map(color) ?? .white,
                        rimWidth: CGFloat(glass.rimWidth ?? 1)
                    )
                )
            case .linearGradient(let linear):
                return .gradient(
                    .linear(
                        gradient(linear.gradient),
                        startPoint: linear.start.unitPoint,
                        endPoint: linear.end.unitPoint
                    )
                )
            case .radialGradient(let radial):
                return .gradient(
                    .radial(
                        gradient(radial.gradient),
                        center: radial.center.unitPoint,
                        startRadius: CGFloat(radial.startRadius),
                        endRadius: CGFloat(radial.endRadius)
                    )
                )
            case .ellipticalGradient(let elliptical):
                return .gradient(
                    .elliptical(
                        gradient(elliptical.gradient),
                        center: elliptical.center.unitPoint,
                        startRadiusFraction: CGFloat(elliptical.startRadius),
                        endRadiusFraction: CGFloat(elliptical.endRadius)
                    )
                )
            case .angularGradient(let angular):
                return .gradient(
                    .angular(
                        gradient(angular.gradient),
                        center: angular.center.unitPoint,
                        startAngle: .degrees(angular.startAngle),
                        endAngle: .degrees(angular.endAngle)
                    )
                )
            case .mesh(let mesh):
                guard mesh.isWellFormed else { return nil }
                return .meshGradient(
                    MeshGradient(
                        width: mesh.width,
                        height: mesh.height,
                        points: mesh.points.map { SIMD2<Float>(Float($0[0]), Float($0[1])) },
                        colors: mesh.colors.map(color),
                        smoothsColors: mesh.smoothsColors
                    )
                )
            case .custom(let id, let fallback):
                if let provider = customBackdrops[id] {
                    return provider(context)
                }
                return fallback.flatMap { backdrop(for: $0, in: context, customBackdrops: customBackdrops) }
            case .unknown(_, let fallback):
                return fallback.flatMap { backdrop(for: $0, in: context, customBackdrops: customBackdrops) }
        }
    }
}

extension NookBackdropDescription.Material {
    /// The `NSVisualEffectView` material.
    var visualEffectMaterial: NSVisualEffectView.Material {
        switch self {
            case .titlebar: .titlebar
            case .selection: .selection
            case .menu: .menu
            case .popover: .popover
            case .sidebar: .sidebar
            case .headerView: .headerView
            case .sheet: .sheet
            case .windowBackground: .windowBackground
            case .hudWindow: .hudWindow
            case .fullScreenUI: .fullScreenUI
            case .toolTip: .toolTip
            case .contentBackground: .contentBackground
            case .underWindowBackground: .underWindowBackground
            case .underPageBackground: .underPageBackground
        }
    }
}

extension NookBackdropDescription.Blending {
    /// The `NSVisualEffectView` blending mode.
    var visualEffectBlending: NSVisualEffectView.BlendingMode {
        switch self {
            case .behindWindow: .behindWindow
            case .withinWindow: .withinWindow
        }
    }
}
