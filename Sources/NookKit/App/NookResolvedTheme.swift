// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import SwiftUI

/// Resolved palette for one layout pass: respects the chrome palette, system appearance,
/// and Reduce Transparency.
///
/// Every color is built **explicitly** from black or white at a fixed opacity - never from
/// system-adaptive colors like `Color.primary`. A nook lives on a non-activating panel
/// whose SwiftUI `colorScheme` environment is unreliable, so an adaptive color could resolve
/// for the wrong appearance (e.g. white text on the white light-mode panel). Resolving the
/// appearance once, here, and emitting concrete colors keeps light and dark both correct.
public struct NookResolvedTheme: Equatable, Sendable {
    public var primaryLabel: Color
    public var secondaryLabel: Color
    public var tertiaryLabel: Color
    public var quaternaryLabel: Color

    public var subtleFill: Color
    public var subtleStroke: Color

    public var headerInactiveIcon: Color

    /// The interactive tint for chrome controls - the active lock/gear glyphs, focus rings,
    /// and the surface `.tint`. Defaults to the macOS system accent (`controlAccentColor`)
    /// so the chrome matches the user's system unless a host overrides it. Set this in a
    /// custom palette to make the chrome track *your* brand color instead of system blue.
    public var accent: Color

    /// Font design applied across the chrome's own text (top bar, compact pill, the default
    /// home placeholder). Defaults to `.default`; set `.rounded`, `.serif`, or `.monospaced`
    /// to restyle the chrome's typography without supplying a full home view. Host-supplied
    /// content controls its own fonts.
    public var fontDesign: Font.Design

    /// The wash a hovered control is filled with, at the control's own wash opacity. Defaults
    /// to white, the wash the chrome has always drawn.
    public var hoverWash: Color

    /// Destructive actions, such as the reset command in Settings. Defaults to `Color.red`.
    public var destructive: Color

    /// Warnings, such as a shortcut that could not be registered. Defaults to `Color.orange`.
    public var warning: Color

    /// Success. Defaults to `Color.green`. The framework chrome does not use it yet; it is
    /// here for host content and banners that want one.
    public var success: Color

    /// Memberwise initializer. Host apps building a custom palette construct one
    /// directly and feed it to ``NookConfiguration/theme``; the framework's own
    /// palette is produced by ``resolve(preferences:effectiveColorScheme:reduceTransparency:)``.
    ///
    /// Every color should be an explicit black/white-at-opacity value - see the type
    /// note above on why system-adaptive colors render wrong on the nook's panel.
    ///
    /// `accent`, `fontDesign`, and the status and hover colors are defaulted, so a palette
    /// can fill only the label, fill, and stroke slots and still get a sensible chrome; pass
    /// them to brand it.
    public init(
        primaryLabel: Color,
        secondaryLabel: Color,
        tertiaryLabel: Color,
        quaternaryLabel: Color,
        subtleFill: Color,
        subtleStroke: Color,
        headerInactiveIcon: Color,
        accent: Color = Color(nsColor: .controlAccentColor),
        fontDesign: Font.Design = .default,
        hoverWash: Color = .white,
        destructive: Color = .red,
        warning: Color = .orange,
        success: Color = .green
    ) {
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.tertiaryLabel = tertiaryLabel
        self.quaternaryLabel = quaternaryLabel
        self.subtleFill = subtleFill
        self.subtleStroke = subtleStroke
        self.headerInactiveIcon = headerInactiveIcon
        self.accent = accent
        self.fontDesign = fontDesign
        self.hoverWash = hoverWash
        self.destructive = destructive
        self.warning = warning
        self.success = success
    }

    /// The framework's palette for `preferences`: ``NookTheme/standard`` resolved for the
    /// person's palette, surface, and accent. See
    /// ``resolve(theme:preferences:effectiveColorScheme:reduceTransparency:)``.
    public static func resolve(
        preferences: NookAppearancePreferences,
        effectiveColorScheme: ColorScheme,
        reduceTransparency: Bool
    ) -> NookResolvedTheme {
        resolve(
            theme: .standard,
            preferences: preferences,
            effectiveColorScheme: effectiveColorScheme,
            reduceTransparency: reduceTransparency
        )
    }

