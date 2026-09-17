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

// MARK: - Top bar

/// `NookConfiguration.topBar` and `labels`, plus a status banner to try them on.
struct TopBarPage: View {
    @ObservedObject var model: PlaygroundModel
    @AppStorage("playground.topBar.showsLabels") private var showsLabels = false

    private static let iconSuggestions = [
        "house", "music.note", "sun.max", "calendar", "bolt.fill", "sparkles", "timer", "tray.full", "bell",
    ]

    var body: some View {
        PlaygroundPageView(page: .topBar) {
            SectionCard(title: "Bar", isModified: flagsAreModified, reset: resetFlags) {
                SwitchRow(
                    title: "Top bar",
                    isOn: $model.settings.topBar.showsTopBar,
                    help: "The row with the title, the lock, and the gear."
                )
                if topBar.showsTopBar {
                    SegmentedRow(
                        title: "Width",
                        selection: $model.settings.topBar.width,
                        choices: [Choice(.contentColumn, "Column"), Choice(.intrinsic, "Fit")],
                        help: "Column spans the content. Fit wraps the icons and centers them."
                    )
                    SwitchRow(title: "Lock button", isOn: $model.settings.topBar.showsKeepOpenButton)
                    if topBar.showsSettings {
                        SwitchRow(title: "Gear button", isOn: $model.settings.topBar.showsSettingsButton)
                    }
                    SwitchRow(
                        title: "Status banner",
                        isOn: $model.settings.topBar.showsStatusBanner,
                        help: "The message strip under the top bar."
                    )
                }
                SwitchRow(
                    title: "Settings",
                    isOn: $model.settings.topBar.showsSettings,
                    help: "Off removes Settings everywhere: the gear, the screen, and the menu item."
                )
            }

            if topBar.showsTopBar {
                SectionCard(
                    title: "Title",
                    isModified: topBar.leadingTitle != defaults.leadingTitle || topBar.leadingIcon != nil,
                    reset: {
                        model.settings.topBar.leadingTitle = defaults.leadingTitle
                        model.settings.topBar.leadingIcon = nil
                    }
                ) {
                    TextRow(title: "Title", text: $model.settings.topBar.leadingTitle, prompt: "Home")
                    iconRow
                }
            }

            SectionCard(
                title: "Notch",
                help: "What happens in the band beside the notch while the top bar is hidden.",
                isModified: notchIsModified,
                reset: {
                    model.settings.topBar.notchClearance = defaults.notchClearance
                    model.settings.topBar.notchAccessories = defaults.notchAccessories
                }
            ) {
                SegmentedRow(
                    title: "Clearance",
                    selection: $model.settings.topBar.notchClearance,
                    choices: [Choice(.automatic, "Automatic"), Choice(.manual, "Manual")],
                    help: "Automatic starts the content below the notch. Manual lets it run up beside the notch."
                )
                SwitchRow(
                    title: "Header beside notch",
                    isOn: $model.settings.topBar.notchAccessories,
                    help: "Moves the home view's header into the band beside the notch, with "
                        + "nookNotchAccessories(leading:trailing:)."
                )
            }

            CollapsibleCard(
                title: "Labels",
                help: "The chrome's own strings, for localization or product naming.",
                isExpanded: $showsLabels,
                isModified: model.settings.labels != .init(),
                reset: { model.settings.labels = .init() }
            ) {
                TextRow(title: "Breadcrumb", text: $model.settings.labels.settingsBreadcrumb)
                TextRow(title: "Lock tooltip", text: $model.settings.labels.keepOpenHelp)
                TextRow(title: "Gear tooltip", text: $model.settings.labels.settingsHelp)
                TextRow(title: "Close tooltip", text: $model.settings.labels.dismissHelp)
            }

            SectionCard(title: "Banner Preview") {
                TextRow(title: "Message", text: $model.demo.statusMessage)
                SegmentedRow(
                    title: "Severity",
                    selection: $model.demo.statusSeverity,
                    choices: NookStatusSeverity.allCases.map { Choice($0.rawValue, $0.rawValue.capitalized) }
                )
            } accessory: {
                Button(action: model.clearStatus) {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(IconButtonStyle())
                .help("Clear the banner")
                PreviewButton(help: bannerPreviewHelp, action: { model.postStatus() })
                    .disabled(!bannerIsShown)
            }
        }
    }

    private var topBar: PlaygroundSettings.TopBar { model.settings.topBar }
    private var defaults: PlaygroundSettings.TopBar { .init() }

    private var bannerIsShown: Bool {
        topBar.showsTopBar && topBar.showsStatusBanner
    }

    private var bannerPreviewHelp: String {
        bannerIsShown ? "Post the message in the nook" : "The banner needs the top bar and its status banner"
    }

    private var flagsAreModified: Bool {
        var flags = topBar
        flags.leadingTitle = defaults.leadingTitle
        flags.leadingIcon = nil
        flags.notchClearance = defaults.notchClearance
        flags.notchAccessories = defaults.notchAccessories
        return flags != defaults
    }

    private var notchIsModified: Bool {
        topBar.notchClearance != defaults.notchClearance || topBar.notchAccessories != defaults.notchAccessories
    }

    /// Resets the switches and the width, leaving the title and the notch to their cards.
    private func resetFlags() {
        var reset = defaults
        reset.leadingTitle = topBar.leadingTitle
        reset.leadingIcon = topBar.leadingIcon
        reset.notchClearance = topBar.notchClearance
        reset.notchAccessories = topBar.notchAccessories
        model.settings.topBar = reset
    }

    private var iconRow: some View {
        ControlRow(
            title: "Icon",
            help: "Any SF Symbol name. Leave it empty for the brand mark.",
            isModified: topBar.leadingIcon != nil
        ) {
            HStack(spacing: 8) {
                TextField("Icon", text: iconName, prompt: Text("Brand mark"))
                    .labelsHidden()
                    .playgroundField()
                iconPreview
                Menu {
                    Button("Brand Mark") { model.settings.topBar.leadingIcon = nil }
                    Divider()
                    ForEach(Self.iconSuggestions, id: \.self) { name in
                        Button {
                            model.settings.topBar.leadingIcon = name
                        } label: {
                            Label(name, systemImage: name)
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .modifier(HoverCircle(size: 26))
                .help("Suggested icons")
                .accessibilityLabel("Suggested icons")
            }
        } reset: {
            model.settings.topBar.leadingIcon = nil
        }
    }

    private var iconName: Binding<String> {
        Binding(
            get: { model.settings.topBar.leadingIcon ?? "" },
            set: { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                model.settings.topBar.leadingIcon = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var iconIsValid: Bool {
        guard let name = topBar.leadingIcon else { return true }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private var iconPreview: some View {
        Group {
            if let name = topBar.leadingIcon {
                if iconIsValid {
                    Image(systemName: name)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help("No SF Symbol has this name, so the top bar shows no icon")
                }
            } else {
                Image(systemName: "seal")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 13, weight: .light))
        .frame(width: 18)
    }
}

// MARK: - Effects

/// `NookConfiguration.rimGlow` and `scrollEdgeFade`, with demos for both.
struct EffectsPage: View {
    @ObservedObject var model: PlaygroundModel

    private let rimDefaults = PlaygroundSettings.RimGlow()
    private let fadeDefaults = PlaygroundSettings.ScrollEdgeFade()

    var body: some View {
        PlaygroundPageView(page: .effects) {
            SectionCard(
                title: "Rim Glow",
                isModified: model.settings.rimGlow != rimDefaults,
                reset: { model.settings.rimGlow = rimDefaults }
            ) {
                ControlRow(
                    title: "Light it",
                    help: "The home view and the compact slots light the rim with nookRimGlow(_:), so it stays lit "
                        + "after the nook collapses."
                ) {
                    HStack(spacing: 10) {
                        ColorSwatch(title: "Rim color", color: rimColor)
                        Toggle("Light the rim", isOn: $model.demo.rimGlowLit)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                }
                SliderRow(
                    title: "Line width",
                    value: $model.settings.rimGlow.lineWidth,
                    range: 0...6,
                    step: 0.5,
                    defaultValue: rimDefaults.lineWidth,
                    help: "Increase Contrast draws it bolder."
                )
                SliderRow(
                    title: "Glow",
                    value: $model.settings.rimGlow.glowRadius,
                    range: 0...30,
                    defaultValue: rimDefaults.glowRadius,
                    help: "The halo's radius. Reduce Transparency drops the halo."
                )
                SliderRow(
                    title: "Intensity",
                    value: $model.settings.rimGlow.intensity,
                    range: 0...1,
                    step: 0.01,
                    defaultValue: rimDefaults.intensity,
                    format: .percent
                )
                SwitchRow(
                    title: "Breathe",
                    isOn: $model.settings.rimGlow.pulses,
                    help: "The halo pulses slowly while lit. Reduce Motion stills it."
                )
                SwitchRow(
                    title: "Ambient color",
                    isOn: $model.settings.rimGlow.followsAmbientColor,
                    help: "With nothing lighting the rim, it takes the ambient color content reports."
                )
            }

            SectionCard(
                title: "Scroll Edge Fade",
                isModified: model.settings.scrollEdgeFade != fadeDefaults,
                reset: { model.settings.scrollEdgeFade = fadeDefaults }
            ) {
                SwitchRow(
                    title: "Fade edges",
                    isOn: $model.settings.scrollEdgeFade.isEnabled,
                    help: "Scroll views that opt in with nookScrollEdgeFade(axes:) fade where they meet the "
                        + "panel's edges."
                )
                if model.settings.scrollEdgeFade.isEnabled {
                    ControlRow(title: "Edges") {
                        EdgeToggles(fade: $model.settings.scrollEdgeFade)
                    }
                    SliderRow(
                        title: "Length",
                        value: $model.settings.scrollEdgeFade.length,
                        range: 0...60,
                        defaultValue: fadeDefaults.length
                    )
                }
                SwitchRow(
                    title: "Scrolling demo",
                    isOn: $model.demo.showsScrollDemo,
                    help: "A scrolling list and tag row in the nook to try the fade on."
                )
            }
        }
    }

    private var rimColor: Binding<Color> {
        Binding(
            get: { model.demo.rimGlowColor.color },
            set: { model.demo.rimGlowColor = PlaygroundColor($0) }
        )
    }
}

/// The four fade edges as round toggles.
private struct EdgeToggles: View {
    @Binding var fade: PlaygroundSettings.ScrollEdgeFade

    var body: some View {
        HStack(spacing: 6) {
            edge("Top", "arrow.up.to.line", $fade.top)
            edge("Bottom", "arrow.down.to.line", $fade.bottom)
            edge("Leading", "arrow.left.to.line", $fade.leading)
            edge("Trailing", "arrow.right.to.line", $fade.trailing)
        }
    }

    private func edge(_ title: String, _ symbol: String, _ isOn: Binding<Bool>) -> some View {
        EdgeToggle(title: title, symbol: symbol, isOn: isOn)
    }
}

private struct EdgeToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(isHovered ? .primary : .secondary))
                .frame(width: 26, height: 26)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .trackingHover($isHovered)
        .help(isOn ? "Fade the \(title.lowercased()) edge: on" : "Fade the \(title.lowercased()) edge: off")
        .accessibilityLabel("Fade the \(title.lowercased()) edge")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        if isOn {
            return AnyShapeStyle(PlaygroundTheme.accent.opacity(isHovered ? 0.85 : 1))
        }
        return AnyShapeStyle(isHovered ? PlaygroundTheme.controlHoverFill : PlaygroundTheme.controlFill)
    }
}

// MARK: - Behavior

/// `NookChromeBehavior.hoverBehavior`, applied with `replaceChromeBehavior(_:)`.
struct BehaviorPage: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        PlaygroundPageView(page: .behavior) {
            SectionCard(
                title: "Hover",
                isModified: model.settings.behavior != .init(),
                reset: { model.settings.behavior = .init() }
            ) {
                SwitchRow(
                    title: "Stay open while hovered",
                    isOn: $model.settings.behavior.hoverKeepsVisible,
                    help: "A request to hide the nook waits until the pointer leaves it."
                )
                SwitchRow(
                    title: "Hover haptics",
                    isOn: $model.settings.behavior.hoverHaptics,
                    help: "A tap on a Force Touch trackpad as the pointer enters and leaves the nook."
                )
            }
        }
    }
}
