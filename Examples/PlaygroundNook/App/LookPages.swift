// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookApp
import PlaygroundNookCore
import SwiftUI

// MARK: - Appearance

/// The user's own appearance preferences - the same ones the built-in Settings screen shows.
struct AppearancePage: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Palette", selection: binding(\.chromePalette)) {
                    Text("Match Mac").tag(NookChromePalette.followSystem)
                    Text("Dark").tag(NookChromePalette.dark)
                    Text("Light").tag(NookChromePalette.light)
                }
                .pickerStyle(.segmented)
                Picker("Surface", selection: binding(\.surfaceStyle)) {
                    Text("Solid").tag(NookSurfaceStyle.solid)
                    Text("Translucent").tag(NookSurfaceStyle.translucent)
                    Text("Liquid Glass").tag(NookSurfaceStyle.liquidGlass)
                }
                .pickerStyle(.segmented)
                LabeledContent("Backdrop strength") {
                    HStack(spacing: 8) {
                        Slider(value: binding(\.backdropStrength), in: 0.15...1)
                            .frame(width: NumberRow.sliderWidth)
                            .accessibilityLabel("Backdrop strength")
                        Text(
                            appState.appearancePreferences.backdropStrength.formatted(
                                .percent.precision(.fractionLength(0))
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                        ResetButton(isVisible: appState.appearancePreferences.backdropStrength != 1) {
                            model.updateAppearance { $0.backdropStrength = 1 }
                        }
                    }
                }
                .disabled(appState.appearancePreferences.surfaceStyle == .solid)
            } header: {
                Text("Palette and material")
            } footer: {
                SectionFooter(
                    text: "Backdrop strength scales the darkening behind content on the translucent and "
                        + "Liquid Glass surfaces."
                )
            }

            Section {
                Picker("Layout", selection: binding(\.presentation)) {
                    Text("Auto").tag(NookPresentation.auto)
                    Text("Notch").tag(NookPresentation.notch)
                    Text("Floating").tag(NookPresentation.floating)
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent") {
                    AccentSwatches(selection: binding(\.accentPreset))
                }
            } header: {
                Text("Layout and accent")
            } footer: {
                SectionFooter(
                    text: "Auto fuses the nook to the notch on a notched display and floats it elsewhere. "
                        + "A theme accent override on the Theme page wins over this accent."
                )
            }

            Section {
                Toggle("Keep the nook expanded", isOn: keepsExpanded)
                Toggle("Completion haptics", isOn: binding(\.hapticFeedbackEnabled))
            } header: {
                Text("Behavior")
            } footer: {
                SectionFooter(
                    text: "These are the user's own preferences, which the framework saves. The Swift export "
                        + "turns them into launch defaults; Keep Expanded is left out, since it is only a "
                        + "working aid here.",
                    isResettable: isModified,
                    reset: resetSection
                )
            }
        }
        .formStyle(.grouped)
    }

    private var isModified: Bool {
        PlaygroundPage.appearance.isModified(model.settings, appearance: appState.appearancePreferences)
    }

    private func resetSection() {
        model.updateAppearance { preferences in
            let keepsOpen = preferences.keepNookOpen
            preferences = .default
            preferences.keepNookOpen = keepsOpen
        }
    }

    private var keepsExpanded: Binding<Bool> {
        Binding(get: { appState.keepNookOpen }, set: { model.setKeepsNookExpanded($0) })
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<NookAppearancePreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { appState.appearancePreferences[keyPath: keyPath] },
            set: { value in model.updateAppearance { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The accent presets as a row of swatches, the way the built-in Settings screen shows them.
/// A menu would draw its symbols without their colors.
private struct AccentSwatches: View {
    @Binding var selection: NookAccentPreset

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NookAccentPreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    Circle()
                        .fill(preset.color())
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(selection == preset ? 0.85 : 0), lineWidth: 2)
                                .padding(-3)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(preset.displayName)
                .accessibilityLabel(preset.displayName)
                .accessibilityAddTraits(selection == preset ? .isSelected : [])
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Theme

/// `NookConfiguration.theme`: the live palette with overrides.
struct ThemePage: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Font design", selection: $model.settings.theme.fontDesign) {
                    Text("Default").tag(PlaygroundSettings.FontDesign.default)
                    Text("Rounded").tag(PlaygroundSettings.FontDesign.rounded)
                    Text("Serif").tag(PlaygroundSettings.FontDesign.serif)
                    Text("Monospaced").tag(PlaygroundSettings.FontDesign.monospaced)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Type")
            } footer: {
                SectionFooter(text: "Restyles the chrome's own text: the top bar, the banner, and Settings.")
            }

            Section {
                ForEach(PlaygroundSettings.Theme.ColorRole.allCases) { role in
                    ColorOverrideRow(
                        title: role.title,
                        override: $model.settings.theme[role],
                        liveColor: role.color(in: livePalette)
                    )
                }
            } header: {
                Text("Colors")
            } footer: {
                SectionFooter(
                    text: "A live color follows the palette and accent preferences. An override is fixed, "
                        + "so pick one that reads on both light and dark chrome, or fix the palette.",
                    isResettable: model.settings.theme != .init(),
                    reset: { model.settings.theme = .init() }
                )
            }

            Section("Preview") {
                ThemePreview(theme: previewPalette, isDark: previewIsDark)
            }
        }
        .formStyle(.grouped)
    }

    /// The palette without overrides, as the chrome would resolve it right now.
    private var livePalette: NookResolvedTheme {
        NookResolvedTheme.live(appState: appState)
    }

    private var previewPalette: NookResolvedTheme {
        var palette = livePalette
        model.settings.theme.apply(to: &palette)
        return palette
    }

    private var previewIsDark: Bool {
        switch appState.appearancePreferences.chromePalette {
            case .dark: true
            case .light: false
            case .followSystem:
                NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}

/// A swatch of the resolved palette on the chrome's own backdrop color.
private struct ThemePreview: View {
    let theme: NookResolvedTheme
    let isDark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                Text("Home")
                    .foregroundStyle(theme.primaryLabel)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.quaternaryLabel)
                Text("Settings")
                    .foregroundStyle(theme.secondaryLabel)
                Spacer()
                Image(systemName: "lock.open")
                    .foregroundStyle(theme.headerInactiveIcon)
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(theme.accent)
            }
            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
            VStack(alignment: .leading, spacing: 3) {
                Text("Primary label")
                    .foregroundStyle(theme.primaryLabel)
                Text("Secondary label")
                    .foregroundStyle(theme.secondaryLabel)
                Text("Tertiary label")
                    .foregroundStyle(theme.tertiaryLabel)
            }
            .font(.system(size: 12, design: theme.fontDesign))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.subtleStroke)
            }
        }
        .padding(14)
        .background(
            isDark ? Color.black : Color.white,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Size and shape

/// `NookConfiguration.expandedWidth`, `style`, and a few `metrics`.
struct PanelPage: View {
    @ObservedObject var model: PlaygroundModel

    private let panelDefaults = PlaygroundSettings.Panel()
    private let metricDefaults = PlaygroundSettings.Metrics()

    var body: some View {
        Form {
            Section {
                NumberRow(
                    title: "Expanded width",
                    value: $model.settings.panel.expandedWidth,
                    range: 320...760,
                    defaultValue: panelDefaults.expandedWidth
                )
                NumberRow(
                    title: "Top corner radius",
                    value: $model.settings.panel.topCornerRadius,
                    range: 0...40,
                    defaultValue: panelDefaults.topCornerRadius
                )
                NumberRow(
                    title: "Bottom corner radius",
                    value: $model.settings.panel.bottomCornerRadius,
                    range: 0...48,
                    defaultValue: panelDefaults.bottomCornerRadius
                )
            } header: {
                Text("Panel")
            } footer: {
                SectionFooter(
                    text: "The top radius rounds into the notch arch; the bottom radius is where the panel meets "
                        + "the wallpaper. In the floating layout both corners use the bottom radius.",
                    isResettable: panelShapeIsModified,
                    reset: resetPanelShape
                )
            }

            Section {
                NumberRow(
                    title: "Top",
                    value: $model.settings.panel.insetTop,
                    range: 0...32,
                    defaultValue: panelDefaults.insetTop
                )
                NumberRow(
                    title: "Bottom",
                    value: $model.settings.panel.insetBottom,
                    range: 0...32,
                    defaultValue: panelDefaults.insetBottom
                )
                NumberRow(
                    title: "Leading",
                    value: $model.settings.panel.insetLeading,
                    range: 0...32,
                    defaultValue: panelDefaults.insetLeading
                )
                NumberRow(
                    title: "Trailing",
                    value: $model.settings.panel.insetTrailing,
                    range: 0...32,
                    defaultValue: panelDefaults.insetTrailing
                )
            } header: {
                Text("Content insets")
            } footer: {
                SectionFooter(
                    text: "The clearance the chrome keeps around expanded content (NookStyle.expandedContentInsets).",
                    isResettable: insetsAreModified,
                    reset: resetInsets
                )
            }

            Section {
                NumberRow(
                    title: "Edge padding",
                    value: $model.settings.metrics.edgePadding,
                    range: 0...24,
                    defaultValue: metricDefaults.edgePadding
                )
                NumberRow(
                    title: "Column spacing",
                    value: $model.settings.metrics.expandedColumnSpacing,
                    range: 0...24,
                    defaultValue: metricDefaults.expandedColumnSpacing
                )
                NumberRow(
                    title: "Top bar height",
                    value: $model.settings.metrics.topBarHeight,
                    range: 16...44,
                    defaultValue: metricDefaults.topBarHeight
                )
                NumberRow(
                    title: "Header icon size",
                    value: $model.settings.metrics.headerIconSize,
                    range: 16...40,
                    defaultValue: metricDefaults.headerIconSize
                )
                NumberRow(
                    title: "Header icon radius",
                    value: $model.settings.metrics.headerIconCornerRadius,
                    range: 0...20,
                    defaultValue: metricDefaults.headerIconCornerRadius
                )
                NumberRow(
                    title: "Compact slot size",
                    value: $model.settings.metrics.compactSlotSize,
                    range: 16...36,
                    defaultValue: metricDefaults.compactSlotSize
                )
                NumberRow(
                    title: "Banner corner radius",
                    value: $model.settings.metrics.bannerCornerRadius,
                    range: 0...20,
                    defaultValue: metricDefaults.bannerCornerRadius
                )
            } header: {
                Text("Metrics")
            } footer: {
                SectionFooter(
                    text: "A few of the NookChromeMetrics values. Post a status banner from the Top Bar page to "
                        + "see the banner radius.",
                    isResettable: model.settings.metrics != metricDefaults,
                    reset: { model.settings.metrics = metricDefaults }
                )
            }
        }
        .formStyle(.grouped)
    }

    private var panel: PlaygroundSettings.Panel { model.settings.panel }

    private var panelShapeIsModified: Bool {
        panel.expandedWidth != panelDefaults.expandedWidth
            || panel.topCornerRadius != panelDefaults.topCornerRadius
            || panel.bottomCornerRadius != panelDefaults.bottomCornerRadius
    }

    private var insetsAreModified: Bool {
        panel.insetTop != panelDefaults.insetTop || panel.insetBottom != panelDefaults.insetBottom
            || panel.insetLeading != panelDefaults.insetLeading || panel.insetTrailing != panelDefaults.insetTrailing
    }

    private func resetPanelShape() {
        var panel = panel
        panel.expandedWidth = panelDefaults.expandedWidth
        panel.topCornerRadius = panelDefaults.topCornerRadius
        panel.bottomCornerRadius = panelDefaults.bottomCornerRadius
        model.settings.panel = panel
    }

    private func resetInsets() {
        var panel = panel
        panel.insetTop = panelDefaults.insetTop
        panel.insetBottom = panelDefaults.insetBottom
        panel.insetLeading = panelDefaults.insetLeading
        panel.insetTrailing = panelDefaults.insetTrailing
        model.settings.panel = panel
    }
}

// MARK: - Type and motion

/// A few `NookConfiguration.typography` roles and `motion` springs.
struct TypeAndMotionPage: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        Form {
            Section {
                FontRow(
                    title: "Top bar title",
                    font: $model.settings.typography.topBarLabel,
                    defaultFont: defaults.topBarLabel
                )
                FontRow(
                    title: "Header icons",
                    font: $model.settings.typography.headerIcon,
                    defaultFont: defaults.headerIcon
                )
                FontRow(
                    title: "Banner message",
                    font: $model.settings.typography.bannerMessage,
                    defaultFont: defaults.bannerMessage
                )
                FontRow(
                    title: "Compact glyph",
                    font: $model.settings.typography.compactLeadingGlyph,
                    defaultFont: defaults.compactLeadingGlyph
                )
            } header: {
                Text("Typography")
            } footer: {
                SectionFooter(
                    text: "Header icons are the lock and gear. The compact glyph is the house left of the notch "
                        + "while the nook is collapsed.",
                    isResettable: model.settings.typography != defaults,
                    reset: { model.settings.typography = defaults }
                )
            }

            Section {
                SpringRows(spring: $model.settings.motion.viewModeChange, defaultSpring: motionDefaults.viewModeChange)
                Button("Switch Between Home and Settings") {
                    model.toggleNookSettings()
                }
            } header: {
                Text("Home and Settings motion")
            } footer: {
                SectionFooter(
                    text: "The spring for the swap between the home view and Settings. A lower damping bounces "
                        + "more.",
                    isResettable: model.settings.motion.viewModeChange != motionDefaults.viewModeChange,
                    reset: { model.settings.motion.viewModeChange = motionDefaults.viewModeChange }
                )
            }

            Section {
                SpringRows(spring: $model.settings.motion.statusBanner, defaultSpring: motionDefaults.statusBanner)
                Button("Post a Status Banner") {
                    model.postStatus()
                }
            } header: {
                Text("Status banner motion")
            } footer: {
                SectionFooter(
                    text: "The spring the status banner appears and leaves with.",
                    isResettable: model.settings.motion.statusBanner != motionDefaults.statusBanner,
                    reset: { model.settings.motion.statusBanner = motionDefaults.statusBanner }
                )
            }
        }
        .formStyle(.grouped)
    }

    private var defaults: PlaygroundSettings.Typography { .init() }
    private var motionDefaults: PlaygroundSettings.Motion { .init() }
}

