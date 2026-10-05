// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// `NookConfiguration.chromeTheme` reaching the chrome: the configuration's resolved look,
/// the host's theme, the coordinator's surface projection, pins, feedback, companions, and
/// the switch to another module's look.
@MainActor
final class NookThemeWiringTests: XCTestCase {
    /// A module with a fixed configuration.
    private final class ThemedModule: NookModule {
        let descriptor: NookModuleDescriptor
        let configuration: NookConfiguration

        init(id: String, configuration: NookConfiguration = NookConfiguration()) {
            self.descriptor = NookModuleDescriptor(id: id, displayName: id, backgroundPolicy: .stayResident)
            self.configuration = configuration
        }

        func makeConfiguration() -> NookConfiguration { configuration }
    }

    private func makeCoordinator(
        _ modules: [ThemedModule],
        hostTheme: NookTheme? = nil,
        preferences: NookAppearancePreferences = .default,
        appState: AppState = AppState(),
        surface: FakeNookSurface = FakeNookSurface()
    ) -> AppCoordinator {
        // Whatever this machine has saved, start from known preferences. Assigned directly,
        // so nothing is written to the preference store.
        appState.appearancePreferences = preferences
        var host = NookHostConfiguration()
        host.chromeTheme = hostTheme
        for module in modules {
            let captured = module
            host.register(captured.descriptor) { _ in captured }
        }
        host.defaultModule = modules[0].descriptor.id
        let coordinator = AppCoordinator(
            appState: appState,
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: surface,
            systemAppearanceChanges: Empty().eraseToAnyPublisher()
        )
        coordinator.reduceTransparencyProvider = { false }
        coordinator.systemColorSchemeProvider = { .dark }
        return coordinator
    }

    private func configuration(_ theme: NookTheme?) -> NookConfiguration {
        var configuration = NookConfiguration()
        configuration.chromeTheme = theme
        return configuration
    }

    // MARK: - No theme changes nothing

    func testAConfigurationWithoutAThemeResolvesToItsOwnValues() {
        var configuration = NookConfiguration()
        configuration.metrics.edgePadding = 5
        XCTAssertNil(configuration.chromeTheme)
        XCTAssertEqual(configuration.effectiveMetrics, configuration.metrics)
        XCTAssertEqual(configuration.effectiveTypography, .default)
        XCTAssertEqual(configuration.effectiveMotion, .default)
        XCTAssertEqual(configuration.effectiveStyle, NookConfiguration.defaultStyle)
        XCTAssertNil(configuration.effectiveTransitions)
        XCTAssertNil(configuration.paletteOverride)
        XCTAssertEqual(configuration.theme(AppState()), NookResolvedTheme.live(appState: AppState()))
    }

    func testTheStandardThemeProjectsTodaysSurface() {
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([ThemedModule(id: "A")], surface: surface)
        coordinator.applySurfaceLook()
        XCTAssertEqual(surface.style, NookConfiguration.defaultStyle)
        XCTAssertEqual(
            surface.transitionConfiguration.openingAnimation,
            AppCoordinator.defaultTransitions.openingAnimation
        )
        XCTAssertEqual(
            surface.transitionConfiguration.closingAnimation,
            AppCoordinator.defaultTransitions.closingAnimation
        )
        XCTAssertEqual(
            surface.transitionConfiguration.conversionAnimation,
            AppCoordinator.defaultTransitions.conversionAnimation
        )
        XCTAssertEqual(surface.transitionConfiguration.compactContentTransition, .standardCompact)
        XCTAssertEqual(surface.transitionConfiguration.expandedContentTransition, .standardExpanded)
        XCTAssertEqual(surface.ambientWash, .standard)
        XCTAssertNil(surface.chromeShadow)
    }

    func testTheStandardThemesTokensMatchTheSurfaceDefaults() {
        let tokens = NookResolvedTokens.standard
        let transitions = tokens.transitionConfiguration
        XCTAssertEqual(transitions.compactContentTransition, .standardCompact)
        XCTAssertEqual(transitions.expandedContentTransition, .standardExpanded)
        XCTAssertEqual(tokens.ambientWash, .standard)
        XCTAssertEqual(tokens.style.compactTopCornerRadius, NookStyle.standardCompactTopCornerRadius)
        XCTAssertEqual(tokens.style.compactBottomCornerRadius, NookStyle.standardCompactBottomCornerRadius)
        XCTAssertNil(tokens.style.floatingExpandedTopCornerRadius)
        XCTAssertNil(tokens.style.floatingExpandedBottomCornerRadius)
    }

    // MARK: - The configuration's look

