// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import SwiftUI

private struct NookThemeKey: EnvironmentKey {
    static let defaultValue: NookTheme = .standard
}

private struct NookThemeTokensKey: EnvironmentKey {
    static let defaultValue: NookResolvedTokens = .standard
}

extension EnvironmentValues {
    /// The theme the chrome around this view is drawn with: the displayed module's
    /// ``NookConfiguration/chromeTheme``, the host's, or ``NookTheme/standard``.
    ///
    /// Read it to resolve a ``NookColorValue`` the same way the chrome does, or to see what
    /// the theme pins, as the built-in Settings does to hide the controls it overrides.
    public var nookTheme: NookTheme {
        get { self[NookThemeKey.self] }
        set { self[NookThemeKey.self] = newValue }
    }

    /// The chrome theme's resolved tokens, for host content that wants the chrome's spacing,
    /// radii, type, and springs: `tokens[.spaceMD]`, `tokens[.typeBody]`,
    /// `tokens[.springDefault]`.
    public var nookThemeTokens: NookResolvedTokens {
        get { self[NookThemeTokensKey.self] }
        set { self[NookThemeTokensKey.self] = newValue }
    }
}

extension NookTheme {
    /// The system's light/dark appearance, read off the application the way the chrome's
    /// palette always has (SwiftUI's `colorScheme` is unreliable on the nook's panel).
    @MainActor
    static var systemColorScheme: ColorScheme {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// The appearance to resolve the theme's colors for right now: the person's preferences
    /// with the theme's pins, the system's appearance, and Reduce Transparency.
    @MainActor
    func liveContext(appState: AppState) -> NookThemeContext {
        context(
            preferences: appState.appearancePreferences,
            systemColorScheme: Self.systemColorScheme,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    /// Whether the theme sets any of the per-part chrome colors in ``NookChromeColors``.
    var setsChromeColors: Bool {
        [NookColorID.bannerSeverityError, .bannerSeverityWarning, .bannerSeverityInfo, .bannerSeveritySuccess]
            .contains { tokens[$0] != nil }
    }

    /// ``chromeColors(in:)`` for right now, skipping the resolution when the theme sets none.
    @MainActor
    func liveChromeColors(appState: AppState) -> NookChromeColors {
        setsChromeColors ? chromeColors(in: liveContext(appState: appState)) : .default
    }
}

extension NookResolvedTheme {
    /// `theme`'s palette for the person's saved preferences, the application's effective
    /// appearance, and Reduce Transparency - ``live(appState:)`` for a theme other than the
    /// standard one.
    @MainActor
    public static func live(appState: AppState, theme: NookTheme) -> NookResolvedTheme {
        resolve(
            theme: theme,
            preferences: appState.appearancePreferences,
            effectiveColorScheme: NookTheme.systemColorScheme,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }
}
