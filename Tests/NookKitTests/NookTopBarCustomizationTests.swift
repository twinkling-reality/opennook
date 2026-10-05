// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI
import XCTest

@testable import NookKit

/// The top bar's glyphs, its leading icon view, and a host bar that replaces it while
/// keeping the framework bar's behavior.
@MainActor
final class NookTopBarCustomizationTests: XCTestCase {
    /// Where a host view records what it was handed.
    @MainActor
    private final class Capture {
        var context: NookTopBarContext?
        var environment: EnvironmentValues?
        var iconColors: [Color] = []
        var keepOpenToggles = 0
    }

    private struct EnvironmentProbe: View {
        let capture: Capture
        @Environment(\.self) private var environment

        var body: some View {
            Color.clear
                .frame(width: 10, height: 10)
                .onAppear { capture.environment = environment }
        }
    }

    /// A host bar that keeps its context, as a real one would.
    private struct HostBar: View {
        let bar: NookTopBarContext
        let capture: Capture

        var body: some View {
            HStack {
                Text(bar.breadcrumb ?? bar.title)
                Spacer()
                Button("Settings", systemImage: bar.symbols.settings) { bar.toggleSettings() }
                EnvironmentProbe(capture: capture)
            }
            .labelStyle(.iconOnly)
            .onAppear { capture.context = bar }
        }
    }

    private func render(_ view: some View) {
        _ = ImageRenderer(content: view.frame(width: 480, height: 200)).nsImage
    }

    private func expandedView(
        appState: AppState,
        topBar: NookTopBarConfiguration,
        motion: NookChromeMotion = .default,
        moduleSwitcher: NookModuleSwitcher? = nil,
        capture: Capture
    ) -> NookExpandedView {
        NookExpandedView(
            appState: appState,
            services: AppServices(),
            toggleKeepOpen: { capture.keepOpenToggles += 1 },
            hide: {},
            resetAllSettings: {},
            home: { AnyView(Color.clear) },
            topBar: topBar,
            motion: motion,
            moduleSwitcher: moduleSwitcher
        )
    }

    // MARK: - Symbols

    func testSymbolsDefaultToTodaysGlyphs() {
        let symbols = NookChromeSymbols.default
        XCTAssertEqual(symbols.keepOpenOn, "lock.fill")
        XCTAssertEqual(symbols.keepOpenOff, "lock.open")
        XCTAssertEqual(symbols.keepOpen(true), "lock.fill")
        XCTAssertEqual(symbols.keepOpen(false), "lock.open")
        XCTAssertEqual(symbols.settings, "gearshape")
        XCTAssertEqual(symbols.breadcrumbSeparator, "chevron.right")
        XCTAssertNil(symbols.back, "the back control keeps the leading identity glyph")
        XCTAssertEqual(symbols.moduleSwitcherIndicator, "chevron.down")
        XCTAssertEqual(symbols.moduleSwitcherActive, "checkmark")
        XCTAssertEqual(NookTopBarConfiguration().symbols, .default)
        XCTAssertEqual(EnvironmentValues().nookChromeSymbols, .default)
    }

    func testTopBarDefaultsLeaveTheFrameworkBar() {
        let topBar = NookTopBarConfiguration()
        XCTAssertNil(topBar.content)
        XCTAssertNil(topBar.leadingIconView)
    }

    /// The configured glyphs reach the expanded content (and so the standalone lock and gear)
    /// and the compact slots.
    func testSymbolsReachTheChromeEnvironment() throws {
        var topBar = NookTopBarConfiguration()
        topBar.symbols.keepOpenOn = "pin.fill"
        topBar.symbols.settings = "slider.horizontal.3"

        let expanded = Capture()
        var configuration = NookConfiguration()
        configuration.topBar = topBar
        configuration.setHome { EnvironmentProbe(capture: expanded) }
        render(
            NookExpandedView(
                appState: AppState(),
                services: AppServices(),
                toggleKeepOpen: {},
                hide: {},
                resetAllSettings: {},
                home: configuration.home,
                topBar: topBar
            )
        )
        XCTAssertEqual(try XCTUnwrap(expanded.environment).nookChromeSymbols, topBar.symbols)

        let compact = Capture()
        configuration.setCompactLeading { EnvironmentProbe(capture: compact) }
        var host = NookHostConfiguration()
        host.register(NookModuleDescriptor(id: "A", displayName: "A")) { configuration }
        let moduleHost = ModuleHost(registry: host.makeRegistry())
        render(
            ModuleRouterCompactView(
                moduleHost: moduleHost,
                appState: AppState(),
                activities: moduleHost.registry.liveActivities,
                slot: .leading
            )
        )
        XCTAssertEqual(try XCTUnwrap(compact.environment).nookChromeSymbols, topBar.symbols)
    }

