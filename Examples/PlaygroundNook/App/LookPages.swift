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

/// The user's own appearance preferences, the ones the built-in Settings screen shows.
struct AppearancePage: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState

    var body: some View {
        PlaygroundPageView(page: .appearance) {
            SectionCard(title: "Style", isModified: styleIsModified, reset: resetStyle) {
                SegmentedRow(
                    title: "Layout",
                    selection: binding(\.presentation),
                    choices: [Choice(.auto, "Auto"), Choice(.notch, "Notch"), Choice(.floating, "Floating")],
                    help: "Auto fuses the nook to the notch on a notched display and floats it elsewhere."
                )
                SegmentedRow(
                    title: "Palette",
                    selection: binding(\.chromePalette),
                    choices: [Choice(.followSystem, "System"), Choice(.dark, "Dark"), Choice(.light, "Light")],
                    help: "Dark or light chrome, or the Mac's own appearance."
                )
                SegmentedRow(
                    title: "Material",
                    selection: binding(\.surfaceStyle),
                    choices: [
                        Choice(.solid, "Solid"), Choice(.translucent, "Translucent"), Choice(.liquidGlass, "Glass"),
                    ],
                    help: "What the panel is made of. Glass is Liquid Glass on macOS 26."
                )
                if preferences.surfaceStyle != .solid {
                    SliderRow(
                        title: "Backdrop",
                        value: binding(\.backdropStrength),
                        range: 0.15...1,
                        step: 0.01,
                        defaultValue: NookAppearancePreferences.default.backdropStrength,
                        format: .percent,
                        help: "How much the backdrop darkens behind the content."
                    )
                }
                ControlRow(title: "Accent", help: "The chrome's tint. An accent picked on the Theme page wins.") {
                    AccentSwatches(selection: binding(\.accentPreset))
                }
            }

            SectionCard(title: "Feedback") {
                SwitchRow(
                    title: "Haptics",
                    isOn: binding(\.hapticFeedbackEnabled),
                    help: "A tap on a Force Touch trackpad when the nook confirms an action."
                )
            }
        }
    }

    private var preferences: NookAppearancePreferences {
        appState.appearancePreferences
    }

    private var styleIsModified: Bool {
        var style = preferences
        style.keepNookOpen = NookAppearancePreferences.default.keepNookOpen
        style.hapticFeedbackEnabled = NookAppearancePreferences.default.hapticFeedbackEnabled
        return style != .default
    }

    private func resetStyle() {
        model.updateAppearance { preferences in
            var reset = NookAppearancePreferences.default
            reset.keepNookOpen = preferences.keepNookOpen
            reset.hapticFeedbackEnabled = preferences.hapticFeedbackEnabled
            preferences = reset
        }
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

/// The accent presets as swatches, the way the built-in Settings screen shows them. A menu
/// would draw its symbols without their colors.
private struct AccentSwatches: View {
    @Binding var selection: NookAccentPreset
    @State private var hovered: NookAccentPreset?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NookAccentPreset.allCases) { preset in
                Button {
                    selection = preset
                } label: {
                    Circle()
                        .fill(preset.color())
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(ringOpacity(preset)), lineWidth: 1.5)
                                .padding(-3)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        if hovering {
                            hovered = preset
                        } else if hovered == preset {
                            hovered = nil
                        }
                    }
                }
                .help(preset.displayName)
                .accessibilityLabel(preset.displayName)
                .accessibilityAddTraits(selection == preset ? .isSelected : [])
            }
        }
        .padding(.vertical, 3)
    }

    private func ringOpacity(_ preset: NookAccentPreset) -> Double {
        if selection == preset { return 0.8 }
        return hovered == preset ? 0.3 : 0
    }
}

// MARK: - Theme