    func testAThemeMovesEveryFieldTheHostLeftAtItsDefault() {
        var configuration = configuration(NookTheme(scale: 2))
        XCTAssertEqual(configuration.effectiveMetrics.edgePadding, 16)
        configuration.metrics.edgePadding = 5
        XCTAssertEqual(configuration.effectiveMetrics.edgePadding, 5, "an explicit field wins")
        XCTAssertEqual(configuration.effectiveMetrics.bannerRowSpacing, 16, "the rest follow the theme")
        configuration.metrics.edgePadding = 8
        XCTAssertEqual(configuration.effectiveMetrics.edgePadding, 16, "a field at its default reads as unset")

        configuration.typography.bannerMessage = .system(size: 30)
        XCTAssertEqual(configuration.effectiveTypography.bannerMessage, .system(size: 30))
        XCTAssertEqual(configuration.effectiveTypography.headerIcon, .system(size: 22, weight: .semibold))
        configuration.motion.breadcrumb = .linear(duration: 1)
        XCTAssertEqual(configuration.effectiveMotion.breadcrumb, .linear(duration: 1))
    }

    func testAThemeShapesTheChromeUnlessAStyleIsSet() {
        var configuration = configuration(NookTheme(radius: .factor(2)))
        configuration.chromeTheme?.tokens[.compactBottomRadius] = 10
        XCTAssertEqual(configuration.effectiveStyle.bottomCornerRadius, 48)
        XCTAssertEqual(configuration.effectiveStyle.compactBottomCornerRadius, 10)
        configuration.style = NookStyle(topCornerRadius: 3, bottomCornerRadius: 4)
        XCTAssertEqual(configuration.effectiveStyle, NookStyle(topCornerRadius: 3, bottomCornerRadius: 4))
    }

    func testThemeTransitionsAndContentTransitions() {
        var theme = NookTheme(motion: .calm)
        theme.tokens[.contentEnter] = NookContentTransitionSpec(opacity: 1, blur: 3, scaleY: 0.9)
        theme.tokens[.compactContent] = NookContentTransitionSpec(blur: 0, scaleX: 0.5)
        var configuration = configuration(theme)
        guard let transitions = configuration.effectiveTransitions else { return XCTFail("expected transitions") }
        XCTAssertEqual(transitions.openingAnimation, .spring(response: 0.52, dampingFraction: 1, blendDuration: 0.12))
        XCTAssertEqual(
            transitions.expandedContentTransition,
            NookContentTransition(blurRadius: 3, scale: 0.9, fades: false)
        )
        XCTAssertEqual(transitions.compactContentTransition, NookContentTransition(blurRadius: 0, scale: 0.5))
        configuration.transitions = NookTransitionConfiguration(openingAnimation: .linear(duration: 2))
        XCTAssertEqual(configuration.effectiveTransitions?.openingAnimation, .linear(duration: 2))
    }

    func testAPaletteClosureStillReplacesTheThemesPalette() {
        var configuration = configuration(NookTheme(accent: "#3399FF"))
        let appState = AppState()
        XCTAssertEqual(configuration.theme(appState).accent, NookRGBA(hex: "#3399FF")!.color)
        let custom = NookResolvedTheme(
            primaryLabel: .red,
            secondaryLabel: .red,
            tertiaryLabel: .red,
            quaternaryLabel: .red,
            subtleFill: .red,
            subtleStroke: .red,
            headerInactiveIcon: .red
        )
        configuration.theme = { _ in custom }
        XCTAssertEqual(configuration.theme(appState), custom)
    }

    // MARK: - Host theme

    func testTheHostThemeReachesModulesWithoutTheirOwn() async {
        let host = NookTheme(accent: "#FF0000")
        let own = NookTheme(accent: "#00FF00")
        let coordinator = makeCoordinator(
            [ThemedModule(id: "A"), ThemedModule(id: "B", configuration: configuration(own))],
            hostTheme: host
        )
        XCTAssertEqual(coordinator.moduleHost.configuration.chromeTheme, host)
        coordinator.switchModule(to: "B")
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(
            coordinator.moduleHost.configuration.chromeTheme,
            own,
            "a module's own theme replaces the host's"
        )
    }

    // MARK: - Surface projection

