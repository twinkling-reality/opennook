// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// Theme + surface pickers for host Settings surfaces. Writes through ``AppState/replaceAppearancePreferences(_:)``.
public struct NookAppearanceSettingsSection: View {
    @ObservedObject public var appState: AppState
    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics
    @Environment(\.nookChromeLabels) private var labels

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsBlockSpacing) {
            labeledPicker(
                title: labels.appearance.themeTitle,
                accessibilityLabel: labels.appearance.themeAccessibilityLabel
            ) {
                Picker(labels.appearance.themeTitle, selection: chromePaletteBinding) {
                    Text(labels.appearance.themeFollowSystem).tag(NookChromePalette.followSystem)
                    Text(labels.appearance.themeDark).tag(NookChromePalette.dark)
                    Text(labels.appearance.themeLight).tag(NookChromePalette.light)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
                labeledPicker(
                    title: labels.appearance.surfaceTitle,
                    accessibilityLabel: labels.appearance.surfaceAccessibilityLabel
                ) {
                    Picker(labels.appearance.surfaceTitle, selection: surfaceStyleBinding) {
                        Text(labels.appearance.surfaceSolid).tag(NookSurfaceStyle.solid)
                        Text(labels.appearance.surfaceTranslucent).tag(NookSurfaceStyle.translucent)
                        Text(labels.appearance.surfaceLiquidGlass).tag(NookSurfaceStyle.liquidGlass)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }

                Text(surfaceStyleDescription)
                    .font(typography.settingsCaption)
                    .foregroundStyle(theme.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
                labeledPicker(
                    title: labels.appearance.layoutTitle,
                    accessibilityLabel: labels.appearance.layoutAccessibilityLabel
                ) {
                    Picker(labels.appearance.layoutTitle, selection: presentationBinding) {
                        Text(labels.appearance.layoutAuto).tag(NookPresentation.auto)
                        Text(labels.appearance.layoutNotch).tag(NookPresentation.notch)
                        Text(labels.appearance.layoutFloating).tag(NookPresentation.floating)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }

                Text(presentationDescription)
                    .font(typography.settingsCaption)
                    .foregroundStyle(theme.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
                Text(labels.appearance.accentTitle)
                    .font(typography.settingsFieldLabel)
                    .foregroundStyle(theme.secondaryLabel)
                HStack(spacing: metrics.settingsInlineSpacing) {
                    ForEach(NookAccentPreset.allCases) { preset in
                        Button {
                            var prefs = appState.appearancePreferences
                            prefs.accentPreset = preset
                            appState.replaceAppearancePreferences(prefs)
                        } label: {
                            Circle()
                                .fill(preset.color())
                                .frame(
                                    width: metrics.settingsAccentSwatchSize,
                                    height: metrics.settingsAccentSwatchSize
                                )
                                .overlay(
                                    Circle()
                                        .stroke(
                                            accentRingColor(for: preset),
                                            lineWidth: metrics.settingsAccentSwatchStrokeWidth
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(labels.appearance.accentName(preset))
                    }
                }
            }

            if appState.appearancePreferences.surfaceStyle != .solid {
                VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
                    Text(strengthLabel)
                        .font(typography.settingsFieldLabel)
                        .foregroundStyle(theme.secondaryLabel)
                    Slider(value: backdropStrengthBinding, in: NookAppearancePreferences.backdropStrengthRange)
                        .controlSize(.small)
                        .accessibilityLabel(strengthLabel)
                    Text(labels.appearance.strengthDetail)
                        .font(typography.settingsCaption)
                        .foregroundStyle(theme.tertiaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var surfaceStyleDescription: String {
        switch surfaceStyleBinding.wrappedValue {
            case .solid:
                return labels.appearance.surfaceSolidDetail
            case .translucent:
                return labels.appearance.surfaceTranslucentDetail
            case .liquidGlass:
                return labels.appearance.surfaceLiquidGlassDetail
        }
    }

    private var strengthLabel: String {
        surfaceStyleBinding.wrappedValue == .liquidGlass
            ? labels.appearance.glassStrengthTitle : labels.appearance.translucencyStrengthTitle
    }

    private var presentationDescription: String {
        switch presentationBinding.wrappedValue {
            case .auto:
                return labels.appearance.layoutAutoDetail
            case .notch:
                return labels.appearance.layoutNotchDetail
            case .floating:
                return labels.appearance.layoutFloatingDetail
        }
    }

    @ViewBuilder
    private func labeledPicker(
        title: String,
        accessibilityLabel: String,
        @ViewBuilder picker: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.settingsFieldSpacing) {
            Text(title)
                .font(typography.settingsFieldLabel)
                .foregroundStyle(theme.secondaryLabel)
            picker()
                .accessibilityLabel(accessibilityLabel)
        }
    }

    /// The selected accent swatch's ring color; clear for the unselected swatches.
    private func accentRingColor(for preset: NookAccentPreset) -> Color {
        appState.appearancePreferences.accentPreset == preset
            ? theme.primaryLabel.opacity(metrics.settingsAccentSwatchSelectedOpacity)
            : Color.clear
    }

    private var chromePaletteBinding: Binding<NookChromePalette> {
        Binding(
            get: { appState.appearancePreferences.chromePalette },
            set: { next in
                var prefs = appState.appearancePreferences
                prefs.chromePalette = next
                appState.replaceAppearancePreferences(prefs)
            }
        )
    }

    private var surfaceStyleBinding: Binding<NookSurfaceStyle> {
        Binding(
            get: { appState.appearancePreferences.surfaceStyle },
            set: { next in
                var prefs = appState.appearancePreferences
                prefs.surfaceStyle = next
                appState.replaceAppearancePreferences(prefs)
            }
        )
    }

    private var presentationBinding: Binding<NookPresentation> {
        Binding(
            get: { appState.appearancePreferences.presentation },
            set: { next in
                var prefs = appState.appearancePreferences
                prefs.presentation = next
                appState.replaceAppearancePreferences(prefs)
            }
        )
    }

    private var backdropStrengthBinding: Binding<Double> {
        Binding(
            get: { appState.appearancePreferences.backdropStrength },
            set: { next in
                var prefs = appState.appearancePreferences
                prefs.backdropStrength = next
                prefs.backdropStrength = prefs.clampedBackdropStrength
                appState.replaceAppearancePreferences(prefs)
            }
        )
    }
}