    /// The configured glyphs reach companion content, so a lock or gear placed in a
    /// companion draws the same glyphs as the top bar.
    func testSymbolsReachCompanions() throws {
        var symbols = NookChromeSymbols.default
        symbols.keepOpenOff = "pin"
        symbols.settings = "slider.horizontal.3"
        let capture = Capture()
        let appState = AppState()
        render(
            NookCompanionHost(
                appState: appState,
                companion: NookCompanion(id: "probe") { EnvironmentProbe(capture: capture) },
                theme: { NookResolvedTheme.live(appState: $0) },
                services: AppServices(),
                labels: .default,
                metrics: .default,
                motion: .default,
                typography: .default,
                branding: .default,
                chromeActions: NookChromeActions(toggleKeepOpen: {}, toggleSettings: {}, collapse: {}),
                symbols: symbols
            )
        )
        XCTAssertEqual(try XCTUnwrap(capture.environment).nookChromeSymbols, symbols)
    }

    // MARK: - Leading icon view

    /// A leading icon view is drawn in place of the symbol and the mark, in the idle icon
    /// color on home and in the back control's color in Settings.
    func testLeadingIconViewReplacesTheIcon() {
        let capture = Capture()
        var topBar = NookTopBarConfiguration(leadingIcon: "house")
        topBar.setLeadingIcon { color in
            capture.iconColors.append(color)
            return Color.clear
        }
        let appState = AppState()

        render(expandedView(appState: appState, topBar: topBar, capture: capture))
        XCTAssertFalse(capture.iconColors.isEmpty, "drawn beside the title on home")
        XCTAssertEqual(capture.iconColors.last, NookResolvedTheme.live(appState: appState).headerInactiveIcon)

        capture.iconColors = []
        appState.showSettings()
        render(expandedView(appState: appState, topBar: topBar, capture: capture))
        XCTAssertFalse(capture.iconColors.isEmpty, "drawn as the back control in Settings")
    }

    /// A back symbol wins over the leading icon view on the back control only.
    func testBackSymbolReplacesTheBackGlyph() {
        let capture = Capture()
        var topBar = NookTopBarConfiguration()
        topBar.symbols.back = "chevron.left"
        topBar.setLeadingIcon { color in
            capture.iconColors.append(color)
            return Color.clear
        }
        let appState = AppState()
        appState.showSettings()

        render(expandedView(appState: appState, topBar: topBar, capture: capture))
        XCTAssertTrue(capture.iconColors.isEmpty)
    }

    // MARK: - Host bar

    /// A host bar replaces the framework bar and gets the bar's state.
    func testHostBarReceivesTheBarState() throws {
        let capture = Capture()
        var configuration = NookConfiguration()
        configuration.topBar.leadingTitle = { $0.isSettingsView ? "Prefs" : "Today" }
        configuration.topBar.leadingIcon = "calendar"
        configuration.topBar.symbols.settings = "slider.horizontal.3"
        configuration.setTopBar { bar in
            HostBar(bar: bar, capture: capture)
        }
        let appState = AppState()
        appState.moduleBreadcrumb = "March"

        render(expandedView(appState: appState, topBar: configuration.topBar, capture: capture))

        let bar = try XCTUnwrap(capture.context, "the host bar rendered")
        XCTAssertEqual(bar.title, "Today")
        XCTAssertEqual(bar.leadingIcon, "calendar")
        XCTAssertEqual(bar.viewMode, .home)
        XCTAssertFalse(bar.isSettingsShown)
        XCTAssertTrue(bar.showsSettings)
        XCTAssertEqual(bar.breadcrumb, "March")
        XCTAssertTrue(bar.canGoBack)
        XCTAssertEqual(bar.isKeepOpen, appState.keepNookOpen)
        XCTAssertNil(bar.moduleSwitcher)
        XCTAssertEqual(bar.symbols.settings, "slider.horizontal.3")
        // The host bar renders in the chrome environment.
        XCTAssertEqual(try XCTUnwrap(capture.environment).nookChromeSymbols.settings, "slider.horizontal.3")
    }

