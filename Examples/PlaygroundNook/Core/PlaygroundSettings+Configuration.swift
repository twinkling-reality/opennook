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

        // `addCompanion` traps on a duplicate id, and the settings may not have been
        // normalized, so a repeated id is skipped rather than registered twice.
        var registeredIDs = Set<String>()
        for item in companions where !item.id.isEmpty && registeredIDs.insert(item.id).inserted {
            configuration.addCompanion(
                id: item.id,
                anchor: item.nookAnchor,
                spacing: CGFloat(item.spacing),
                visibility: item.nookVisibility,
                shape: item.nookShape,
                backdrop: item.nookBackdrop,
                hidesInSettings: item.hidesInSettings,
                accessibilityLabel: item.accessibilityLabel
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

    /// The chrome behavior these settings describe.
    public var chromeBehavior: NookChromeBehavior {
        NookChromeBehavior(hoverBehavior: behavior.hoverBehavior)
    }
}
