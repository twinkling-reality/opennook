// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import NookSurface
import SwiftUI
import XCTest

@testable import PlaygroundNookCore

/// The settings model against the framework: its defaults are the framework's, and each
/// value lands on the configuration field it describes.
@MainActor
final class PlaygroundSettingsTests: XCTestCase {
    private struct Placeholder: View, Sendable {
        var body: some View { EmptyView() }
    }

    private func configuration(_ settings: PlaygroundSettings) -> NookConfiguration {
        settings.makeConfiguration(home: { Placeholder() }, companion: { _ in Placeholder() })
    }

    // MARK: - Defaults

    func testDefaultSettingsDescribeTheDefaultConfiguration() {
        let configuration = configuration(.default)
        let stock = NookConfiguration()

        XCTAssertNil(configuration.expandedWidth)
        XCTAssertNil(configuration.style)
        XCTAssertEqual(configuration.metrics, stock.metrics)
        XCTAssertEqual(configuration.typography, stock.typography)
        XCTAssertEqual(configuration.motion, stock.motion)
        XCTAssertEqual(configuration.labels, stock.labels)
        XCTAssertTrue(configuration.companions.isEmpty)
        XCTAssertEqual(configuration.rimGlow, stock.rimGlow)
        XCTAssertNil(configuration.scrollEdgeFade)
        XCTAssertEqual(configuration.chromeBehavior.hoverBehavior, stock.chromeBehavior.hoverBehavior)

        let topBar = configuration.topBar
        XCTAssertEqual(topBar.showsTopBar, stock.topBar.showsTopBar)
        XCTAssertEqual(topBar.showsSettings, stock.topBar.showsSettings)
        XCTAssertEqual(topBar.showsKeepOpenButton, stock.topBar.showsKeepOpenButton)
        XCTAssertEqual(topBar.showsSettingsButton, stock.topBar.showsSettingsButton)
        XCTAssertEqual(topBar.showsStatusBanner, stock.topBar.showsStatusBanner)
        XCTAssertEqual(topBar.width, stock.topBar.width)
        XCTAssertNil(topBar.leadingIcon)
    }

    /// Fonts and animations cannot be read back, so the playground restates the framework's;
    /// these catch a framework default that moved.
    func testRestatedDefaultsMatchTheFramework() {
        let typography = PlaygroundSettings.Typography()
        let stockTypography = NookChromeTypography.default
        XCTAssertEqual(typography.headerIcon.font, stockTypography.headerIcon)
        XCTAssertEqual(typography.topBarLabel.font, stockTypography.topBarLabel)
        XCTAssertEqual(typography.bannerMessage.font, stockTypography.bannerMessage)
        XCTAssertEqual(typography.compactLeadingGlyph.font, stockTypography.compactLeadingGlyph)

        let motion = PlaygroundSettings.Motion()
        XCTAssertEqual(motion.viewModeChange.animation, NookChromeMotion.default.viewModeChange)
        XCTAssertEqual(motion.statusBanner.animation, NookChromeMotion.default.statusBanner)

        let appState = AppState()
        XCTAssertEqual(PlaygroundSettings.TopBar().leadingTitle, NookTopBarConfiguration.default.leadingTitle(appState))
        XCTAssertEqual(PlaygroundSettings.Panel().expandedWidth, Double(NookLayout.width))
        XCTAssertNil(PlaygroundSettings.Panel().style, "the panel defaults are the framework's default style")
    }

    func testCompanionDefaultsMatchAddCompanion() {
        var configuration = NookConfiguration()
        configuration.addCompanion(id: "reference") { Placeholder() }
        let reference = configuration.companions[0]
        let companion = PlaygroundSettings.Companion(id: "reference", kind: .actions)

        XCTAssertEqual(companion.nookAnchor, reference.anchor)
        XCTAssertEqual(CGFloat(companion.spacing), reference.spacing)
        XCTAssertEqual(companion.nookVisibility, reference.visibility)
        XCTAssertEqual(companion.nookShape, reference.shape)
        XCTAssertEqual(companion.nookBackdrop, reference.backdrop)
        XCTAssertEqual(companion.hidesInSettings, reference.hidesInSettings)
        XCTAssertEqual(companion.accessibilityLabel, reference.accessibilityLabel)
    }

    // MARK: - Mapping

