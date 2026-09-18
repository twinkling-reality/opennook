// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit

@testable import PlaygroundNookCore

enum PlaygroundFixtures {
    /// A preset with at least one change in every group the exporters write.
    static var everythingChanged: PlaygroundPreset {
        var settings = PlaygroundSettings()
        settings.theme.accent = PlaygroundColor(red: 1, green: 0.5, blue: 0)
        settings.theme.primaryLabel = PlaygroundColor(red: 1, green: 1, blue: 1, opacity: 0.9)
        settings.theme.fontDesign = .rounded

        settings.panel.expandedWidth = 440
        settings.panel.bottomCornerRadius = 30
        settings.panel.insetBottom = 12

        settings.metrics.edgePadding = 12
        settings.typography.topBarLabel = PlaygroundSettings.FontSpec(size: 12, weight: .medium)
        settings.motion.viewModeChange = PlaygroundSettings.SpringSpec(response: 0.5, dampingFraction: 0.8)
        settings.labels.settingsBreadcrumb = "Preferences"

        settings.topBar.showsKeepOpenButton = false
        settings.topBar.showsSettingsButton = false
        settings.topBar.notchClearance = .manual
        settings.topBar.notchAccessories = true
        settings.topBar.leadingTitle = "Today"
        settings.topBar.leadingIcon = "sun.max"

        settings.companionDefaults.fade = 0.25
        var actions = PlaygroundSettings.Companion(id: "actions", template: .actions, accessibilityLabel: "Actions")
        actions.alignment = .end
        actions.spacing = 12
        actions.gap = 16
        var leave = PlaygroundSettings.Item(symbol: "phone.down.fill", title: "Leave", action: .collapse)
        leave.fill = .color
        leave.fillColor = PlaygroundColor(red: 1, green: 0.2, blue: 0.2)
        actions.items.append(leave)
        var controls = PlaygroundSettings.Companion(
            id: "controls",
            template: .controls,
            accessibilityLabel: "Nook controls"
        )
        controls.visibility = .both
        controls.outline = .roundedRectangle
        controls.cornerRadius = 9
        controls.backdrop = .solid
        controls.backdropColor = PlaygroundColor(red: 0, green: 0, blue: 0, opacity: 0.6)
        controls.size = .small
        settings.companions = [actions, controls]

        settings.rimGlow.lineWidth = 2
        settings.rimGlow.pulses = false
        settings.scrollEdgeFade.isEnabled = true
        settings.scrollEdgeFade.leading = false
        settings.scrollEdgeFade.trailing = false
        settings.behavior.hoverHaptics = true
        settings.behavior.glassShading = .notchFade

        return PlaygroundPreset(
            appearance: NookAppearancePreferences(
                chromePalette: .dark,
                surfaceStyle: .liquidGlass,
                presentation: .floating,
                accentPreset: .violet,
                backdropStrength: 0.7
            ),
            settings: settings
        )
    }

    /// `PlaygroundSwiftExporter`'s output for ``everythingChanged``. It compiles as a
    /// `main.swift` once the home view's placeholder views exist.
    static let everythingChangedSwift = """
        import NookApp
        import SwiftUI

        struct MyNookHome: View {
            var body: some View {
                MyHomeView()  // your home view
                    .nookNotchAccessories {
                        HeaderTitle()  // your view: an icon and a short title
                    } trailing: {
                        HeaderButtons()  // your view: a few icon buttons
                    }
            }
        }

        var configuration = NookConfiguration()
        configuration.setHome { MyNookHome() }

        // Launch appearance. It seeds the first run; the user's own Settings choices win.
        configuration.preferenceDefaults = NookPreferenceDefaults(
            appearance: NookAppearancePreferences(
                chromePalette: .dark,
                surfaceStyle: .liquidGlass,
                presentation: .floating,
                accentPreset: .violet,
                backdropStrength: 0.7
            )
        )

        // The live palette, which follows the user's palette and accent, with overrides.
        configuration.theme = { appState in
            var theme = NookResolvedTheme.live(appState: appState)
            theme.accent = Color(red: 1, green: 0.502, blue: 0)
            theme.primaryLabel = Color(red: 1, green: 1, blue: 1, opacity: 0.902)
            theme.fontDesign = .rounded
            return theme
        }

        configuration.expandedWidth = 440
        configuration.style = NookConfiguration.defaultStyle
        configuration.style?.bottomCornerRadius = 30
        configuration.style?.expandedContentInsets.bottom = 12

        configuration.metrics.edgePadding = 12
        configuration.typography.topBarLabel = .system(size: 12, weight: .medium)
        configuration.motion.viewModeChange = .spring(response: 0.5, dampingFraction: 0.8)
        configuration.labels.settingsBreadcrumb = "Preferences"

        configuration.topBar.showsKeepOpenButton = false
        configuration.topBar.showsSettingsButton = false
        configuration.topBar.notchClearance = .manual
        configuration.topBar.leadingTitle = { _ in "Today" }
        configuration.topBar.leadingIcon = "sun.max"

        // How every companion looks and appears, unless it says otherwise.
        configuration.companionStyle = .faded

        configuration.addCompanion(
            id: "actions",
            anchor: .below(alignment: .end),
            spacing: 12,
            gap: 16,
            accessibilityLabel: "Actions"
        ) {
            ActionsCompanion()
        }
        configuration.addCompanion(
            id: "controls",
            anchor: .trailing,
            visibility: .both,
            shape: .roundedRectangle(cornerRadius: 9),
            backdrop: .custom(.solid(Color(red: 0, green: 0, blue: 0, opacity: 0.6))),
            size: .small,
            hidesInSettings: false,
            accessibilityLabel: "Nook controls"
        ) {
            ControlsCompanion()
        }

        // The rim shows while chrome content lights it: .nookRimGlow(isBusy ? .blue : nil)
        configuration.rimGlow = NookRimGlowStyle(lineWidth: 2, pulses: false)
        // Scroll views opt in with .nookScrollEdgeFade(axes:).
        configuration.scrollEdgeFade = NookScrollEdgeFade(edges: .vertical)

        configuration.chromeBehavior.hoverBehavior = .hapticFeedback
        configuration.chromeBehavior.glassShading = .notchFade

        NookApp.main(configuration)

        // MARK: - Companion content

        struct ActionsCompanion: View {
            @Environment(\\.nookChromeActions) private var chromeActions

            var body: some View {
                HStack(spacing: 2) {
                    Button("Previous", systemImage: "backward.fill") {}  // your action
                    Button("Play", systemImage: "play.fill") {}  // your action
                    Button("Next", systemImage: "forward.fill") {}  // your action
                    Button("Leave", systemImage: "phone.down.fill") { chromeActions.collapse() }
                        .buttonStyle(.nookGlyph(fill: .color(Color(red: 1, green: 0.2, blue: 0.2))))
                }
                .buttonStyle(.nookGlyph)
            }
        }

        struct ControlsCompanion: View {
            var body: some View {
                VStack(spacing: 2) {
                    NookKeepOpenButton()
                    NookSettingsButton()
                }
            }
        }

        """
}
