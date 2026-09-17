// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import NookSurface
import SwiftUI

extension PlaygroundSettings {
    /// The configuration these settings describe, with the playground's own views as content.
    /// Settings left at their defaults leave the matching configuration values at theirs.
    ///
    /// - Parameters:
    ///   - home: The expanded home view.
    ///   - companion: The content of one companion surface.
    public func makeConfiguration<Home: View & Sendable, CompanionContent: View & Sendable>(
        home: @escaping @Sendable @MainActor () -> Home,
        companion: @escaping @Sendable @MainActor (Companion) -> CompanionContent
    ) -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.setHome(home)

        if theme != Theme() {
            let theme = theme
            configuration.theme = { appState in
                var resolved = NookResolvedTheme.live(appState: appState)
                theme.apply(to: &resolved)
                return resolved
            }
        }

        if panel.expandedWidth != Panel().expandedWidth {
            configuration.expandedWidth = CGFloat(panel.expandedWidth)
        }
        configuration.style = panel.style
        configuration.metrics = metrics.chromeMetrics
        configuration.typography = typography.chromeTypography
        configuration.motion = motion.chromeMotion
        configuration.labels = labels.chromeLabels
        topBar.apply(to: &configuration.topBar)

        configuration.companionSize = companionDefaults.size.nookSize
        configuration.companionPresence = companionDefaults.presence.nookPresence
        let defaultStyle = companionDefaults.style
        if defaultStyle != .standard {
            configuration.companionStyle = AnyNookCompanionStyle(defaultStyle)
        }

        // `addCompanion` traps on a duplicate id, and the settings may not have been
        // normalized, so a repeated id is skipped rather than registered twice.
        var registeredIDs = Set<String>()
        let chromeTheme = configuration.theme
        for item in companions where !item.id.isEmpty && registeredIDs.insert(item.id).inserted {
            configuration.addCompanion(
                id: item.id,
                anchor: item.nookAnchor,
                spacing: CGFloat(item.spacing),
                gap: item.gap.map { CGFloat($0) },
                rowAlignment: item.rowAlignment?.nookAlignment,
                visibility: item.nookVisibility,
                shape: item.nookShape,
                backdrop: item.nookBackdrop,
                style: item.overridesStyle ? AnyNookCompanionStyle(item.style(over: companionDefaults)) : nil,
                size: item.size?.nookSize,
                presence: item.presence?.nookPresence,
                hidesInSettings: item.hidesInSettings,
                accessibilityLabel: item.accessibilityLabel,
                theme: Self.theme(chromeTheme, accent: item.accent)
            ) {
                companion(item)
            }
        }

        configuration.rimGlow = rimGlow.style
        configuration.scrollEdgeFade = scrollEdgeFade.fade
        // A module's configuration does not carry chrome behavior to the host - the playground
        // applies it with `AppCoordinator.replaceChromeBehavior(_:)`. It is set here too so the
        // configuration describes everything the settings do.
        configuration.chromeBehavior = chromeBehavior
        return configuration
    }

    /// `chromeTheme` with its accent replaced, for a companion with an accent of its own, or `nil`
    /// to leave the companion on the chrome's palette.
    private static func theme(
        _ chromeTheme: @escaping @Sendable @MainActor (AppState) -> NookResolvedTheme,
        accent: PlaygroundColor?
    ) -> (@Sendable @MainActor (AppState) -> NookResolvedTheme)? {
        guard let accent else { return nil }
        return { appState in
            var theme = chromeTheme(appState)
            theme.accent = accent.color
            return theme
        }
    }

    /// The chrome behavior these settings describe.
    public var chromeBehavior: NookChromeBehavior {
        NookChromeBehavior(hoverBehavior: behavior.hoverBehavior, glassShading: behavior.glassShading.nookShading)
    }
}