    func testChangedSettingsLandOnTheirConfigurationFields() {
        var settings = PlaygroundSettings()
        settings.theme.fontDesign = .serif
        settings.theme.accent = PlaygroundColor(red: 1, green: 0, blue: 0)
        settings.theme.subtleFill = PlaygroundColor(red: 0, green: 0, blue: 1, opacity: 0.5)
        settings.panel.expandedWidth = 440
        settings.panel.bottomCornerRadius = 30
        settings.panel.insetBottom = 12
        settings.metrics.edgePadding = 12
        settings.metrics.compactSlotSize = 30
        settings.typography.topBarLabel = PlaygroundSettings.FontSpec(size: 13, weight: .bold)
        settings.motion.viewModeChange = PlaygroundSettings.SpringSpec(response: 0.5, dampingFraction: 0.7)
        settings.labels.settingsBreadcrumb = "Preferences"
        settings.topBar.showsKeepOpenButton = false
        settings.topBar.showsStatusBanner = false
        settings.topBar.width = .intrinsic
        settings.topBar.leadingTitle = "Today"
        settings.topBar.leadingIcon = "sun.max"
        settings.rimGlow = PlaygroundSettings.RimGlow()
        settings.rimGlow.lineWidth = 3
        settings.rimGlow.followsAmbientColor = true
        settings.scrollEdgeFade.isEnabled = true
        settings.scrollEdgeFade.leading = false
        settings.scrollEdgeFade.length = 24
        settings.behavior.hoverHaptics = true

        let configuration = configuration(settings)

        let theme = configuration.theme(AppState())
        XCTAssertEqual(theme.fontDesign, .serif)
        XCTAssertEqual(theme.accent, PlaygroundColor(red: 1, green: 0, blue: 0).color)
        XCTAssertEqual(theme.subtleFill, PlaygroundColor(red: 0, green: 0, blue: 1, opacity: 0.5).color)
        XCTAssertEqual(configuration.expandedWidth, 440)
        XCTAssertEqual(
            configuration.style,
            NookStyle(
                topCornerRadius: NookConfiguration.defaultStyle.topCornerRadius,
                bottomCornerRadius: 30,
                expandedContentInsets: NookEdgeInsets(top: 0, bottom: 12, leading: 8, trailing: 8)
            )
        )
        var metrics = NookChromeMetrics.default
        metrics.edgePadding = 12
        metrics.compactSlotSize = 30
        XCTAssertEqual(configuration.metrics, metrics)
        XCTAssertEqual(configuration.typography.topBarLabel, .system(size: 13, weight: .bold))
        XCTAssertEqual(configuration.typography.headerIcon, NookChromeTypography.default.headerIcon)
        XCTAssertEqual(configuration.motion.viewModeChange, .spring(response: 0.5, dampingFraction: 0.7))
        XCTAssertEqual(configuration.motion.statusBanner, NookChromeMotion.default.statusBanner)
        XCTAssertEqual(configuration.labels.settingsBreadcrumb, "Preferences")
        XCTAssertEqual(configuration.labels.settingsHelp, NookChromeLabels.default.settingsHelp)
        XCTAssertFalse(configuration.topBar.showsKeepOpenButton)
        XCTAssertFalse(configuration.topBar.showsStatusBanner)
        XCTAssertTrue(configuration.topBar.showsSettingsButton)
        XCTAssertEqual(configuration.topBar.width, .intrinsic)
        XCTAssertEqual(configuration.topBar.leadingTitle(AppState()), "Today")
        XCTAssertEqual(configuration.topBar.leadingIcon, "sun.max")
        XCTAssertEqual(configuration.rimGlow, NookRimGlowStyle(lineWidth: 3, followsAmbientColor: true))
        XCTAssertEqual(configuration.scrollEdgeFade, NookScrollEdgeFade(edges: [.top, .bottom, .trailing], length: 24))
        XCTAssertEqual(configuration.chromeBehavior.hoverBehavior, .hapticFeedback)
        XCTAssertEqual(settings.chromeBehavior.hoverBehavior, .hapticFeedback)
    }

    func testThemeWithoutOverridesKeepsTheLivePalette() {
        let live = NookResolvedTheme.live(appState: AppState())
        let resolved = configuration(.default).theme(AppState())
        XCTAssertEqual(resolved.accent, live.accent)
        XCTAssertEqual(resolved.primaryLabel, live.primaryLabel)
        XCTAssertEqual(resolved.fontDesign, live.fontDesign)
    }

    func testEveryColorRoleReadsAndWritesItsOwnColor() {
        var theme = PlaygroundSettings.Theme()
        var resolved = NookResolvedTheme.live(appState: AppState())
        for (index, role) in PlaygroundSettings.Theme.ColorRole.allCases.enumerated() {
            let color = PlaygroundColor(red: Double(index) / 10, green: 0, blue: 0)
            theme[role] = color
            XCTAssertEqual(theme[role], color, role.rawValue)
        }
        theme.apply(to: &resolved)
        for (index, role) in PlaygroundSettings.Theme.ColorRole.allCases.enumerated() {
            XCTAssertEqual(
                role.color(in: resolved),
                PlaygroundColor(red: Double(index) / 10, green: 0, blue: 0).color,
                role.rawValue
            )
        }
    }

