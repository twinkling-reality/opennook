// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

// ThemedNook - a host-supplied chrome theme plus lifecycle hooks.
//
// Shows `NookConfiguration.chromeTheme` (a `NookTheme` recolors the chrome's labels, pins it
// dark, rounds its type, and reshapes it) and the `onExpand` / `onCompact` callbacks. Run with
// `swift run ThemedNook` and watch the console as you toggle the nook with ⌥⌘;.
//
// The same theme could live in a JSON file: `try NookTheme(contentsOf: url)` reads it, and
// `NookThemeSource.watching(fileAt: url)` follows it as you edit it.

import NookApp
import SwiftUI

/// A warm palette, written as theme tokens. Colors stay explicit, never system-adaptive -
/// see the `NookResolvedTheme` type docs for why.
@MainActor
func sunsetTheme() -> NookTheme {
    var theme = NookTheme(
        name: "Sunset",
        // `accent` tints the chrome's interactive controls (lock, gear, toggles) instead of
        // the system blue.
        accent: .srgb(red: 1.0, green: 0.55, blue: 0.30, opacity: 1),
        // Pinned dark: the labels below are light, and the Theme picker in Settings hides.
        palette: .dark,
        fontDesign: .rounded
    )
    theme.tokens[.labelPrimary] = .srgb(red: 1.0, green: 0.93, blue: 0.86, opacity: 1)
    theme.tokens[.labelSecondary] = .srgb(red: 1.0, green: 0.78, blue: 0.62, opacity: 0.85)
    theme.tokens[.labelTertiary] = .srgb(red: 1.0, green: 0.66, blue: 0.50, opacity: 0.70)
    theme.tokens[.labelQuaternary] = .srgb(red: 1.0, green: 0.62, blue: 0.46, opacity: 0.50)
    theme.tokens[.fillSubtle] = .white(opacity: 0.08)
    theme.tokens[.strokeSubtle] = .white(opacity: 0.16)
    theme.tokens[.iconInactive] = .srgb(red: 1.0, green: 0.70, blue: 0.55, opacity: 0.55)
    // Smaller corners, and the bottom safe-area strip tightened from 8pt to 2pt so the home
    // view's last row sits closer to the rounded bottom.
    theme.tokens[.chromeTopRadius] = 15
    theme.tokens[.chromeBottomRadius] = 20
    theme.tokens[.chromeInsetBottom] = 2
    return theme
}

struct ThemedHomeView: View {
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.secondaryLabel)
            Text("Themed Nook")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.primaryLabel)
            Text("A host-supplied NookTheme paints the chrome.")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

NookApp.main {
    var configuration = NookConfiguration()
    configuration.setHome { ThemedHomeView() }
    configuration.chromeTheme = sunsetTheme()
    configuration.onExpand = { print("[ThemedNook] nook expanded") }
    configuration.onCompact = { print("[ThemedNook] nook compacted") }
    return configuration
}
