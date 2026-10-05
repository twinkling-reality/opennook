// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The global shortcut, "Stay expanded", haptic feedback, and, while the chrome theme has
/// sounds the person may turn off, "Sounds" - the body of the built-in Settings screen's
/// "Shortcut & nook" group, for a host that builds its own Settings screen.
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
    @Environment(\.nookChromeLabels) private var labels
    @Environment(\.nookTheme) private var chromeTheme
    @Environment(\.nookThemeTokens) private var themeTokens

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsGroupSpacing) {
            SettingsShortcutRow(appState: appState)
            if !appState.hotkeyRegistrationFailures.keys.filter({ $0 != NookHotkeyIDs.toggle }).isEmpty {
                SettingsHotkeyFailureRow(appState: appState)
            }
            NookOpeningSettingsRows(appState: appState)
            SettingActionLine(
                icon: appState.keepNookOpen ? "pin.fill" : "pin",
                title: labels.shortcut.stayExpandedTitle,
                detail: appState.keepNookOpen
                    ? labels.shortcut.stayExpandedOn
                    : labels.shortcut.stayExpandedOff,
                accent: theme.accent,
                action: actions.toggleKeepOpen
            )
            SettingActionLine(
                icon: appState.appearancePreferences.hapticFeedbackEnabled ? "hand.tap.fill" : "hand.tap",
                title: labels.shortcut.hapticTitle,
                detail: appState.appearancePreferences.hapticFeedbackEnabled
                    ? labels.shortcut.hapticOn
                    : labels.shortcut.hapticOff,
                accent: theme.accent,
                action: toggleHapticFeedback
            )
            if showsSoundsRow {
                SettingActionLine(
                    icon: soundsEnabled ? "speaker.wave.2.fill" : "speaker.slash",
                    title: labels.shortcut.soundsTitle,
                    detail: soundsEnabled ? labels.shortcut.soundsOn : labels.shortcut.soundsOff,
                    accent: theme.accent,
                    action: toggleSounds
                )
            }
        }
    }

    private var soundsEnabled: Bool {
        appState.appearancePreferences.soundsEnabled
    }

    /// The "Sounds" row shows while the theme has sounds and lets the person turn them off -
    /// and also while they are off, so a person who turned them off under another theme can
    /// always turn them back on.
    private var showsSoundsRow: Bool {
        Self.showsSoundsRow(theme: chromeTheme, tokens: themeTokens, soundsEnabled: soundsEnabled)
    }

    static func showsSoundsRow(theme: NookTheme, tokens: NookResolvedTokens, soundsEnabled: Bool) -> Bool {
        tokens.hasSounds && (theme.allowsUserSoundToggle || !soundsEnabled)
    }

    private func toggleSounds() {
        var prefs = appState.appearancePreferences
        prefs.soundsEnabled.toggle()
        appState.replaceAppearancePreferences(prefs)
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
    @Environment(\.nookChromeLabels) private var labels
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(alignment: .center, spacing: metrics.settingsGroupSpacing) {
            Image(systemName: "keyboard")
                .font(typography.settingsEmphasis)
                .foregroundStyle(theme.headerInactiveIcon)
                .frame(width: metrics.settingsIconWidth)

            VStack(alignment: .leading, spacing: metrics.settingsTextSpacing) {
                Text(labels.shortcut.showHost(branding.hostName))
                    .font(typography.settingsRowTitle)
                    .foregroundStyle(theme.primaryLabel.opacity(metrics.settingsTitleEmphasisOpacity))
                if let failure = appState.hotkeyRegistrationFailures[NookHotkeyIDs.toggle] {
                    Text(labels.shortcut.unavailable(failure.combination))
                        .font(typography.settingsHint)
                        .foregroundStyle(theme.warning)
                } else {
                    Text(isRecording ? labels.shortcut.recordingHint : labels.shortcut.changeHint)
                        .font(typography.settingsHint)
                        .foregroundStyle(theme.tertiaryLabel)
                }
            }

            Spacer(minLength: 8)

            Button(action: toggleRecording) {
                if isRecording {
                    Text(labels.shortcut.listening)
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
            labels.shortcut.rowAccessibilityLabel(host: branding.hostName, keys: appState.hotkey.displaySymbols)
        )
        .accessibilityHint(labels.shortcut.rowAccessibilityHint)
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

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookChromeLabels) private var labels

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
                            .foregroundStyle(theme.warning)
                            .frame(width: metrics.settingsIconWidth)
                        VStack(alignment: .leading, spacing: metrics.settingsTextSpacing) {
                            Text(failure.shortcutName)
                                .font(typography.settingsRowTitle)
                            Text(labels.shortcut.unavailable(failure.combination))
                                .font(typography.settingsHint)
                                .foregroundStyle(theme.warning)
                        }
                        Spacer(minLength: 8)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(labels.shortcut.failureAccessibilityLabel(failure))
                }
            }
            .padding(.vertical, metrics.settingsRowVerticalPadding)
        }
    }
}
