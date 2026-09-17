// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

// ChromeNook - a tour of OpenNook's deeper chrome-customization seams.
//
// Where ThemedNook covers a host theme + lifecycle hooks, this shows the rest of
// the `NookConfiguration` surface, all additive and non-breaking:
//   • launch preference defaults (translucent chrome out of the box)
//   • chrome behavior (hover side-effects, the notch fade for Liquid Glass, launch shimmer)
//   • typing: a note field the global shortcut types straight into
//   • labels / metrics / motion overrides
//   • a custom brand mark (replaces the OpenNook glyph everywhere) and menu-bar icon
//   • a Settings screen without its Data group
//   • top-bar trailing actions + the status banner with severity
//
// Run with `swift run ChromeNook`, then press ⌥⌘; to expand and start typing a note.

import NookApp
import SwiftUI

/// A custom brand mark. Supplied to `NookHostBranding.mark`, it replaces the OpenNook
/// glyph in the top-bar leading cluster, the About card, and the menu-bar status icon.
struct SparkMark: View {
    var color: Color

    var body: some View {
        Image(systemName: "sparkle")
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
    }
}

struct ChromeHomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Text("ChromeNook")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryLabel)
            Text("A tour of the deeper chrome-customization seams.")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryLabel)
                .multilineTextAlignment(.center)

            QuickNoteField()

            // Post a success-severity status into the framework banner.
            Button("Post a success status") {
                appState.showStatus("Saved your changes.", severity: .success)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// A note field the nook types into. It is the nook's only text input, so it has focus when the
/// nook gets the keyboard: with the shortcut opted in to taking the keyboard, ⌥⌘; opens the nook
/// ready to type. It holds the nook open while it has focus, and lets go when the person clicks
/// into another app.
struct QuickNoteField: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme
    @State private var note = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Jot a note, then press Return", text: $note)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(theme.primaryLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.subtleFill, in: Capsule())
            .frame(maxWidth: 280)
            .focused($isFocused)
            .nookKeepsExpanded(whileFocused: $isFocused)
            .onSubmit {
                guard !note.isEmpty else { return }
                appState.showStatus("Noted: \(note)", severity: .success)
                note = ""
            }
    }
}

/// A top-bar trailing action - rendered left of the framework lock + gear. It reads the
/// resolved theme and observes `AppState`, like the rest of the chrome.
struct ChromeTrailingActions: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme

    var body: some View {
        Button {
            appState.showStatus("Heads up — warning posted from the top bar.", severity: .warning)
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.headerInactiveIcon)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Post a warning status")
    }
}

var configuration = NookConfiguration()
configuration.setHome { ChromeHomeView() }
configuration.setTopBarTrailingItems { ChromeTrailingActions() }

// Launch defaults - ship translucent chrome out of the box (seed-only: a user's
// Settings change still wins, and the seed is never persisted).
configuration.preferenceDefaults = NookPreferenceDefaults(
    appearance: NookAppearancePreferences(
        chromePalette: .followSystem,
        surfaceStyle: .translucent,
        presentation: .auto
    )
)

// Chrome behavior - opt into hover side-effects (keep-visible + haptics), shade Liquid Glass
// black at the notch and clear below (pick Liquid Glass in Settings to see it), and let the
// global shortcut hand the nook the keyboard so the note field takes typing at once.
configuration.chromeBehavior = NookChromeBehavior(
    hoverBehavior: .all,
    glassShading: .notchFade,
    keyboard: NookKeyboardBehavior(shortcutTakesKeyboardFocus: true)
)

// Settings - keep every framework group except Data (the status preview and reset).
configuration.settingsGroups = [.appearance, .display, .shortcut, .about]

// Labels / metrics / motion - localize a string, widen the breadcrumb, snappier swap.
configuration.labels.settingsBreadcrumb = "Preferences"
configuration.metrics.breadcrumbMaxWidth = 160
configuration.motion.viewModeChange = .snappy

// Identity - name, tagline, a custom brand mark replacing the OpenNook glyph, and a menu-bar
// icon of its own.
configuration.branding = NookHostBranding(
    hostName: "ChromeNook",
    hostTagline: "A tour of OpenNook's chrome-customization seams.",
    mark: { size, color in AnyView(SparkMark(color: color).frame(width: size, height: size)) },
    menuBarIcon: NookHostBranding.symbol("sparkles")
)

NookApp.main(configuration)
