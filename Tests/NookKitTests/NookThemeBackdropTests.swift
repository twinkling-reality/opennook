// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import Combine
import NookSurface
import SwiftUI
import XCTest

@testable import NookKit

/// A theme's backdrop descriptions turned into `NookBackdrop`s, and painted by the chrome.
@MainActor
final class NookThemeBackdropTests: XCTestCase {
    private func context(
        _ style: NookSurfaceStyle,
        dark: Bool = true,
        strength: Double = 1,
        reduceTransparency: Bool = false
    ) -> NookBackdropContext {
        NookBackdropContext(
            preferences: NookAppearancePreferences(
                chromePalette: dark ? .dark : .light,
                surfaceStyle: style,
                backdropStrength: strength
            ),
            colorScheme: dark ? .dark : .light,
            reduceTransparency: reduceTransparency,
            state: .expanded,
            form: .notch
        )
    }

    private let gradient = NookGradientSpec(colors: ["#101014", .black(opacity: 1)])

    func testTheStandardThemeLeavesTheBackdropToTheFramework() {
        for style in NookSurfaceStyle.allCases {
            XCTAssertNil(NookTheme.standard.backdrop(in: context(style)))
        }
        var theme = NookTheme()
        theme.backdrops.solid = .framework
        XCTAssertNil(theme.backdrop(in: context(.solid)))
    }

    func testSolidColorsResolveForTheAppearance() {
        var theme = NookTheme()
        theme.backdrops.solid = .solid("{color.surface}")
        XCTAssertEqual(theme.backdrop(in: context(.solid)), .solid(.black))
        XCTAssertEqual(theme.backdrop(in: context(.solid, dark: false)), .solid(.white))
    }

    func testVibrancyScalesWithStrengthAndCollapsesUnderReduceTransparency() {
        var theme = NookTheme()
        theme.backdrops.translucent = .vibrancy(
            .init(
                material: .hudWindow,
                darken: NookAdaptiveNumber(dark: 0.5, light: 0.2),
                darkenColor: .white(opacity: 1)
            )
        )
        XCTAssertEqual(
            theme.backdrop(in: context(.translucent, strength: 0.5)),
            .vibrancy(
                .init(material: .hudWindow, blendingMode: .behindWindow, darkenOpacity: 0.25, darkenColor: .white)
            )
        )
        XCTAssertNil(theme.backdrop(in: context(.translucent, reduceTransparency: true)))
    }

    func testGlassCarriesEverySurfaceKnob() {
        var theme = NookTheme(accent: "#3399FF")
        theme.backdrops.liquidGlass = .liquidGlass(
            .init(
                tint: "accent",
                tintStrength: 0.4,
                highlight: 0.5,
                shading: .init(gradient: gradient),
                scalesWithStrength: false,
                variant: .clear,
                fallbackMaterial: .popover,
                highlightColor: "#FF0000",
                rimWidth: 2
            )
        )
        guard case .liquidGlass(let glass)? = theme.backdrop(in: context(.liquidGlass, strength: 0.5)) else {
            return XCTFail("expected glass")
        }
        XCTAssertEqual(glass.tint, NookRGBA(hex: "#3399FF")!.color)
        XCTAssertEqual(glass.tintStrength, 0.4, "not scaled by strength")
        XCTAssertEqual(glass.highlightStrength, 0.5)
        XCTAssertEqual(glass.variant, .clear)
        XCTAssertEqual(glass.fallbackMaterial, .popover)
        XCTAssertEqual(glass.highlightColor, NookRGBA(hex: "#FF0000")!.color)
        XCTAssertEqual(glass.rimWidth, 2)
        XCTAssertEqual(glass.shading?.startPoint, .top)
    }

    func testGradientsAndMeshes() {
        var theme = NookTheme()
        theme.backdrops.solid = .linearGradient(.init(gradient: gradient, start: .top, end: .bottom))
        let expected = Gradient(stops: [
            .init(color: NookRGBA(hex: "#101014")!.color, location: 0), .init(color: .black, location: 1),
        ])
        XCTAssertEqual(theme.backdrop(in: context(.solid)), .gradient(.linear(expected)))
        theme.backdrops.solid = .ellipticalGradient(.init(gradient: gradient, endRadius: 0.8))
        XCTAssertEqual(theme.backdrop(in: context(.solid)), .gradient(.elliptical(expected, endRadiusFraction: 0.8)))
        theme.backdrops.solid = .angularGradient(.init(gradient: gradient))
        XCTAssertEqual(theme.backdrop(in: context(.solid)), .gradient(.angular(expected)))
        theme.backdrops.solid = .mesh(
            .init(
                width: 2,
                height: 2,
                points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                colors: ["#000000", "#111111", "#222222", "#333333"]
            )
        )
        guard case .meshGradient? = theme.backdrop(in: context(.solid)) else { return XCTFail("expected a mesh") }
    }

