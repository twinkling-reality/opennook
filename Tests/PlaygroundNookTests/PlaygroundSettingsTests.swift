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
        XCTAssertEqual(topBar.notchClearance, stock.topBar.notchClearance)
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
        let companion = PlaygroundSettings.Companion(id: "reference", template: .actions)

        XCTAssertEqual(companion.nookAnchor, reference.anchor)
        XCTAssertEqual(CGFloat(companion.spacing), reference.spacing)
        XCTAssertEqual(companion.nookVisibility, reference.visibility)
        XCTAssertEqual(companion.nookShape, reference.shape)
        XCTAssertEqual(companion.nookBackdrop, reference.backdrop)
        XCTAssertEqual(companion.hidesInSettings, reference.hidesInSettings)
        XCTAssertEqual(companion.accessibilityLabel, reference.accessibilityLabel)
        XCTAssertNil(companion.gap)
        XCTAssertNil(reference.gap)
        XCTAssertNil(companion.rowAlignment)
        XCTAssertNil(reference.rowAlignment)
        XCTAssertNil(companion.size)
        XCTAssertNil(reference.size)
        XCTAssertNil(companion.presence)
        XCTAssertNil(reference.presence)
        XCTAssertFalse(companion.overridesStyle)
        XCTAssertNil(reference.style)
        XCTAssertNil(companion.accent)
        XCTAssertNil(reference.theme)
    }

    /// Untouched companion defaults are the framework's own.
    func testCompanionDefaultsDescribeTheFrameworksDefaults() {
        let configuration = configuration(.default)
        let stock = NookConfiguration()
        XCTAssertEqual(configuration.companionSize, stock.companionSize)
        XCTAssertEqual(configuration.companionPresence, stock.companionPresence)
        XCTAssertEqual(
            configuration.companionStyle.base as? NookStandardCompanionStyle,
            stock.companionStyle.base as? NookStandardCompanionStyle
        )
        XCTAssertEqual(PlaygroundSettings.CompanionDefaults().style, .standard)
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
        settings.topBar.notchClearance = .manual
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
        XCTAssertEqual(configuration.topBar.notchClearance, .manual)
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
        var pill = PlaygroundSettings.Companion(id: "pill", template: .actions, accessibilityLabel: "Actions")
        pill.anchor = .trailing
        pill.alignment = .end
        pill.spacing = 14
        pill.visibility = .both
        pill.outline = .roundedRectangle
        pill.cornerRadius = 6
        pill.backdrop = .solid
        pill.backdropColor = PlaygroundColor(red: 0, green: 0, blue: 1)
        pill.hidesInSettings = false
        var glass = PlaygroundSettings.Companion(id: "glass", template: .chip)
        glass.backdrop = .glass
        glass.visibility = .compact
        glass.outline = .circle
        var settings = PlaygroundSettings()
        settings.companions = [
            pill,
            glass,
            PlaygroundSettings.Companion(id: "pill", template: .button),
            PlaygroundSettings.Companion(id: "", template: .chip),
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

    func testCompanionDefaultsLandOnTheConfiguration() {
        var settings = PlaygroundSettings()
        settings.companionDefaults.size = .large
        settings.companionDefaults.presence = .pop
        settings.companionDefaults.fade = 0.25
        settings.companionDefaults.stroke = true
        settings.companionDefaults.shadow = true
        settings.companionDefaults.hover = .glow

        let configuration = configuration(settings)
        XCTAssertEqual(configuration.companionSize, .large)
        XCTAssertEqual(configuration.companionPresence, .pop)
        XCTAssertEqual(
            configuration.companionStyle.base as? NookStandardCompanionStyle,
            NookStandardCompanionStyle(fade: .standard, stroke: .hairline, shadow: .soft, hover: .glow)
        )
    }

    /// Buttons the size of a surface are surfaces of their own, so a companion of nothing else draws
    /// none around them: it takes the plain style, whatever the defaults say.
    func testSurfaceButtonsMakeAPlainCompanion() {
        var settings = PlaygroundSettings()
        settings.companionDefaults.fade = 0.25
        var leave = PlaygroundSettings.Item(symbol: "phone.down.fill", title: "Leave")
        leave.size = .surface
        var alone = PlaygroundSettings.Companion(id: "leave", items: [leave])
        alone.shadow = true
        let mixed = PlaygroundSettings.Companion(
            id: "mixed",
            items: [leave, PlaygroundSettings.Item(symbol: "mic.fill", title: "Mute")]
        )
        XCTAssertTrue(alone.itemsAreSurfaces)
        XCTAssertFalse(mixed.itemsAreSurfaces, "a control-sized item needs a surface around it")
        XCTAssertFalse(PlaygroundSettings.Companion(id: "empty").itemsAreSurfaces)
        var label = PlaygroundSettings.Item(type: .label, title: "Live")
        label.size = .surface
        XCTAssertFalse(PlaygroundSettings.Companion(id: "label", items: [label]).itemsAreSurfaces)

        XCTAssertTrue(alone.overridesStyle)
        XCTAssertEqual(alone.style(over: settings.companionDefaults), .plain)
        settings.companions = [alone, mixed]
        let companions = configuration(settings).companions
        XCTAssertEqual(companions[0].style?.base as? NookStandardCompanionStyle, .plain)
        XCTAssertNil(companions[1].style)
    }

    /// Taking the lock or gear out of the companions puts it back in the top bar, one control at a
    /// time, and leaves a control the companions never held alone.
    func testLosingTheLockOrGearPutsItBackInTheTopBar() {
        var settings = PlaygroundSettings()
        settings.companions = [PlaygroundSettings.Companion(id: "controls", template: .controls)]
        settings.topBar.showsKeepOpenButton = false
        settings.topBar.showsSettingsButton = false

        var edited = settings
        edited.companions[0].items.removeFirst()
        edited.restoreChromeControls(heldBy: settings.companions)
        XCTAssertTrue(edited.topBar.showsKeepOpenButton, "the lock is gone from the companion")
        XCTAssertFalse(edited.topBar.showsSettingsButton, "the gear is still in it")

        var retyped = settings
        retyped.companions[0].items[1].type = .button
        retyped.restoreChromeControls(heldBy: settings.companions)
        XCTAssertFalse(retyped.topBar.showsKeepOpenButton)
        XCTAssertTrue(retyped.topBar.showsSettingsButton)

        var emptied = settings
        emptied.companions = []
        emptied.restoreChromeControls(heldBy: settings.companions)
        XCTAssertTrue(emptied.topBar.showsKeepOpenButton)
        XCTAssertTrue(emptied.topBar.showsSettingsButton)

        var hidden = PlaygroundSettings()
        hidden.topBar.showsKeepOpenButton = false
        hidden.companions = [PlaygroundSettings.Companion(id: "actions", template: .actions)]
        let before = hidden.companions
        hidden.companions = []
        hidden.restoreChromeControls(heldBy: before)
        XCTAssertFalse(hidden.topBar.showsKeepOpenButton, "a lock hidden on its own stays hidden")
    }

    /// A companion's own values win over the defaults one by one; the ones it leaves unset still
    /// come from the defaults.
    func testACompanionsOwnValuesWinOverTheDefaults() {
        var settings = PlaygroundSettings()
        settings.companionDefaults.fade = 0.25
        settings.companionDefaults.shadow = true
        settings.theme.primaryLabel = PlaygroundColor(red: 0, green: 1, blue: 0)
        var own = PlaygroundSettings.Companion(id: "own", template: .actions)
        own.gap = 18
        own.rowAlignment = .start
        own.size = .small
        own.presence = .slide
        own.fade = 1
        own.hover = .lift
        own.accent = PlaygroundColor(red: 1, green: 0, blue: 0)
        settings.companions = [own, PlaygroundSettings.Companion(id: "plain", template: .chip)]

        let companions = configuration(settings).companions
        XCTAssertEqual(companions[0].gap, 18)
        XCTAssertEqual(companions[0].rowAlignment, .start)
        XCTAssertEqual(companions[0].size, .small)
        XCTAssertEqual(companions[0].presence, .slide)
        XCTAssertEqual(
            companions[0].style?.base as? NookStandardCompanionStyle,
            NookStandardCompanionStyle(shadow: .soft, hover: .lift),
            "its own fade of 1 turns the default fade off, and the default shadow stays"
        )
        let theme = companions[0].theme?(AppState())
        XCTAssertEqual(theme?.accent, PlaygroundColor(red: 1, green: 0, blue: 0).color)
        XCTAssertEqual(theme?.primaryLabel, PlaygroundColor(red: 0, green: 1, blue: 0).color, "on the chrome's theme")

        XCTAssertNil(companions[1].style, "a companion that sets nothing takes the configuration's style")
        XCTAssertNil(companions[1].size)
        XCTAssertNil(companions[1].theme)
    }

    func testTemplatesStartWithTheirItemsAndPlacement() {
        typealias Companion = PlaygroundSettings.Companion
        XCTAssertEqual(Companion(id: "a", template: .actions).items.map(\.displayTitle), ["Previous", "Play", "Next"])
        XCTAssertEqual(Companion(id: "b", template: .button).outline, .circle)
        let controls = Companion(id: "c", template: .controls)
        XCTAssertEqual(controls.anchor, .trailing)
        XCTAssertFalse(controls.hidesInSettings)
        XCTAssertTrue(controls.holdsChromeControls)
        XCTAssertEqual(controls.resolvedLayout, .column, "beside the nook, items stack")
        XCTAssertEqual(Companion(id: "d", template: .chip).items.map(\.type), [.label])
        XCTAssertTrue(Companion(id: "e", template: .empty).items.isEmpty)

        XCTAssertEqual(Companion(id: "", template: .actions).suggestedID, "actions")
        XCTAssertEqual(Companion(id: "", template: .button).suggestedID, "button")
        XCTAssertEqual(Companion(id: "", template: .controls).suggestedID, "controls")
        XCTAssertEqual(Companion(id: "", template: .chip).suggestedID, "status")
        XCTAssertEqual(Companion(id: "", template: .empty).suggestedID, "companion")

        XCTAssertEqual(Companion(id: "", template: .actions).contentSummary, "3 buttons")
        XCTAssertEqual(Companion(id: "", template: .controls).contentSummary, "lock and gear")
        XCTAssertEqual(Companion(id: "", template: .chip).contentSummary, "a label")
        XCTAssertEqual(Companion(id: "", template: .empty).contentSummary, "nothing")

        var row = Companion(id: "r", template: .controls)
        row.layout = .row
        XCTAssertEqual(row.resolvedLayout, .row, "an explicit layout wins")
    }

    func testItemsNameThemselves() {
        typealias Item = PlaygroundSettings.Item
        XCTAssertEqual(Item(action: .collapse).displaySymbol, "chevron.up")
        XCTAssertEqual(Item(action: .collapse).displayTitle, "Collapse")
        XCTAssertEqual(Item(symbol: "star", title: "Star").displaySymbol, "star")
        XCTAssertNil(Item(type: .label).displaySymbol, "a label without a symbol is text only")
        XCTAssertEqual(Item(type: .settings).displayTitle, "Settings")
        XCTAssertEqual(
            Item.summary(of: [Item(), Item(type: .label), Item(type: .keepOpen)]),
            "a button and a label and a chrome control"
        )
        XCTAssertEqual(Item.titles(of: [Item(title: "A"), Item(title: "B")]), "A, B")
        XCTAssertEqual(Item.titles(of: []), "nothing")
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
            PlaygroundSettings.Companion(id: " actions ", template: .actions),
            PlaygroundSettings.Companion(id: "actions", template: .actions),
            PlaygroundSettings.Companion(id: "", template: .actions),
            PlaygroundSettings.Companion(id: "  ", template: .chip),
            PlaygroundSettings.Companion(id: "status", template: .button),
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
        var companion = PlaygroundSettings.Companion(id: "a", template: .chip, accessibilityLabel: "   ")
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

    func testNormalizingKeepsCompanionStyleAndItemsInRange() {
        var settings = PlaygroundSettings()
        settings.companionDefaults.fade = 4
        var item = PlaygroundSettings.Item(symbol: "  star  ", title: " ")
        item.fade = -1
        var companion = PlaygroundSettings.Companion(
            id: "a",
            items: Array(repeating: item, count: PlaygroundSettings.Companion.maximumItems + 3)
        )
        companion.gap = -8
        companion.fade = .nan
        settings.companions = [companion]

        let normalized = settings.normalized()
        XCTAssertEqual(normalized.companionDefaults.fade, 1)
        let result = normalized.companions[0]
        XCTAssertEqual(result.gap, 0)
        XCTAssertEqual(result.fade, 1, "a fade that is not a number is no fade")
        XCTAssertEqual(result.items.count, PlaygroundSettings.Companion.maximumItems)
        XCTAssertEqual(result.items[0].symbol, "star")
        XCTAssertNil(result.items[0].title)
        XCTAssertEqual(result.items[0].fade, 0)
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