/// `NookConfiguration.theme`: the live palette with overrides.
struct ThemePage: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState
    @AppStorage("playground.theme.showsMoreColors") private var showsMoreColors = false

    private typealias Role = PlaygroundSettings.Theme.ColorRole
    private static let mainRoles: [Role] = [.accent, .primaryLabel, .secondaryLabel, .tertiaryLabel]
    private static let moreRoles: [Role] = [.quaternaryLabel, .subtleFill, .subtleStroke, .headerInactiveIcon]

    var body: some View {
        PlaygroundPageView(page: .theme) {
            ThemePreview(theme: previewPalette, isDark: previewIsDark)

            SectionCard(title: "Type") {
                SegmentedRow(
                    title: "Font",
                    selection: $model.settings.theme.fontDesign,
                    choices: [
                        Choice(.default, "Default"), Choice(.rounded, "Rounded"), Choice(.serif, "Serif"),
                        Choice(.monospaced, "Mono"),
                    ],
                    help: "The design of the chrome's own text: the top bar, the banner, and Settings."
                )
            }

            SectionCard(
                title: "Colors",
                help: "Live colors follow the palette and accent. Pick a color to override one.",
                isModified: Self.mainRoles.contains { theme[$0] != nil },
                reset: { reset(Self.mainRoles) }
            ) {
                ForEach(Self.mainRoles) { role in
                    colorRow(role)
                }
            }

            CollapsibleCard(
                title: "More Colors",
                isExpanded: $showsMoreColors,
                isModified: Self.moreRoles.contains { theme[$0] != nil },
                reset: { reset(Self.moreRoles) }
            ) {
                ForEach(Self.moreRoles) { role in
                    colorRow(role)
                }
            }
        }
    }

    private var theme: PlaygroundSettings.Theme { model.settings.theme }

    private func colorRow(_ role: Role) -> some View {
        ColorRow(
            title: role.title,
            override: $model.settings.theme[role],
            liveColor: role.color(in: livePalette),
            help: role.help
        )
    }

    private func reset(_ roles: [Role]) {
        var theme = theme
        for role in roles {
            theme[role] = nil
        }
        model.settings.theme = theme
    }

    /// The palette without overrides, as the chrome would resolve it right now.
    private var livePalette: NookResolvedTheme {
        NookResolvedTheme.live(appState: appState)
    }

    private var previewPalette: NookResolvedTheme {
        var palette = livePalette
        theme.apply(to: &palette)
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

extension PlaygroundSettings.Theme.ColorRole {
    fileprivate var help: String {
        switch self {
            case .accent: "The active lock and gear, toggles, and focus rings."
            case .primaryLabel: "Titles and main text."
            case .secondaryLabel: "Supporting text, such as the Settings breadcrumb."
            case .tertiaryLabel: "Captions and hints in Settings."
            case .quaternaryLabel: "The faintest glyphs, such as the breadcrumb chevron."
            case .subtleFill: "The hover background of header icons and Settings controls."
            case .subtleStroke: "The hover outline of header icons, and Settings dividers."
            case .headerInactiveIcon: "Header icons and Settings glyphs at rest."
        }
    }
}

/// The resolved palette on the chrome's own backdrop color.
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
                    .padding(4)
                    .background(theme.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.subtleStroke)
                    }
            }
            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Primary")
                    .foregroundStyle(theme.primaryLabel)
                Text("Secondary")
                    .foregroundStyle(theme.secondaryLabel)
                Text("Tertiary")
                    .foregroundStyle(theme.tertiaryLabel)
                Text("Quaternary")
                    .foregroundStyle(theme.quaternaryLabel)
            }
            .font(.system(size: 12, design: theme.fontDesign))
        }
        .padding(14)
        .background(
            isDark ? Color.black : Color.white,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme preview")
    }
}

// MARK: - Panel

/// `NookConfiguration.expandedWidth`, `style`, and a few `metrics`.
struct PanelPage: View {
    @ObservedObject var model: PlaygroundModel
    @AppStorage("playground.panel.showsInsets") private var showsInsets = false
    @AppStorage("playground.panel.showsMetrics") private var showsMetrics = false

    private let panelDefaults = PlaygroundSettings.Panel()
    private let metricDefaults = PlaygroundSettings.Metrics()