    func testCustomBackdropsComeFromTheHostOrFallBack() {
        var theme = NookTheme()
        theme.backdrops.solid = .custom(id: "aurora", fallback: .solid("#112233"))
        let custom = NookBackdrop.custom(.init(id: "aurora") { _ in Color.purple })
        XCTAssertEqual(theme.backdrop(in: context(.solid), customBackdrops: ["aurora": { _ in custom }]), custom)
        XCTAssertEqual(theme.backdrop(in: context(.solid)), .solid(NookRGBA(hex: "#112233")!.color))
        theme.backdrops.solid = .unknown(kind: "shader", fallback: nil)
        XCTAssertNil(theme.backdrop(in: context(.solid)), "an unknown kind with no fallback is the framework's")
    }

    func testNewDescriptionFieldsRoundTrip() throws {
        let descriptions: [NookBackdropDescription] = [
            .vibrancy(.init(darken: 0.3, darkenColor: .white(opacity: 1))),
            .liquidGlass(.init(variant: .clear, fallbackMaterial: .menu, highlightColor: "accent", rimWidth: 1.5)),
            .ellipticalGradient(.init(gradient: gradient, center: .top, startRadius: 0.1, endRadius: 0.9)),
        ]
        for description in descriptions {
            let data = try JSONEncoder().encode(description)
            XCTAssertEqual(try JSONDecoder().decode(NookBackdropDescription.self, from: data), description)
        }
    }

    // MARK: - On the chrome

    private final class Module: NookModule {
        let descriptor = NookModuleDescriptor(id: "A", displayName: "A")
        let configuration: NookConfiguration
        init(_ configuration: NookConfiguration) { self.configuration = configuration }
        func makeConfiguration() -> NookConfiguration { configuration }
    }

    private func coordinator(
        _ configuration: NookConfiguration,
        preferences: NookAppearancePreferences,
        surface: FakeNookSurface
    ) -> AppCoordinator {
        var host = NookHostConfiguration()
        let module = Module(configuration)
        host.register(module.descriptor) { _ in module }
        let appState = AppState()
        appState.appearancePreferences = preferences
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

    func testTheChromePaintsTheThemesBackdropForThePersonsSurface() {
        var configuration = NookConfiguration()
        var theme = NookTheme()
        theme.backdrops.translucent = .linearGradient(.init(gradient: gradient))
        configuration.chromeTheme = theme
        let surface = FakeNookSurface()
        let translucent = coordinator(
            configuration,
            preferences: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .translucent),
            surface: surface
        )
        translucent.syncNotchBackdrop()
        guard case .gradient = surface.backdrop else { return XCTFail("expected the theme's gradient") }
        XCTAssertNil(surface.companionBackdrop, "companions inherit the chrome's")

        let solidSurface = FakeNookSurface()
        let solid = coordinator(
            configuration,
            preferences: NookAppearancePreferences(chromePalette: .dark),
            surface: solidSurface
        )
        solid.syncNotchBackdrop()
        XCTAssertEqual(solidSurface.backdrop, .solid(.black), "no description for solid: the framework's")
    }

    func testAHostResolverStillWins() {
        var configuration = NookConfiguration()
        var theme = NookTheme()
        theme.backdrops.solid = .solid("#FF0000")
        configuration.chromeTheme = theme
        configuration.chromeBehavior.backdrop = { _ in .solid(.green) }
        let surface = FakeNookSurface()
        var host = NookHostConfiguration()
        host.chromeBehavior = configuration.chromeBehavior
        let module = Module(configuration)
        host.register(module.descriptor) { _ in module }
        let coordinator = AppCoordinator(
            appState: AppState(),
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: surface,
            systemAppearanceChanges: Empty().eraseToAnyPublisher()
        )
        coordinator.reduceTransparencyProvider = { false }
        coordinator.syncNotchBackdrop()
        XCTAssertEqual(surface.backdrop, .solid(.green))
    }

    func testTheThemesGlassShadingAppliesUnlessTheHostChoseOne() {
        var configuration = NookConfiguration()
        var theme = NookTheme()
        theme.backdrops.glassShading = .notchFade
        configuration.chromeTheme = theme
        let surface = FakeNookSurface()
        let coordinator = coordinator(
            configuration,
            preferences: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .liquidGlass),
            surface: surface
        )
        coordinator.syncNotchBackdrop()
        let expected = NookBackdropMapping.notchBackdrop(
            preferences: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .liquidGlass),
            effectiveColorScheme: .dark,
            reduceTransparency: false,
            glassShading: .notchFade,
            state: surface.state
        )
        XCTAssertEqual(surface.backdrop, expected)
    }
}
