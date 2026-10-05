// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Expanded-surface router. `Nook` builds its expanded content closure exactly once,
/// so to swap modules at runtime the *view* - not the closure - must observe the
/// ``ModuleHost``. When ``ModuleHost/configuration`` is re-published, this view's body
/// re-evaluates and rebuilds ``NookExpandedView`` from the new configuration: new home
/// content, new theme, new chrome opt-outs.
///
/// It renders the *displayed* module (``ModuleHost/displayedConfiguration``): the active
/// module, or a background module while its urgent surface claim holds the surface.
struct ModuleRouterExpandedView: View {
    @ObservedObject var moduleHost: ModuleHost
    @ObservedObject var appState: AppState

    let toggleKeepOpen: () -> Void
    let hide: () -> Void
    let resetAllSettings: () -> Void
    let switchModule: (String) -> Void
    /// What the lock and gear do, for host content that shows them outside the top bar.
    var chromeActions: NookChromeActions = .inert

    /// When the surface inserted this view: the start of the content's entrance. The surface
    /// inserts it each time it expands and keeps it across a module switch, so a switch does
    /// not replay the entrance's waits.
    @State private var entranceStart = Date()

    var body: some View {
        let configuration = moduleHost.displayedConfiguration
        NookExpandedView(
            appState: appState,
            services: moduleHost.displayedServices,
            toggleKeepOpen: toggleKeepOpen,
            hide: hide,
            resetAllSettings: resetAllSettings,
            theme: configuration.theme,
            home: configuration.home,
            settings: configuration.settings,
            settingsSections: configuration.settingsSections,
            settingsGroups: configuration.settingsGroups,
            topBar: configuration.topBar,
            labels: configuration.labels,
            metrics: configuration.effectiveMetrics,
            motion: configuration.effectiveMotion,
            typography: configuration.effectiveTypography,
            width: configuration.expandedWidth ?? NookLayout.width,
            // Only fold a switcher into the chrome when the host opted in; otherwise the
            // surface is untouched and switching lives in the menu bar / hotkeys.
            moduleSwitcher: leadingClusterSwitcher,
            chromeTheme: configuration.effectiveChromeTheme,
            themeTokens: configuration.effectiveThemeTokens
        )
        // Identity tracks the displayed module so a switch tears down the old content and
        // inserts the new - letting the transition cross-fade rather than diff in place.
        .id(moduleHost.displayedModuleID)
        .transition(.opacity)
        // Host-product identity (brand mark, About card, show-hide hotkey label) lives on
        // `ModuleHost`; surface it so the chrome can read it without an init-time plumb.
        .environment(\.nookHostBranding, moduleHost.branding)
        .environment(\.nookChromeActions, chromeActions)
        .environment(
            \.nookContentEntrance,
            NookContentEntrance(
                start: entranceStart,
                delay: configuration.effectiveTransitions?.expandedContentTransition.delay ?? 0
            )
        )
    }

    /// The in-surface switcher payload, built only when the host opted into
    /// ``NookModuleSwitcherPlacement/leadingCluster`` and more than one module is
    /// registered. `nil` leaves the top bar's leading cluster the plain module title.
    private var leadingClusterSwitcher: NookModuleSwitcher? {
        guard moduleHost.isMultiModule, moduleHost.switcherPlacement.foldsIntoLeadingCluster else {
            return nil
        }
        return NookModuleSwitcher(
            modules: moduleHost.descriptors,
            // The module whose content is on screen, so the cluster labels what is shown.
            activeID: moduleHost.displayedModuleID,
            attentionIDs: moduleHost.attentionModuleIDs,
            switchTo: switchModule
        )
    }
}

/// Compact-slot router - the collapsed-pill counterpart to ``ModuleRouterExpandedView``.
/// One instance per slot; both observe the same ``ModuleHost`` so a module switch
/// re-renders the leading and trailing glyphs together. Like the expanded router it
/// renders the displayed module, and gives the slot the same chrome environment.
struct ModuleRouterCompactView: View {
    enum Slot {
        case leading
        case trailing
    }

    @ObservedObject var moduleHost: ModuleHost
    @ObservedObject var appState: AppState
    let slot: Slot
    var chromeActions: NookChromeActions = .inert

    var body: some View {
        let configuration = moduleHost.displayedConfiguration
        let content = slot == .leading ? configuration.compactLeading : configuration.compactTrailing
        // The compact slots render in their own view tree (not under NookExpandedView), so
        // the host gives them the whole chrome environment the expanded content gets.
        NookCompactHost(
            appState: appState,
            theme: configuration.theme,
            services: moduleHost.displayedServices,
            labels: configuration.labels,
            metrics: configuration.effectiveMetrics,
            motion: configuration.effectiveMotion,
            typography: configuration.effectiveTypography,
            branding: moduleHost.branding,
            chromeActions: chromeActions,
            symbols: configuration.topBar.symbols,
            chromeTheme: configuration.effectiveChromeTheme,
            themeTokens: configuration.effectiveThemeTokens,
            content: content
        )
    }
}