    func testReloadAndLaunchApplyTheThemesSurfaceLook() {
        var theme = NookTheme(radius: .large)
        theme.tokens[.chrome] = NookShadowSpec(color: .black(opacity: 0.5), radius: 10, y: 2)
        theme.tokens[.ambientWashTop] = 0.5
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ThemedModule(id: "A", configuration: configuration(theme))],
            surface: surface
        )
        coordinator.reloadActiveConfiguration()
        XCTAssertEqual(surface.style.bottomCornerRadius, 24 * 1.4)
        XCTAssertEqual(surface.chromeShadow, NookChromeShadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 2))
        XCTAssertEqual(surface.ambientWash, NookAmbientWash(opacities: [0.5, 0.16, 0.06, 0.02]))
    }

    func testASwitchAppliesTheIncomingModulesLook() async {
        var flat = NookTheme(palette: .light)
        flat.tokens[.chromeBottomRadius] = 8
        flat.tokens[.chrome] = NookShadowSpec()
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ThemedModule(id: "A"), ThemedModule(id: "B", configuration: configuration(flat))],
            surface: surface
        )
        coordinator.applySurfaceLook()
        coordinator.syncNotchBackdrop()
        XCTAssertEqual(surface.style, NookConfiguration.defaultStyle)
        XCTAssertNil(surface.chromeShadow)
        XCTAssertNil(surface.chromeAppearance)

        coordinator.switchModule(to: "B")
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.style.bottomCornerRadius, 8)
        XCTAssertNotNil(surface.chromeShadow)
        XCTAssertEqual(surface.chromeAppearance?.name, .aqua, "the theme pins the window to light")
        XCTAssertEqual(surface.backdrop, .solid(.white), "the solid surface in the pinned light palette")

        coordinator.switchModule(to: "A")
        await coordinator.drainLifecycleForTesting()
        XCTAssertEqual(surface.style, NookConfiguration.defaultStyle)
        XCTAssertNil(surface.chromeShadow)
        XCTAssertNil(surface.chromeAppearance)
    }

    func testPinsDecideTheBackdropWithoutChangingThePersonsChoices() {
        let appState = AppState()
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ThemedModule(id: "A", configuration: configuration(NookTheme(surface: .solid)))],
            preferences: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .liquidGlass),
            appState: appState,
            surface: surface
        )
        coordinator.syncNotchBackdrop()
        XCTAssertEqual(surface.backdrop, .solid(.black))
        XCTAssertEqual(appState.appearancePreferences.surfaceStyle, .liquidGlass)
    }

    // MARK: - Feedback

    func testFeedbackFollowsTheAccent() {
        let appState = AppState()
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator([ThemedModule(id: "A")], appState: appState, surface: surface)
        coordinator.playFeedback(.pulse)
        XCTAssertEqual(
            surface.lastFeedbackStyle?.color,
            Color(nsColor: .controlAccentColor),
            "the standard theme with the System accent is the macOS accent, as before"
        )
        // The one intentional difference from before themes: an accent the person picked now
        // colors the cue too, as the theming guide always said.
        appState.appearancePreferences.accentPreset = .teal
        coordinator.playFeedback(.pulse)
        XCTAssertEqual(surface.lastFeedbackStyle?.color, NookAccentPreset.teal.color())
    }

    func testAThemeCanTintFeedbackItsOwnWay() {
        var theme = NookTheme()
        theme.tokens[.feedbackTint] = "#FF8800"
        let surface = FakeNookSurface()
        let coordinator = makeCoordinator(
            [ThemedModule(id: "A", configuration: configuration(theme))],
            surface: surface
        )
        coordinator.playFeedback()
        XCTAssertEqual(surface.lastFeedbackStyle?.color, NookRGBA(hex: "#FF8800")!.color)
    }

    // MARK: - Companions

    func testTheThemesHoverWashReachesBuiltInStylesOnly() {
        var theme = NookTheme()
        theme.tokens[.hoverWash] = .black(opacity: 1)
        let coordinator = makeCoordinator([ThemedModule(id: "A")])
        let washed = AnyNookCompanionStyle.standard(hover: .init(wash: 0.1))
        let themed = coordinator.themedCompanionStyle(washed, theme: theme)
        XCTAssertEqual((themed.base as? NookStandardCompanionStyle)?.hover.washColor, Color.black)

        let explicit = AnyNookCompanionStyle.standard(hover: .init(wash: 0.1, washColor: .red))
        let kept = coordinator.themedCompanionStyle(explicit, theme: theme)
        XCTAssertEqual((kept.base as? NookStandardCompanionStyle)?.hover.washColor, Color.red)

        let untouched = coordinator.themedCompanionStyle(washed, theme: .standard)
        XCTAssertEqual((untouched.base as? NookStandardCompanionStyle)?.hover.washColor, Color.white)
    }

    func testTheProjectedCompanionsWashInTheThemesColor() {
        var theme = NookTheme()
        theme.tokens[.hoverWash] = .black(opacity: 1)
        var configuration = configuration(theme)
        configuration.companionStyle = .standard(hover: .init(wash: 0.2))
        configuration.addCompanion(id: "one") { Text("one") }
        let surface = FakeNookSurface()
        _ = makeCoordinator([ThemedModule(id: "A", configuration: configuration)], surface: surface)
        let style = surface.companions.first?.style.base as? NookStandardCompanionStyle
        XCTAssertEqual(style?.hover.washColor, Color.black)
    }

    // MARK: - Locks in Settings

    func testThePinnedSettingModifierLeavesOutPinnedControls() {
        XCTAssertTrue(NookPinnedSettingModifier(isPinned: true).isPinned)
        XCTAssertEqual(NookTheme(palette: .dark).effectivePreferences(.default).chromePalette, .dark)
    }
}
