// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The global shortcut, "Stay expanded", and haptic feedback - the body of the built-in
/// Settings screen's "Shortcut & nook" group, for a host that builds its own Settings screen.
///
/// Use it inside chrome content, which supplies the chrome's actions: "Stay expanded" runs
/// ``NookChromeActions/toggleKeepOpen``, like the top bar's lock.
///
/// ```swift
/// NookSettingsGroup("Shortcut & nook") { NookShortcutSettingsSection(appState: appState) }
/// ```
public struct NookShortcutSettingsSection: View {
    @ObservedObject public var appState: AppState

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookChromeActions) private var actions

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsGroupSpacing) {
            SettingsShortcutRow(appState: appState)
            if !appState.hotkeyRegistrationFailures.keys.filter({ $0 != NookHotkeyIDs.toggle }).isEmpty {
                SettingsHotkeyFailureRow(appState: appState)
            }
            SettingActionLine(
                icon: appState.keepNookOpen ? "pin.fill" : "pin",
                title: "Stay expanded",
                detail: appState.keepNookOpen
                    ? "On — nook stays open after hover ends"
                    : "Off — closes when the pointer leaves",
                accent: theme.accent,
                action: actions.toggleKeepOpen
            )
            SettingActionLine(
                icon: appState.appearancePreferences.hapticFeedbackEnabled ? "hand.tap.fill" : "hand.tap",
                title: "Haptic feedback",
                detail: appState.appearancePreferences.hapticFeedbackEnabled
                    ? "On — trackpad pulse on confirmation"
                    : "Off — silent confirmation",
                accent: theme.accent,
                action: toggleHapticFeedback
            )
        }
    }

    /// Flip the haptic preference and fire one pulse on the way *on* so the user feels
    /// what they just enabled. Off doesn't pulse - silence is its whole point.
    private func toggleHapticFeedback() {
        var prefs = appState.appearancePreferences
        prefs.hapticFeedbackEnabled.toggle()
        appState.replaceAppearancePreferences(prefs)
        NookHaptics.confirm(enabled: prefs.hapticFeedbackEnabled)
    }
}

/// Settings row for the global show/hide hotkey. Tap the shortcut to record a new one:
/// the next modifier + key combination is captured, persisted via `AppState`, and
/// re-registered live by `AppCoordinator`. Escape cancels.
struct SettingsShortcutRow: View {
    @ObservedObject var appState: AppState

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookHostBranding) private var branding
    @Environment(\.nookChromeActions) private var actions
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(alignment: .center, spacing: metrics.settingsGroupSpacing) {
            Image(systemName: "keyboard")
                .font(typography.settingsEmphasis)
                .foregroundStyle(theme.headerInactiveIcon)
                .frame(width: metrics.settingsIconWidth)

            VStack(alignment: .leading, spacing: metrics.settingsTextSpacing) {
                Text("Show \(branding.hostName)")
                    .font(typography.settingsRowTitle)
                    .foregroundStyle(theme.primaryLabel.opacity(metrics.settingsTitleEmphasisOpacity))
                if let failure = appState.hotkeyRegistrationFailures[NookHotkeyIDs.toggle] {
                    Text(failure.message)
                        .font(typography.settingsHint)
                        .foregroundStyle(Color.orange)
                } else {
                    Text(isRecording ? "Press a shortcut — Esc to cancel" : "Global shortcut — click to change")
                        .font(typography.settingsHint)
                        .foregroundStyle(theme.tertiaryLabel)
                }
            }

            Spacer(minLength: 8)

            Button(action: toggleRecording) {
                if isRecording {
                    Text("Listening…")
                        .font(typography.settingsFieldLabel)
                        .foregroundStyle(theme.primaryLabel.opacity(metrics.settingsRecordingLabelOpacity))
                        .padding(.horizontal, metrics.settingsRecordingHorizontalPadding)
                        .frame(minHeight: metrics.settingsRecordingMinHeight)
                        .background(theme.subtleFill.opacity(metrics.settingsRecordingFillOpacity), in: Capsule())
                        .overlay(
                            Capsule().stroke(
                                theme.accent.opacity(metrics.settingsRecordingStrokeOpacity),
                                lineWidth: metrics.settingsRecordingStrokeWidth
                            )
                        )
                } else {
                    HStack(spacing: metrics.shortcutKeyCapSpacing) {
                        ForEach(Array(appState.hotkey.displaySymbols.enumerated()), id: \.offset) { _, symbol in
                            ShortcutKeySquircle(symbol: symbol)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, metrics.settingsRowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Show \(branding.hostName) shortcut, "
                + "currently \(appState.hotkey.displaySymbols.joined(separator: " "))"
        )
        .accessibilityHint("Activates to record a new shortcut")
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        appState.isRecordingHotkey = true
        // The recorder listens for key presses, which reach the nook only while it has the
        // keyboard - not the case when the person came from another app without clicking.
        actions.takeKeyboardFocus()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels without changing the shortcut.
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            if let hotkey = NookHotkey(event: event) {
                appState.replaceHotkey(hotkey)
                stopRecording()
            }
            // Swallow the event either way so it doesn't reach the rest of the app
            // while recording - including a partial combo that isn't valid yet.
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        isRecording = false
        appState.isRecordingHotkey = false
    }
}

/// Surfaces hotkey-registration failures for the host-configured shortcuts - the
/// module direct-jump keys and the module-cycle key. The user-rebindable show/hide
/// shortcut reports its own failure inline in ``SettingsShortcutRow``; this row covers
/// the static shortcuts, which would otherwise fail silently. Renders nothing when
/// every static shortcut registered successfully.
struct SettingsHotkeyFailureRow: View {
    @ObservedObject var appState: AppState

    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics

    /// Failures for every shortcut except the show/hide toggle, sorted for stable order.
    private var staticFailures: [HotkeyRegistrationFailure] {
        appState.hotkeyRegistrationFailures
            .filter { $0.key != NookHotkeyIDs.toggle }
            .values
            .sorted { $0.shortcutName < $1.shortcutName }
    }

    var body: some View {
        if !staticFailures.isEmpty {
            VStack(alignment: .leading, spacing: metrics.settingsFailureRowSpacing) {
                ForEach(staticFailures, id: \.shortcutName) { failure in
                    HStack(alignment: .center, spacing: metrics.settingsGroupSpacing) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(typography.settingsEmphasis)
                            .foregroundStyle(Color.orange)
                            .frame(width: metrics.settingsIconWidth)
                        VStack(alignment: .leading, spacing: metrics.settingsTextSpacing) {
                            Text(failure.shortcutName)
                                .font(typography.settingsRowTitle)
                            Text(failure.message)
                                .font(typography.settingsHint)
                                .foregroundStyle(Color.orange)
                        }
                        Spacer(minLength: 8)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(failure.shortcutName) shortcut unavailable: \(failure.message)")
                }
            }
            .padding(.vertical, metrics.settingsRowVerticalPadding)
        }
    }
}
