// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import SwiftUI

/// The "Open on hover" rows of the Shortcut & nook group: what resting the pointer on the
/// compact pill does, and how long it waits first. Left out while the host fixes the behavior
/// in code (`NookChromeBehavior.hoverIntent`), the way a theme's pins leave out the controls
/// they pin.
struct NookOpeningSettingsRows: View {
    @ObservedObject var appState: AppState

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookChromeLabels) private var labels

    var body: some View {
        if !appState.hostFixesHoverIntent {
            VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
                Text(labels.shortcut.openOnHoverTitle)
                    .font(typography.settingsFieldLabel)
                    .foregroundStyle(theme.secondaryLabel)
                Picker(labels.shortcut.openOnHoverTitle, selection: binding(\.openOnHover)) {
                    Text(labels.shortcut.openOnHoverImmediately).tag(NookOpenOnHover.immediately)
                    Text(labels.shortcut.openOnHoverPeekFirst).tag(NookOpenOnHover.peekFirst)
                    Text(labels.shortcut.openOnHoverOff).tag(NookOpenOnHover.off)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(labels.shortcut.openOnHoverTitle)
                Text(detail)
                    .font(typography.settingsCaption)
                    .foregroundStyle(theme.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.openOnHover != .off {
                    timingSlider(
                        labels.shortcut.hoverDelayTitle,
                        value: binding(\.hoverDelay),
                        range: NookAppearancePreferences.hoverTimingRange,
                        zero: labels.shortcut.noDelay
                    )
                    timingSlider(
                        labels.shortcut.externalDisplayHoverDelayTitle,
                        value: binding(\.externalDisplayHoverDelay),
                        range: NookAppearancePreferences.hoverTimingRange,
                        zero: labels.shortcut.noDelay
                    )
                }
                if preferences.openOnHover == .peekFirst {
                    timingSlider(
                        labels.shortcut.peekDwellTitle,
                        value: binding(\.peekDwell),
                        range: NookAppearancePreferences.peekDwellRange,
                        zero: labels.shortcut.dwellOff
                    )
                }
            }
            .padding(.vertical, metrics.settingsRowVerticalPadding)
        }
    }

    private var preferences: NookAppearancePreferences { appState.appearancePreferences }

    private var detail: String {
        switch preferences.openOnHover {
            case .immediately: labels.shortcut.openOnHoverImmediatelyDetail
            case .peekFirst: labels.shortcut.openOnHoverPeekFirstDetail
            case .off: labels.shortcut.openOnHoverOffDetail
        }
    }

    /// A slider in tenths of a second, its value beside its title; `zero` names the value 0.
    private func timingSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        zero: String
    ) -> some View {
        let shown = value.wrappedValue > 0 ? labels.shortcut.seconds(value.wrappedValue) : zero
        return VStack(alignment: .leading, spacing: metrics.settingsTextSpacing) {
            HStack {
                Text(title)
                    .font(typography.settingsCaption)
                    .foregroundStyle(theme.secondaryLabel)
                Spacer(minLength: 8)
                Text(shown)
                    .font(typography.settingsCaption.monospacedDigit())
                    .foregroundStyle(theme.tertiaryLabel)
            }
            Slider(value: value, in: range, step: 0.1)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(shown)
        }
    }

    private func binding<Value>(_ field: WritableKeyPath<NookAppearancePreferences, Value>) -> Binding<Value> {
        Binding(
            get: { appState.appearancePreferences[keyPath: field] },
            set: { next in
                var prefs = appState.appearancePreferences
                prefs[keyPath: field] = next
                appState.replaceAppearancePreferences(prefs)
            }
        )
    }
}