    var body: some View {
        PlaygroundPageView(page: .panel) {
            SectionCard(title: "Shape", isModified: shapeIsModified, reset: resetShape) {
                SliderRow(
                    title: "Width",
                    value: $model.settings.panel.expandedWidth,
                    range: 320...760,
                    defaultValue: panelDefaults.expandedWidth,
                    help: "The expanded content's width."
                )
                SliderRow(
                    title: "Top corners",
                    value: $model.settings.panel.topCornerRadius,
                    range: 0...40,
                    defaultValue: panelDefaults.topCornerRadius,
                    help: "The rounding into the notch arch."
                )
                SliderRow(
                    title: "Bottom corners",
                    value: $model.settings.panel.bottomCornerRadius,
                    range: 0...48,
                    defaultValue: panelDefaults.bottomCornerRadius,
                    help:
                        "The rounding where the panel meets the wallpaper. The floating panel uses it for every corner."
                )
            }

            CollapsibleCard(
                title: "Content Insets",
                help: "The clearance the chrome keeps around the content.",
                isExpanded: $showsInsets,
                isModified: insetsAreModified,
                reset: resetInsets
            ) {
                insetRow("Top", \.insetTop)
                insetRow("Bottom", \.insetBottom)
                insetRow("Leading", \.insetLeading)
                insetRow("Trailing", \.insetTrailing)
            }

            CollapsibleCard(
                title: "Metrics",
                help: "A few of the chrome's layout measurements.",
                isExpanded: $showsMetrics,
                isModified: model.settings.metrics != metricDefaults,
                reset: { model.settings.metrics = metricDefaults }
            ) {
                SliderRow(
                    title: "Edge padding",
                    value: $model.settings.metrics.edgePadding,
                    range: 0...24,
                    defaultValue: metricDefaults.edgePadding,
                    help: "The space between the panel's edge and its content."
                )
                SliderRow(
                    title: "Row spacing",
                    value: $model.settings.metrics.expandedColumnSpacing,
                    range: 0...24,
                    defaultValue: metricDefaults.expandedColumnSpacing,
                    help: "The gap between the top bar, the banner, and the content."
                )
                SliderRow(
                    title: "Top bar height",
                    value: $model.settings.metrics.topBarHeight,
                    range: 16...44,
                    defaultValue: metricDefaults.topBarHeight
                )
                SliderRow(
                    title: "Header icons",
                    value: $model.settings.metrics.headerIconSize,
                    range: 16...40,
                    defaultValue: metricDefaults.headerIconSize,
                    help: "The size of the lock and gear buttons."
                )
                SliderRow(
                    title: "Icon corners",
                    value: $model.settings.metrics.headerIconCornerRadius,
                    range: 0...20,
                    defaultValue: metricDefaults.headerIconCornerRadius,
                    help: "The rounding of a header icon's hover background."
                )
                SliderRow(
                    title: "Compact slots",
                    value: $model.settings.metrics.compactSlotSize,
                    range: 16...36,
                    defaultValue: metricDefaults.compactSlotSize,
                    help: "The size of the glyphs beside the collapsed pill."
                )
                SliderRow(
                    title: "Banner corners",
                    value: $model.settings.metrics.bannerCornerRadius,
                    range: 0...20,
                    defaultValue: metricDefaults.bannerCornerRadius,
                    help: "The status banner's rounding. Post one from the Top Bar page."
                )
            }
        }
    }

    private var panel: PlaygroundSettings.Panel { model.settings.panel }

    private func insetRow(_ title: String, _ keyPath: WritableKeyPath<PlaygroundSettings.Panel, Double>) -> some View {
        SliderRow(
            title: title,
            value: $model.settings.panel[dynamicMember: keyPath],
            range: 0...32,
            defaultValue: panelDefaults[keyPath: keyPath]
        )
    }

    private var shapeIsModified: Bool {
        panel.expandedWidth != panelDefaults.expandedWidth
            || panel.topCornerRadius != panelDefaults.topCornerRadius
            || panel.bottomCornerRadius != panelDefaults.bottomCornerRadius
    }

    private var insetsAreModified: Bool {
        panel.insetTop != panelDefaults.insetTop || panel.insetBottom != panelDefaults.insetBottom
            || panel.insetLeading != panelDefaults.insetLeading || panel.insetTrailing != panelDefaults.insetTrailing
    }