    func testCompanionsMapOntoAddCompanionAndSkipUnusableIDs() {
        var pill = PlaygroundSettings.Companion(id: "pill", kind: .actions, accessibilityLabel: "Actions")
        pill.anchor = .trailing
        pill.alignment = .end
        pill.spacing = 14
        pill.visibility = .both
        pill.outline = .roundedRectangle
        pill.cornerRadius = 6
        pill.backdrop = .solid
        pill.backdropColor = PlaygroundColor(red: 0, green: 0, blue: 1)
        pill.hidesInSettings = false
        var glass = PlaygroundSettings.Companion(id: "glass", kind: .chip)
        glass.backdrop = .glass
        glass.visibility = .compact
        glass.outline = .circle
        var settings = PlaygroundSettings()
        settings.companions = [
            pill,
            glass,
            PlaygroundSettings.Companion(id: "pill", kind: .button),
            PlaygroundSettings.Companion(id: "", kind: .chip),
        ]

        let companions = configuration(settings).companions

        XCTAssertEqual(companions.map(\.id), ["pill", "glass"], "a repeated or empty id is skipped, not a trap")
        XCTAssertEqual(companions[0].anchor, .trailing(alignment: .end))
        XCTAssertEqual(companions[0].spacing, 14)
        XCTAssertEqual(companions[0].visibility, .both)
        XCTAssertEqual(companions[0].shape, .roundedRectangle(cornerRadius: 6))
        XCTAssertEqual(companions[0].backdrop, .custom(.solid(PlaygroundColor(red: 0, green: 0, blue: 1).color)))
        XCTAssertFalse(companions[0].hidesInSettings)
        XCTAssertEqual(companions[0].accessibilityLabel, "Actions")
        XCTAssertEqual(companions[1].anchor, .below)
        XCTAssertEqual(companions[1].visibility, .compact)
        XCTAssertEqual(companions[1].shape, .circle)
        XCTAssertEqual(
            companions[1].backdrop,
            .custom(.liquidGlass(NookBackdrop.LiquidGlass(tint: glass.backdropColor.color)))
        )
        XCTAssertNil(companions[1].accessibilityLabel)
    }

    func testEverySampleBuildsAConfiguration() {
        for sample in PlaygroundPreset.samples {
            let configuration = configuration(sample.preset.settings)
            XCTAssertEqual(
                configuration.companions.map(\.id),
                sample.preset.settings.companions.map(\.id),
                sample.id
            )
        }
    }

    // MARK: - Normalizing

    func testNormalizingMakesCompanionIDsUniqueAndNonEmpty() {
        var settings = PlaygroundSettings()
        settings.companions = [
            PlaygroundSettings.Companion(id: " actions ", kind: .actions),
            PlaygroundSettings.Companion(id: "actions", kind: .actions),
            PlaygroundSettings.Companion(id: "", kind: .actions),
            PlaygroundSettings.Companion(id: "  ", kind: .chip),
            PlaygroundSettings.Companion(id: "status", kind: .button),
        ]
        XCTAssertEqual(
            settings.normalized().companions.map(\.id),
            ["actions", "actions-2", "actions-3", "status", "status-2"]
        )
    }

    func testNormalizingClampsValuesTheChromeCannotUse() {
        var settings = PlaygroundSettings()
        settings.panel.expandedWidth = 10
        settings.panel.topCornerRadius = -4
        settings.panel.insetTrailing = -1
        settings.metrics.edgePadding = -1
        settings.typography.bannerMessage.size = 0
        settings.motion.statusBanner = PlaygroundSettings.SpringSpec(response: 0, dampingFraction: 5)
        settings.rimGlow.glowRadius = -2
        settings.rimGlow.intensity = 3
        settings.scrollEdgeFade.length = -10
        settings.topBar.leadingIcon = "  "
        var companion = PlaygroundSettings.Companion(id: "a", kind: .chip, accessibilityLabel: "   ")
        companion.spacing = -3
        companion.cornerRadius = -3
        settings.companions = [companion]

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.panel.expandedWidth, 100)
        XCTAssertEqual(normalized.panel.topCornerRadius, 0)
        XCTAssertEqual(normalized.panel.insetTrailing, 0)
        XCTAssertEqual(normalized.metrics.edgePadding, 0)
        XCTAssertEqual(normalized.typography.bannerMessage.size, 1)
        XCTAssertEqual(
            normalized.motion.statusBanner,
            PlaygroundSettings.SpringSpec(response: 0.01, dampingFraction: 2)
        )
        XCTAssertEqual(normalized.rimGlow.glowRadius, 0)
        XCTAssertEqual(normalized.rimGlow.intensity, 1)
        XCTAssertEqual(normalized.scrollEdgeFade.length, 0)
        XCTAssertNil(normalized.topBar.leadingIcon)
        XCTAssertEqual(normalized.companions[0].spacing, 0)
        XCTAssertEqual(normalized.companions[0].cornerRadius, 0)
        XCTAssertNil(normalized.companions[0].accessibilityLabel)
    }

    func testNormalizingLeavesUsableSettingsAlone() {
        XCTAssertEqual(PlaygroundSettings.default.normalized(), .default)
        XCTAssertEqual(
            PlaygroundFixtures.everythingChanged.settings.normalized(),
            PlaygroundFixtures.everythingChanged.settings
        )
        for sample in PlaygroundPreset.samples {
            XCTAssertEqual(sample.preset.settings.normalized(), sample.preset.settings, sample.id)
        }
    }
}
