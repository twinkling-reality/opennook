// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// Default compact slot to the **left** of the notch when the nook is collapsed. The
/// shimmer peripheral cue lives in `NookSurface.NookFeedbackOverlay`; this view just
/// renders the static icon flanking the cutout.
///
/// This is the default `compactLeading` content installed by `NookConfiguration`. Host
/// apps register their own via ``NookConfiguration/setCompactLeading(_:)``.
public struct NookCompactLeadingView: View {
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics

    public init() {}

    public var body: some View {
        Image(systemName: "house")
            .font(typography.compactLeadingGlyph)
            .foregroundStyle(theme.primaryLabel.opacity(metrics.compactLeadingGlyphOpacity))
            .frame(width: metrics.compactSlotSize, height: metrics.compactSlotSize)
    }
}

/// Default compact slot to the **right** of the notch: the host's brand mark
/// (``NookHostBranding/mark``), or the OpenNook mark when the host set none.
public struct NookCompactTrailingView: View {
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookHostBranding) private var branding

    public init() {}

    public var body: some View {
        branding.markView(
            frameworkWidth: metrics.compactTrailingMarkSize,
            strokeWidth: metrics.compactTrailingMarkStrokeWidth,
            color: theme.primaryLabel.opacity(metrics.compactTrailingMarkOpacity)
        )
        .frame(width: metrics.compactSlotSize, height: metrics.compactSlotSize)
    }
}

/// Wraps host-registered compact content in the same chrome environment the expanded
/// surface gives its content (see ``NookChromeEnvironment``).
///
/// `NookSurface` renders the compact slots directly, with no environment of its own, so
/// the coordinator wraps each registered compact closure in one of these. Observing
/// `AppState` keeps the resolved theme current when appearance preferences change.
struct NookCompactHost<Content: View>: View {
    @ObservedObject var appState: AppState
    let theme: (AppState) -> NookResolvedTheme
    let services: AppServices
    let labels: NookChromeLabels
    let metrics: NookChromeMetrics
    let motion: NookChromeMotion
    let typography: NookChromeTypography
    let branding: NookHostBranding
    let chromeActions: NookChromeActions
    var symbols: NookChromeSymbols = .default
    let content: () -> Content

    var body: some View {
        content()
            .modifier(
                NookChromeEnvironment(
                    appState: appState,
                    theme: theme(appState),
                    services: services,
                    labels: labels,
                    metrics: metrics,
                    motion: motion,
                    typography: typography,
                    branding: branding,
                    chromeActions: chromeActions,
                    symbols: symbols
                )
            )
    }
}

/// The chrome environment ``NookExpandedView`` gives the home view, for content the surface
/// renders in a view tree of its own - the compact slots and companions - so it can read
/// the same environment values and `@EnvironmentObject` as the rest of the chrome.
struct NookChromeEnvironment: ViewModifier {
    @ObservedObject var appState: AppState
    let theme: NookResolvedTheme
    let services: AppServices
    let labels: NookChromeLabels
    let metrics: NookChromeMetrics
    let motion: NookChromeMotion
    let typography: NookChromeTypography
    let branding: NookHostBranding
    let chromeActions: NookChromeActions
    /// The top bar's glyphs, for ``NookKeepOpenButton`` and ``NookSettingsButton`` placed
    /// here. See ``NookTopBarConfiguration/symbols``.
    var symbols: NookChromeSymbols = .default

    func body(content: Content) -> some View {
        content
            .environment(\.nookResolvedTheme, theme)
            .environment(\.nookChromeLabels, labels)
            .environment(\.nookChromeMetrics, metrics)
            .environment(\.nookChromeMotion, motion)
            .environment(\.nookChromeTypography, typography)
            .environment(\.nookHostBranding, branding)
            .environment(\.nookChromeActions, chromeActions)
            .environment(\.nookChromeSymbols, symbols)
            .environment(\.appServices, services)
            .environmentObject(appState)
            // The panel is non-activating, so controls would otherwise paint as inactive
            // until clicked - the same override the expanded surface applies.
            .environment(\.controlActiveState, .active)
            .tint(theme.accent)
            .fontDesign(theme.fontDesign)
            .preferredColorScheme(appState.appearancePreferences.chromeColorSchemeOverride)
    }
}