    /// `theme`'s palette for the person's `preferences`, with the theme's pins applied.
    ///
    /// `effectiveColorScheme` is the system's appearance, used when the palette follows the
    /// system. The colors stay explicit, black or white at an opacity unless the theme says
    /// otherwise; see the type note on why system-adaptive colors render wrong on the nook's
    /// panel. ``NookTheme/standard`` gives exactly the framework's palette: white at 0.95,
    /// 0.62, 0.46, and 0.34 for the labels on dark chrome, black at 0.88, 0.55, 0.42, and 0.32
    /// on light, and a subtle fill a touch stronger on an opaque surface.
    public static func resolve(
        theme: NookTheme,
        preferences: NookAppearancePreferences,
        effectiveColorScheme: ColorScheme,
        reduceTransparency: Bool
    ) -> NookResolvedTheme {
        let context = theme.context(
            preferences: preferences,
            systemColorScheme: effectiveColorScheme,
            reduceTransparency: reduceTransparency
        )
        let resolver = NookThemeResolver(theme: theme)
        return NookResolvedTheme(
            primaryLabel: resolver.color(.labelPrimary, in: context),
            secondaryLabel: resolver.color(.labelSecondary, in: context),
            tertiaryLabel: resolver.color(.labelTertiary, in: context),
            quaternaryLabel: resolver.color(.labelQuaternary, in: context),
            subtleFill: resolver.color(.fillSubtle, in: context),
            subtleStroke: resolver.color(.strokeSubtle, in: context),
            headerInactiveIcon: resolver.color(.iconInactive, in: context),
            accent: resolver.color(.accent, in: context),
            fontDesign: theme.fontDesign.design,
            hoverWash: resolver.color(.hoverWash, in: context),
            destructive: resolver.color(.destructive, in: context),
            warning: resolver.color(.warning, in: context),
            success: resolver.color(.success, in: context)
        )
    }
}

// MARK: - SwiftUI environment

private struct NookResolvedThemeKey: EnvironmentKey {
    static let defaultValue = NookResolvedTheme.resolve(
        preferences: .default,
        effectiveColorScheme: .dark,
        reduceTransparency: false
    )
}

extension EnvironmentValues {
    public var nookResolvedTheme: NookResolvedTheme {
        get { self[NookResolvedThemeKey.self] }
        set { self[NookResolvedThemeKey.self] = newValue }
    }
}

extension NookResolvedTheme {
    /// Resolves chrome using saved prefs, the **application's effective appearance** for
    /// "Match Mac" (SwiftUI's `colorScheme` is unreliable on menu-bar panels), and Reduce
    /// Transparency.
    ///
    /// Reads the appearance off `NSApplication.shared` rather than the `NSApp` global so
    /// it stays safe before the app has finished launching (and callable from tests).
    ///
    /// `@MainActor` because it touches `NSApplication.shared.effectiveAppearance`, which
    /// is main-actor state. Chrome theming is resolved during view rendering, so the
    /// isolation matches where it actually runs.
    @MainActor
    public static func live(appState: AppState) -> NookResolvedTheme {
        let systemScheme: ColorScheme =
            NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        let scheme = appState.appearancePreferences.effectiveColorScheme(systemScheme: systemScheme)
        return resolve(
            preferences: appState.appearancePreferences,
            effectiveColorScheme: scheme,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }
}

extension NookAppearancePreferences {
    /// When non-nil, apply as SwiftUI `preferredColorScheme` so Dark/Light chrome overrides stick on panel-hosted UI.
    public var chromeColorSchemeOverride: ColorScheme? {
        switch chromePalette {
            case .followSystem:
                nil
            case .dark:
                .dark
            case .light:
                .light
        }
    }

    public func effectiveColorScheme(systemScheme: ColorScheme) -> ColorScheme {
        switch chromePalette {
            case .followSystem:
                systemScheme
            case .dark:
                .dark
            case .light:
                .light
        }
    }

    /// The `NSAppearance` to pin on the chrome window, or `nil` to follow the system.
    /// Drives the backdrop's `NSVisualEffectView` material so a forced theme renders right.
    public var chromeAppearanceOverride: NSAppearance? {
        switch chromePalette {
            case .followSystem:
                nil
            case .dark:
                NSAppearance(named: .darkAqua)
            case .light:
                NSAppearance(named: .aqua)
        }
    }
}
