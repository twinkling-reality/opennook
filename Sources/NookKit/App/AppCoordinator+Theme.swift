// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// Projects the displayed module's chrome theme onto the surface, the way the coordinator
/// projects its rim glow and companions: the MIT surface only ever sees finished values.
extension AppCoordinator {
    /// The theme of the module whose content is on the surface.
    var displayedTheme: NookTheme {
        moduleHost.displayedConfiguration.effectiveChromeTheme
    }

    /// The person's appearance preferences with the displayed theme's pins applied: what the
    /// chrome paints with. The stored preferences are never changed.
    var effectiveAppearancePreferences: NookAppearancePreferences {
        displayedTheme.effectivePreferences(appState.appearancePreferences)
    }

    /// The appearance the displayed theme's colors resolve for right now, read through the
    /// coordinator's own system-appearance and Reduce Transparency seams.
    var themeContext: NookThemeContext {
        displayedTheme.context(
            preferences: appState.appearancePreferences,
            systemColorScheme: systemColorSchemeProvider(),
            reduceTransparency: reduceTransparencyProvider()
        )
    }

    /// Applies the displayed configuration's surface look: its shape, its expand and
    /// collapse curves and content transitions, its ambient wash, and its theme colors.
    ///
    /// Called at launch, by ``reloadActiveConfiguration()``, and when a module switch or a
    /// background module's claim changes which configuration is on the surface. A switch calls
    /// it inside its animation, so the chrome reshapes with the content.
    func applySurfaceLook() {
        let configuration = moduleHost.displayedConfiguration
        let style = configuration.effectiveStyle
        // `Nook.style` publishes on every assignment, so skip one that changes nothing.
        if surface.style != style {
            surface.style = style
        }
        configureNotchAnimations()
        let wash = configuration.effectiveThemeTokens.ambientWash
        if surface.ambientWash != wash {
            surface.ambientWash = wash
        }
        applyThemeColors()
        bindThemeSources()
    }

    /// Follows the theme sources that decide the displayed configuration's theme, so a theme
    /// replaced in code or a theme file saved on disk reaches the chrome at once.
    func bindThemeSources() {
        let sources = [moduleHost.displayedConfiguration.chromeThemeSource, moduleHost.registry.chromeThemeSource]
        themeSourceSubscriptions = sources.compactMap { $0 }.map { source in
            source.changes.sink { [weak self] _ in self?.themeSourceDidChange() }
        }
    }

    /// Applies a changed live theme the way ``reloadActiveConfiguration()`` applies a
    /// configuration, to the active module and to a background module presenting over it.
    func themeSourceDidChange() {
        moduleHost.reloadPresentedBackgroundConfiguration()
        reloadActiveConfiguration()
    }

    /// The theme colors the surface draws, which follow the appearance: the chrome's shadow.
    /// Called from ``syncNotchBackdrop()``, which runs on every appearance change.
    func applyThemeColors() {
        let shadow = chromeShadow(for: displayedTheme, in: themeContext)
        if surface.chromeShadow != shadow {
            surface.chromeShadow = shadow
        }
    }

    /// The theme's `shadow.chrome`, resolved, or `nil` when it casts none.
    func chromeShadow(for theme: NookTheme, in context: NookThemeContext) -> NookChromeShadow? {
        guard let spec = theme.tokens[.chrome] else { return nil }
        return NookChromeShadow(
            color: theme.resolve(spec.color, in: context),
            radius: CGFloat(max(spec.radius, 0)),
            x: CGFloat(spec.x),
            y: CGFloat(spec.y)
        )
    }

    /// The feedback look for the displayed theme: the standard cue in `feedback.tint`, which
    /// follows the accent.
    var themedFeedbackStyle: NookFeedbackStyle {
        var style = NookFeedbackStyle.standard
        style.color = displayedTheme.color(.feedbackTint, in: themeContext)
        return style
    }

    /// `style` with the displayed theme's `color.hoverWash` when it is a built-in standard
    /// style still washing in the default white. A style whose wash color a host set, and a
    /// custom style, are left exactly as they are; so is every style while the theme leaves
    /// `color.hoverWash` at its default.
    func themedCompanionStyle(_ style: AnyNookCompanionStyle, theme: NookTheme) -> AnyNookCompanionStyle {
        guard theme.tokens[.hoverWash] != nil,
            var standard = style.base as? NookStandardCompanionStyle,
            standard.hover.washColor == .white
        else {
            return style
        }
        standard.hover.washColor = theme.color(.hoverWash, in: themeContext)
        return AnyNookCompanionStyle(standard)
    }

    /// Plays a peripheral cue along the chrome's edge in the theme's `feedback.tint` - a sync
    /// that finished, a background task that completed. A cue requested while the nook is
    /// hidden plays the next time it shows.
    ///
    /// ```swift
    /// coordinator.playFeedback(.pulse)
    /// ```
    public func playFeedback(_ effect: NookFeedback = .shimmer, duration: TimeInterval = 0.85, repeats: Bool = false) {
        surface.playFeedback(effect, style: themedFeedbackStyle, duration: duration, repeats: repeats)
    }
}
