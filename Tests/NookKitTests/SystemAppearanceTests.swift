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

/// A macOS light/dark change re-applies the backdrop and the theme right away under the
/// `.followSystem` palette, instead of waiting for the next expand or collapse.
@MainActor
final class SystemAppearanceTests: XCTestCase {
    /// The system scheme the coordinator reads, changed by the test.
    @MainActor
    private final class SchemeBox {
        var scheme: ColorScheme = .dark
    }

    private func pumpMainRunLoop() async {
        // The appearance sink hops through `RunLoop.main`; sleeping lets it run.
        try? await Task.sleep(nanoseconds: 30_000_000)
    }

    func testAppearanceChangeReappliesBackdropAndTheme() async {
        let appState = AppState()
        appState.appearancePreferences = NookAppearancePreferences(
            chromePalette: .followSystem,
            surfaceStyle: .liquidGlass
        )
        var host = NookHostConfiguration()
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) { NookConfiguration() }
        let changes = PassthroughSubject<Void, Never>()
        let surface = FakeNookSurface()
        let coordinator = AppCoordinator(
            appState: appState,
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: surface,
            systemAppearanceChanges: changes.eraseToAnyPublisher()
        )
        // Pinned rather than read off the machine (a CI runner has Reduce Transparency on).
        coordinator.reduceTransparencyProvider = { false }
        let box = SchemeBox()
        coordinator.systemColorSchemeProvider = { box.scheme }
        func expected(_ scheme: ColorScheme) -> NookBackdrop {
            NookBackdropMapping.notchBackdrop(
                preferences: appState.appearancePreferences,
                effectiveColorScheme: scheme,
                reduceTransparency: false
            )
        }

        coordinator.syncNotchBackdrop()
        XCTAssertEqual(surface.backdrop, expected(.dark))

        var themeInvalidations = 0
        let subscription = appState.objectWillChange.sink { themeInvalidations += 1 }
        defer { subscription.cancel() }

        box.scheme = .light
        changes.send()
        await pumpMainRunLoop()

        XCTAssertEqual(surface.backdrop, expected(.light), "the backdrop follows the new system appearance")
        XCTAssertNotEqual(expected(.light), expected(.dark))
        XCTAssertGreaterThan(themeInvalidations, 0, "views observing AppState re-render and re-resolve the theme")
    }
}