    private func resetShape() {
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

    private let fontDefaults = PlaygroundSettings.Typography()
    private let motionDefaults = PlaygroundSettings.Motion()

    var body: some View {
        PlaygroundPageView(page: .typeAndMotion) {
            SectionCard(
                title: "Fonts",
                isModified: model.settings.typography != fontDefaults,
                reset: { model.settings.typography = fontDefaults }
            ) {
                FontRow(
                    title: "Top bar title",
                    font: $model.settings.typography.topBarLabel,
                    defaultFont: fontDefaults.topBarLabel
                )
                FontRow(
                    title: "Header icons",
                    font: $model.settings.typography.headerIcon,
                    defaultFont: fontDefaults.headerIcon,
                    help: "The lock and gear glyphs."
                )
                FontRow(
                    title: "Banner",
                    font: $model.settings.typography.bannerMessage,
                    defaultFont: fontDefaults.bannerMessage,
                    help: "The status banner's message."
                )
                FontRow(
                    title: "Compact glyph",
                    font: $model.settings.typography.compactLeadingGlyph,
                    defaultFont: fontDefaults.compactLeadingGlyph,
                    help: "The glyph left of the notch while the nook is collapsed."
                )
            }

            SectionCard(
                title: "Home and Settings",
                help: "The spring for switching between the home view and Settings.",
                isModified: model.settings.motion.viewModeChange != motionDefaults.viewModeChange,
                reset: { model.settings.motion.viewModeChange = motionDefaults.viewModeChange }
            ) {
                SpringRows(spring: $model.settings.motion.viewModeChange, defaultSpring: motionDefaults.viewModeChange)
            } accessory: {
                PreviewButton(help: "Switch the nook between home and Settings", action: model.toggleNookSettings)
            }

            SectionCard(
                title: "Status Banner",
                help: "The spring the status banner comes and goes with.",
                isModified: model.settings.motion.statusBanner != motionDefaults.statusBanner,
                reset: { model.settings.motion.statusBanner = motionDefaults.statusBanner }
            ) {
                SpringRows(spring: $model.settings.motion.statusBanner, defaultSpring: motionDefaults.statusBanner)
            } accessory: {
                PreviewButton(help: "Post a status banner", action: { model.postStatus() })
            }
        }
    }
}

private struct FontRow: View {
    let title: String
    @Binding var font: PlaygroundSettings.FontSpec
    let defaultFont: PlaygroundSettings.FontSpec
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help, isModified: font != defaultFont) {
            HStack(spacing: 8) {
                Picker("\(title) weight", selection: $font.weight) {
                    ForEach(PlaygroundSettings.FontWeight.allCases, id: \.self) { weight in
                        Text(weight.title).tag(weight)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                Spacer(minLength: 0)
                Text("\(font.size.formatted(.number.precision(.fractionLength(0...1)))) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                // Half-point steps, since the framework's own sizes include 10.5.
                Stepper("\(title) size", value: $font.size, in: 8...20, step: 0.5)
                    .labelsHidden()
                    .accessibilityValue("\(font.size.formatted()) points")
            }
        } reset: {
            font = defaultFont
        }
    }
}

extension PlaygroundSettings.FontWeight {
    fileprivate var title: String {
        switch self {
            case .ultraLight: "Ultralight"
            case .thin: "Thin"
            case .light: "Light"
            case .regular: "Regular"
            case .medium: "Medium"
            case .semibold: "Semibold"
            case .bold: "Bold"
            case .heavy: "Heavy"
            case .black: "Black"
        }
    }
}

private struct SpringRows: View {
    @Binding var spring: PlaygroundSettings.SpringSpec
    let defaultSpring: PlaygroundSettings.SpringSpec

    var body: some View {
        SliderRow(
            title: "Response",
            value: $spring.response,
            range: 0.1...1.5,
            step: 0.01,
            defaultValue: defaultSpring.response,
            format: .seconds,
            help: "Roughly how long the spring takes to settle."
        )
        SliderRow(
            title: "Damping",
            value: $spring.dampingFraction,
            range: 0.2...1.2,
            step: 0.01,
            defaultValue: defaultSpring.dampingFraction,
            format: .number,
            help: "Below 1 the motion overshoots and bounces; at 1 and above it settles without."
        )
    }
}
