// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Combine
import Foundation
import NookSurface
import XCTest

@testable import NookKit

/// Live themes: a source replaced in code, a watched theme file, and the chrome following both.
@MainActor
final class NookThemeSourceTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("opennook-theme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ theme: NookTheme, to url: URL, atomically: Bool = true) throws {
        try theme.jsonData().write(to: url, options: atomically ? .atomic : [])
    }

    /// Waits up to `timeout` seconds, letting the main queue run, for `condition`.
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testReplacingValidatesAndPublishesAfterTheChange() {
        let source = NookThemeSource(NookTheme(accent: "#112233"))
        var seen: [NookTheme] = []
        let subscription = source.changes.sink { _ in seen.append(source.theme) }
        source.replace(NookTheme(scale: 9))
        XCTAssertEqual(source.theme.scale, 2, "brought into range")
        XCTAssertEqual(source.issues.map(\.path), ["scale"])
        XCTAssertEqual(seen, [source.theme], "a subscriber reads the new theme")
        source.replace(NookTheme(scale: 2))
        XCTAssertEqual(seen.count, 1, "an unchanged theme publishes nothing")
        subscription.cancel()
    }

    func testAWatchedFileLoadsNowAndOnEverySave() async throws {
        let url = folder.appendingPathComponent("theme.json")
        try write(NookTheme(accent: "#112233"), to: url)
        let source = NookThemeSource.watching(fileAt: url, debounce: .milliseconds(20))
        XCTAssertEqual(source.theme.accent, "#112233")
        XCTAssertEqual(source.fileURL, url)

        try write(NookTheme(accent: "#445566"), to: url)
        await waitUntil { source.theme.accent == "#445566" }
        XCTAssertEqual(source.theme.accent, "#445566", "a save by replacement")

        try write(NookTheme(accent: "#778899"), to: url, atomically: false)
        await waitUntil { source.theme.accent == "#778899" }
        XCTAssertEqual(source.theme.accent, "#778899", "a save in place")
    }

    func testAFileThatFailsToLoadKeepsTheLastGoodTheme() async throws {
        let url = folder.appendingPathComponent("theme.json")
        try write(NookTheme(accent: "#112233"), to: url)
        let source = NookThemeSource.watching(fileAt: url, debounce: .milliseconds(20))
        try Data("{ not json".utf8).write(to: url, options: .atomic)
        await waitUntil { source.loadError != nil }
        XCTAssertNotNil(source.loadError)
        XCTAssertEqual(source.theme.accent, "#112233")

        try write(NookTheme(accent: "#ABCDEF"), to: url)
        await waitUntil { source.loadError == nil }
        XCTAssertEqual(source.theme.accent, "#ABCDEF")
    }

    func testAMissingFileReportsAndUsesTheStandardTheme() {
        let source = NookThemeSource.watching(fileAt: folder.appendingPathComponent("absent.json"))
        XCTAssertEqual(source.theme, .standard)
        XCTAssertNotNil(source.loadError)
    }

    // MARK: - The chrome follows

    private final class Module: NookModule {
        let descriptor = NookModuleDescriptor(id: "A", displayName: "A")
        let configuration: NookConfiguration
        init(_ configuration: NookConfiguration) { self.configuration = configuration }
        func makeConfiguration() -> NookConfiguration { configuration }
    }

    private func coordinator(
        _ configuration: NookConfiguration,
        hostSource: NookThemeSource? = nil,
        surface: FakeNookSurface
    ) -> AppCoordinator {
        var host = NookHostConfiguration()
        host.chromeThemeSource = hostSource
        let module = Module(configuration)
        host.register(module.descriptor) { _ in module }
        let appState = AppState()
        appState.appearancePreferences = .default
        let coordinator = AppCoordinator(
            appState: appState,
            moduleHost: ModuleHost(registry: host.makeRegistry()),
            surface: surface,
            systemAppearanceChanges: Empty().eraseToAnyPublisher()
        )
        coordinator.reduceTransparencyProvider = { false }
        coordinator.systemColorSchemeProvider = { .dark }
        coordinator.applySurfaceLook()
        return coordinator
    }

    func testTheChromeFollowsAConfigurationsSource() {
        let source = NookThemeSource()
        var configuration = NookConfiguration()
        configuration.chromeThemeSource = source
        configuration.chromeTheme = NookTheme(radius: .none)  // the source wins over it
        let surface = FakeNookSurface()
        let coordinator = coordinator(configuration, surface: surface)
        XCTAssertEqual(surface.style, NookConfiguration.defaultStyle)

        source.replace(NookTheme(radius: .factor(2)))
        XCTAssertEqual(surface.style.bottomCornerRadius, 48)
        XCTAssertEqual(coordinator.moduleHost.configuration.chromeTheme?.radius, .factor(2))
    }

    func testTheChromeFollowsTheHostsSource() {
        let source = NookThemeSource(NookTheme(radius: .factor(2)))
        let surface = FakeNookSurface()
        let coordinator = coordinator(NookConfiguration(), hostSource: source, surface: surface)
        XCTAssertEqual(surface.style.bottomCornerRadius, 48)
        source.replace(.standard)
        XCTAssertEqual(surface.style, NookConfiguration.defaultStyle)
        withExtendedLifetime(coordinator) {}
    }
}