private struct FontRow: View {
    let title: String
    @Binding var font: PlaygroundSettings.FontSpec
    let defaultFont: PlaygroundSettings.FontSpec

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: size, in: 8...20)
                    .frame(width: 110)
                    .accessibilityLabel("\(title) size")
                Text("\(font.size.formatted(.number.precision(.fractionLength(0...1)))) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                Picker("\(title) weight", selection: $font.weight) {
                    ForEach(PlaygroundSettings.FontWeight.allCases, id: \.self) { weight in
                        Text(weight.rawValue.capitalized).tag(weight)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
                ResetButton(isVisible: font != defaultFont) { font = defaultFont }
            }
        } label: {
            Text(title)
                .font(font.font)
        }
    }

    /// Half-point steps, since the framework's own sizes include 10.5.
    private var size: Binding<Double> {
        Binding(get: { font.size }, set: { font.size = ($0 * 2).rounded() / 2 })
    }
}

private struct SpringRows: View {
    @Binding var spring: PlaygroundSettings.SpringSpec
    let defaultSpring: PlaygroundSettings.SpringSpec

    var body: some View {
        NumberRow(
            title: "Response",
            value: $spring.response,
            range: 0.1...1.5,
            step: 0.01,
            defaultValue: defaultSpring.response,
            unit: "s"
        )
        NumberRow(
            title: "Damping",
            value: $spring.dampingFraction,
            range: 0.2...1.2,
            step: 0.01,
            defaultValue: defaultSpring.dampingFraction,
            unit: ""
        )
    }
}