    /// The host bar's actions do what the framework bar's controls do.
    func testHostBarActionsBehaveLikeTheFrameworkBar() throws {
        let capture = Capture()
        var topBar = NookTopBarConfiguration()
        topBar.setContent { bar in
            capture.context = bar
            return Color.clear
        }
        let appState = AppState()
        render(expandedView(appState: appState, topBar: topBar, capture: capture))
        var bar = try XCTUnwrap(capture.context)

        bar.toggleKeepOpen()
        XCTAssertEqual(capture.keepOpenToggles, 1, "the chrome's keep-open action")

        XCTAssertFalse(bar.canGoBack)
        bar.toggleSettings()
        XCTAssertTrue(appState.isSettingsView)

        render(expandedView(appState: appState, topBar: topBar, capture: capture))
        bar = try XCTUnwrap(capture.context)
        XCTAssertTrue(bar.isSettingsShown)
        XCTAssertTrue(bar.canGoBack)
        bar.goBack()
        XCTAssertTrue(appState.isHomeView, "back leaves Settings")

        appState.moduleBreadcrumb = "Detail"
        render(expandedView(appState: appState, topBar: topBar, capture: capture))
        bar = try XCTUnwrap(capture.context)
        bar.goBack()
        XCTAssertNil(appState.moduleBreadcrumb, "back clears the breadcrumb")
        XCTAssertTrue(appState.isHomeView)
    }

    /// Without Settings the host bar's gear action does nothing, as the framework bar has no
    /// gear then.
    func testHostBarSettingsActionRespectsShowsSettings() throws {
        let capture = Capture()
        var topBar = NookTopBarConfiguration(showsSettings: false)
        topBar.setContent { bar in
            capture.context = bar
            return Color.clear
        }
        let appState = AppState()
        render(expandedView(appState: appState, topBar: topBar, capture: capture))
        let bar = try XCTUnwrap(capture.context)

        XCTAssertFalse(bar.showsSettings)
        bar.toggleSettings()
        XCTAssertTrue(appState.isHomeView)
    }

    /// A multi-module host that put switching in the top bar hands the switcher to its bar.
    func testHostBarGetsTheModuleSwitcher() throws {
        let capture = Capture()
        var topBar = NookTopBarConfiguration()
        topBar.setContent { bar in
            capture.context = bar
            return Color.clear
        }
        var switchedTo: String?
        let switcher = NookModuleSwitcher(
            modules: [
                NookModuleDescriptor(id: "a", displayName: "A"),
                NookModuleDescriptor(id: "b", displayName: "B"),
            ],
            activeID: "a",
            attentionIDs: ["b"],
            switchTo: { switchedTo = $0 }
        )

        render(expandedView(appState: AppState(), topBar: topBar, moduleSwitcher: switcher, capture: capture))

        let received = try XCTUnwrap(capture.context?.moduleSwitcher)
        XCTAssertEqual(received.modules.map(\.id), ["a", "b"])
        XCTAssertEqual(received.activeID, "a")
        XCTAssertEqual(received.attentionIDs, ["b"])
        received.switchTo("b")
        XCTAssertEqual(switchedTo, "b")
    }

    /// `NookConfiguration.setTopBar` is the top bar's `setContent`.
    func testSetTopBarSetsTheContent() {
        var configuration = NookConfiguration()
        XCTAssertNil(configuration.topBar.content)
        configuration.setTopBar { _ in Color.clear }
        XCTAssertNotNil(configuration.topBar.content)
    }

    /// A context built for a preview reports its state and runs the given actions.
    func testPreviewContext() {
        @MainActor final class Log { var ran: [String] = [] }
        let log = Log()
        let bar = NookTopBarContext(
            title: "Home",
            viewMode: .settings,
            moduleSwitcher: NookTopBarContext.ModuleSwitcher(
                modules: [NookModuleDescriptor(id: "a", displayName: "A")],
                activeID: "a",
                switchTo: { log.ran.append("switch \($0)") }
            ),
            toggleKeepOpen: { log.ran.append("lock") },
            toggleSettings: { log.ran.append("gear") },
            goBack: { log.ran.append("back") }
        )
        XCTAssertTrue(bar.isSettingsShown)
        XCTAssertTrue(bar.canGoBack)
        XCTAssertNil(bar.breadcrumb)
        XCTAssertEqual(bar.moduleSwitcher?.activeDescriptor?.displayName, "A")
        bar.toggleKeepOpen()
        bar.toggleSettings()
        bar.goBack()
        bar.moduleSwitcher?.switchTo("a")
        XCTAssertEqual(log.ran, ["lock", "gear", "back", "switch a"])
    }
}
