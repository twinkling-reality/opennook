// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookKit
import NookSurface

/// Writes playground state out as Swift a host can paste into its `main.swift`. Pure.
///
/// The snippet uses the single-module `NookConfiguration` path and sets only what differs from
/// the framework's defaults, so an untouched playground exports an empty configuration. The
/// views the playground demonstrates with - its home view and companion contents - appear as
/// placeholder views to replace with your own.
public enum PlaygroundSwiftExporter {
    public static func snippet(for preset: PlaygroundPreset) -> String {
        let settings = preset.settings
        let sections = [
            appearanceLines(preset.appearance),
            themeLines(settings.theme),
            panelLines(settings.panel),
            tokenLines(settings),
            topBarLines(settings.topBar),
            companionLines(settings.companions),
            effectLines(rimGlow: settings.rimGlow, scrollEdgeFade: settings.scrollEdgeFade),
            behaviorLines(settings.behavior),
        ]
        .filter { !$0.isEmpty }

        var lines = [
            "import NookApp",
            "import SwiftUI",
            "",
            "var configuration = NookConfiguration()",
            "configuration.setHome { MyHomeView() }  // your home view",
        ]
        if sections.isEmpty {
            lines += ["", "// Every other setting is at its default."]
        }
        for section in sections {
            lines.append("")
            lines += section
        }
        lines += ["", "NookApp.main(configuration)"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Calls longer than this break onto one line per argument.
    static let maximumLineLength = 100

    // MARK: - Sections

    static func appearanceLines(_ appearance: NookAppearancePreferences) -> [String] {
        let defaults = NookAppearancePreferences.default
        var arguments: [String] = []
        if appearance.chromePalette != defaults.chromePalette {
            arguments.append("chromePalette: \(literal(appearance.chromePalette))")
        }
        if appearance.surfaceStyle != defaults.surfaceStyle {
            arguments.append("surfaceStyle: \(literal(appearance.surfaceStyle))")
        }
        if appearance.presentation != defaults.presentation {
            arguments.append("presentation: \(literal(appearance.presentation))")
        }
        if appearance.hapticFeedbackEnabled != defaults.hapticFeedbackEnabled {
            arguments.append("hapticFeedbackEnabled: \(appearance.hapticFeedbackEnabled)")
        }
        if appearance.accentPreset != defaults.accentPreset {
            arguments.append("accentPreset: \(literal(appearance.accentPreset))")
        }
        if differs(appearance.backdropStrength, defaults.backdropStrength) {
            arguments.append("backdropStrength: \(number(appearance.backdropStrength))")
        }
        guard !arguments.isEmpty else { return [] }
        return [
            "// Launch appearance. It seeds the first run; the user's own Settings choices win.",
            "configuration.preferenceDefaults = NookPreferenceDefaults(",
            "    appearance: NookAppearancePreferences(",
        ]
            + argumentLines(arguments, indent: 8)
            + [
                "    )",
                ")",
            ]
    }

    static func themeLines(_ theme: PlaygroundSettings.Theme) -> [String] {
        var body: [String] = []
        for role in PlaygroundSettings.Theme.ColorRole.allCases {
            if let color = theme[role] {
                body.append("    theme.\(role.rawValue) = \(literal(color))")
            }
        }
        if theme.fontDesign != .default {
            body.append("    theme.fontDesign = \(literal(theme.fontDesign))")
        }
        guard !body.isEmpty else { return [] }
        return [
            "// The live palette, which follows the user's palette and accent, with overrides.",
            "configuration.theme = { appState in",
            "    var theme = NookResolvedTheme.live(appState: appState)",
        ]
            + body
            + [
                "    return theme",
                "}",
            ]
    }

    static func panelLines(_ panel: PlaygroundSettings.Panel) -> [String] {
        let defaults = PlaygroundSettings.Panel()
        var lines: [String] = []
        if differs(panel.expandedWidth, defaults.expandedWidth) {
            lines.append("configuration.expandedWidth = \(number(panel.expandedWidth))")
        }
        let style = [
            ("topCornerRadius", panel.topCornerRadius, defaults.topCornerRadius),
            ("bottomCornerRadius", panel.bottomCornerRadius, defaults.bottomCornerRadius),
            ("expandedContentInsets.top", panel.insetTop, defaults.insetTop),
            ("expandedContentInsets.bottom", panel.insetBottom, defaults.insetBottom),
            ("expandedContentInsets.leading", panel.insetLeading, defaults.insetLeading),
            ("expandedContentInsets.trailing", panel.insetTrailing, defaults.insetTrailing),
        ]
        .filter { differs($0.1, $0.2) }
        if !style.isEmpty {
            // Starting from the framework's style keeps the export to the values that changed.
            lines.append("configuration.style = NookConfiguration.defaultStyle")
            lines += style.map { "configuration.style?.\($0.0) = \(number($0.1))" }
        }
        return lines
    }

    /// Metrics, typography, motion, and labels.
    static func tokenLines(_ settings: PlaygroundSettings) -> [String] {
        var lines: [String] = []

        let metrics = settings.metrics
        let defaultMetrics = PlaygroundSettings.Metrics()
        let metricValues = [
            ("edgePadding", metrics.edgePadding, defaultMetrics.edgePadding),
            ("expandedColumnSpacing", metrics.expandedColumnSpacing, defaultMetrics.expandedColumnSpacing),
            ("topBarHeight", metrics.topBarHeight, defaultMetrics.topBarHeight),
            ("headerIconSize", metrics.headerIconSize, defaultMetrics.headerIconSize),
            ("headerIconCornerRadius", metrics.headerIconCornerRadius, defaultMetrics.headerIconCornerRadius),
            ("compactSlotSize", metrics.compactSlotSize, defaultMetrics.compactSlotSize),
            ("bannerCornerRadius", metrics.bannerCornerRadius, defaultMetrics.bannerCornerRadius),
        ]
        for (name, value, fallback) in metricValues where differs(value, fallback) {
            lines.append("configuration.metrics.\(name) = \(number(value))")
        }

        let typography = settings.typography
        let defaultTypography = PlaygroundSettings.Typography()
        let fonts = [
            ("headerIcon", typography.headerIcon, defaultTypography.headerIcon),
            ("topBarLabel", typography.topBarLabel, defaultTypography.topBarLabel),
            ("bannerMessage", typography.bannerMessage, defaultTypography.bannerMessage),
            ("compactLeadingGlyph", typography.compactLeadingGlyph, defaultTypography.compactLeadingGlyph),
        ]
        for (name, font, fallback) in fonts where differs(font, fallback) {
            lines.append("configuration.typography.\(name) = \(literal(font))")
        }

        let motion = settings.motion
        let defaultMotion = PlaygroundSettings.Motion()
        let springs = [
            ("viewModeChange", motion.viewModeChange, defaultMotion.viewModeChange),
            ("statusBanner", motion.statusBanner, defaultMotion.statusBanner),
        ]
        for (name, spring, fallback) in springs where differs(spring, fallback) {
            lines.append("configuration.motion.\(name) = \(literal(spring))")
        }

        let labels = settings.labels
        let defaultLabels = PlaygroundSettings.Labels()
        let strings = [
            ("settingsBreadcrumb", labels.settingsBreadcrumb, defaultLabels.settingsBreadcrumb),
            ("keepOpenHelp", labels.keepOpenHelp, defaultLabels.keepOpenHelp),
            ("settingsHelp", labels.settingsHelp, defaultLabels.settingsHelp),
            ("dismissHelp", labels.dismissHelp, defaultLabels.dismissHelp),
        ]
        for (name, value, fallback) in strings where value != fallback {
            lines.append("configuration.labels.\(name) = \(stringLiteral(value))")
        }
        return lines
    }

    static func topBarLines(_ topBar: PlaygroundSettings.TopBar) -> [String] {
        let defaults = PlaygroundSettings.TopBar()
        var lines: [String] = []
        let flags = [
            ("showsTopBar", topBar.showsTopBar, defaults.showsTopBar),
            ("showsSettings", topBar.showsSettings, defaults.showsSettings),
            ("showsKeepOpenButton", topBar.showsKeepOpenButton, defaults.showsKeepOpenButton),
            ("showsSettingsButton", topBar.showsSettingsButton, defaults.showsSettingsButton),
            ("showsStatusBanner", topBar.showsStatusBanner, defaults.showsStatusBanner),
        ]
        for (name, value, fallback) in flags where value != fallback {
            lines.append("configuration.topBar.\(name) = \(value)")
        }
        if topBar.width != defaults.width {
            lines.append("configuration.topBar.width = \(literal(topBar.width))")
        }
        if topBar.leadingTitle != defaults.leadingTitle {
            lines.append("configuration.topBar.leadingTitle = { _ in \(stringLiteral(topBar.leadingTitle)) }")
        }
        if topBar.leadingIcon != defaults.leadingIcon, let icon = topBar.leadingIcon {
            lines.append("configuration.topBar.leadingIcon = \(stringLiteral(icon))")
        }
        return lines
    }

    static func companionLines(_ companions: [PlaygroundSettings.Companion]) -> [String] {
        let defaults = PlaygroundSettings.Companion(id: "", kind: .actions)
        var lines: [String] = []
        for companion in companions {
            var arguments = ["id: \(stringLiteral(companion.id))"]
            if companion.anchor != defaults.anchor || companion.alignment != defaults.alignment {
                arguments.append("anchor: \(anchorLiteral(companion))")
            }
            if differs(companion.spacing, defaults.spacing) {
                arguments.append("spacing: \(number(companion.spacing))")
            }
            if companion.visibility != defaults.visibility {
                arguments.append("visibility: \(literal(companion.visibility))")
            }
            if companion.outline != defaults.outline {
                arguments.append("shape: \(shapeLiteral(companion))")
            }
            if companion.backdrop != defaults.backdrop {
                arguments.append("backdrop: \(backdropLiteral(companion))")
            }
            if companion.hidesInSettings != defaults.hidesInSettings {
                arguments.append("hidesInSettings: \(companion.hidesInSettings)")
            }
            if let label = companion.accessibilityLabel {
                arguments.append("accessibilityLabel: \(stringLiteral(label))")
            }
            lines += call("configuration.addCompanion", arguments: arguments, trailer: " {")
            lines.append("    \(placeholder(for: companion.kind))")
            lines.append("}")
        }
        return lines
    }

    static func effectLines(
        rimGlow: PlaygroundSettings.RimGlow,
        scrollEdgeFade: PlaygroundSettings.ScrollEdgeFade
    ) -> [String] {
        var lines: [String] = []
        let defaults = PlaygroundSettings.RimGlow()
        var arguments: [String] = []
        if differs(rimGlow.lineWidth, defaults.lineWidth) {
            arguments.append("lineWidth: \(number(rimGlow.lineWidth))")
        }
        if differs(rimGlow.glowRadius, defaults.glowRadius) {
            arguments.append("glowRadius: \(number(rimGlow.glowRadius))")
        }
        if differs(rimGlow.intensity, defaults.intensity) {
            arguments.append("intensity: \(number(rimGlow.intensity))")
        }
        if rimGlow.pulses != defaults.pulses {
            arguments.append("pulses: \(rimGlow.pulses)")
        }
        if rimGlow.followsAmbientColor != defaults.followsAmbientColor {
            arguments.append("followsAmbientColor: \(rimGlow.followsAmbientColor)")
        }
        if !arguments.isEmpty {
            // The style alone draws nothing, so say how the rim gets lit.
            lines.append("// The rim shows while chrome content lights it: .nookRimGlow(isBusy ? .blue : nil)")
            lines += call("configuration.rimGlow = NookRimGlowStyle", arguments: arguments)
        }

        if scrollEdgeFade.isEnabled {
            lines.append("// Scroll views opt in with .nookScrollEdgeFade(axes:).")
            let fallback = PlaygroundSettings.ScrollEdgeFade()
            var arguments: [String] = []
            if scrollEdgeFade.edges != fallback.edges {
                arguments.append("edges: \(edgesLiteral(scrollEdgeFade))")
            }
            if differs(scrollEdgeFade.length, fallback.length) {
                arguments.append("length: \(number(scrollEdgeFade.length))")
            }
            if arguments.isEmpty {
                lines.append("configuration.scrollEdgeFade = .standard")
            } else {
                lines += call("configuration.scrollEdgeFade = NookScrollEdgeFade", arguments: arguments)
            }
        }
        return lines
    }

    static func behaviorLines(_ behavior: PlaygroundSettings.Behavior) -> [String] {
        guard behavior != PlaygroundSettings.Behavior() else { return [] }
        let value =
            switch (behavior.hoverKeepsVisible, behavior.hoverHaptics) {
                case (true, true): ".all"
                case (true, false): ".keepVisible"
                case (false, true): ".hapticFeedback"
                case (false, false): "[]"
            }
        return ["configuration.chromeBehavior.hoverBehavior = \(value)"]
    }

    // MARK: - Literals

    static func literal(_ palette: NookChromePalette) -> String {
        switch palette {
            case .followSystem: ".followSystem"
            case .dark: ".dark"
            case .light: ".light"
        }
    }

    static func literal(_ style: NookSurfaceStyle) -> String {
        switch style {
            case .solid: ".solid"
            case .translucent: ".translucent"
            case .liquidGlass: ".liquidGlass"
        }
    }

    static func literal(_ presentation: NookPresentation) -> String {
        switch presentation {
            case .auto: ".auto"
            case .notch: ".notch"
            case .floating: ".floating"
        }
    }

    static func literal(_ accent: NookAccentPreset) -> String {
        switch accent {
            case .system: ".system"
            case .teal: ".teal"
            case .blue: ".blue"
            case .violet: ".violet"
            case .orange: ".orange"
            case .rose: ".rose"
        }
    }

    static func literal(_ design: PlaygroundSettings.FontDesign) -> String {
        switch design {
            case .default: ".default"
            case .rounded: ".rounded"
            case .serif: ".serif"
            case .monospaced: ".monospaced"
        }
    }

    static func literal(_ width: PlaygroundSettings.TopBar.Width) -> String {
        switch width {
            case .contentColumn: ".contentColumn"
            case .intrinsic: ".intrinsic"
        }
    }

    static func literal(_ visibility: PlaygroundSettings.Companion.Visibility) -> String {
        switch visibility {
            case .expanded: ".expanded"
            case .compact: ".compact"
            case .both: ".both"
        }
    }

    static func literal(_ color: PlaygroundColor) -> String {
        var arguments = [
            "red: \(number(color.red))",
            "green: \(number(color.green))",
            "blue: \(number(color.blue))",
        ]
        if color.opacity < 1 {
            arguments.append("opacity: \(number(color.opacity))")
        }
        return "Color(\(arguments.joined(separator: ", ")))"
    }

    static func literal(_ font: PlaygroundSettings.FontSpec) -> String {
        let weight =
            switch font.weight {
                case .ultraLight: ".ultraLight"
                case .thin: ".thin"
                case .light: ".light"
                case .regular: ".regular"
                case .medium: ".medium"
                case .semibold: ".semibold"
                case .bold: ".bold"
                case .heavy: ".heavy"
                case .black: ".black"
            }
        return ".system(size: \(number(font.size)), weight: \(weight))"
    }

    static func literal(_ spring: PlaygroundSettings.SpringSpec) -> String {
        ".spring(response: \(number(spring.response)), dampingFraction: \(number(spring.dampingFraction)))"
    }

    static func anchorLiteral(_ companion: PlaygroundSettings.Companion) -> String {
        let edge =
            switch companion.anchor {
                case .below: ".below"
                case .leading: ".leading"
                case .trailing: ".trailing"
            }
        let alignment =
            switch companion.alignment {
                case .start: ".start"
                case .center: ".center"
                case .end: ".end"
            }
        return companion.alignment == .center ? edge : "\(edge)(alignment: \(alignment))"
    }

    static func shapeLiteral(_ companion: PlaygroundSettings.Companion) -> String {
        switch companion.outline {
            case .capsule: ".capsule"
            case .circle: ".circle"
            case .roundedRectangle: ".roundedRectangle(cornerRadius: \(number(companion.cornerRadius)))"
        }
    }

    static func backdropLiteral(_ companion: PlaygroundSettings.Companion) -> String {
        switch companion.backdrop {
            case .inherit: ".inherit"
            case .solid: ".custom(.solid(\(literal(companion.backdropColor))))"
            case .glass: ".custom(.liquidGlass(.init(tint: \(literal(companion.backdropColor)))))"
            case .none: ".none"
        }
    }

    static func edgesLiteral(_ fade: PlaygroundSettings.ScrollEdgeFade) -> String {
        switch (fade.top, fade.bottom, fade.leading, fade.trailing) {
            case (true, true, true, true):
                return ".all"
            case (true, true, false, false):
                return ".vertical"
            case (false, false, true, true):
                return ".horizontal"
            default:
                var names: [String] = []
                if fade.top { names.append(".top") }
                if fade.bottom { names.append(".bottom") }
                if fade.leading { names.append(".leading") }
                if fade.trailing { names.append(".trailing") }
                return names.count == 1 ? names[0] : "[\(names.joined(separator: ", "))]"
        }
    }

    static func placeholder(for kind: PlaygroundSettings.Companion.Kind) -> String {
        switch kind {
            case .actions: "ActionPill()  // your view: a row of icon buttons"
            case .button: "RoundButton()  // your view: a single icon button"
            case .controls: "ChromeControls()  // your view stacking NookKeepOpenButton() and NookSettingsButton()"
            case .chip: "StatusChip()  // your view: a short label"
        }
    }

    /// A Swift string literal for `text`, escaping everything a literal cannot hold as is.
    static func stringLiteral(_ text: String) -> String {
        var literal = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
                case "\\": literal += "\\\\"
                case "\"": literal += "\\\""
                case "\n": literal += "\\n"
                case "\r": literal += "\\r"
                case "\t": literal += "\\t"
                case "\0": literal += "\\0"
                default:
                    switch scalar.properties.generalCategory {
                        case .control, .format, .lineSeparator, .paragraphSeparator:
                            literal += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                        default:
                            literal.unicodeScalars.append(scalar)
                    }
            }
        }
        return literal + "\""
    }

    /// `value` rounded to three decimals, with no trailing zeros: `8`, `0.5`, `10.25`.
    static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == 0 {
            // Also turns -0 into 0.
            return "0"
        }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        return text
    }

    // MARK: - Helpers

    /// Whether two values differ at the precision the export writes them with.
    static func differs(_ lhs: Double, _ rhs: Double) -> Bool {
        number(lhs) != number(rhs)
    }

    static func differs(_ lhs: PlaygroundSettings.FontSpec, _ rhs: PlaygroundSettings.FontSpec) -> Bool {
        differs(lhs.size, rhs.size) || lhs.weight != rhs.weight
    }

    static func differs(_ lhs: PlaygroundSettings.SpringSpec, _ rhs: PlaygroundSettings.SpringSpec) -> Bool {
        differs(lhs.response, rhs.response) || differs(lhs.dampingFraction, rhs.dampingFraction)
    }

    /// `head(arguments)trailer` on one line, or with one argument per line when that is too long.
    static func call(_ head: String, arguments: [String], trailer: String = "") -> [String] {
        let line = "\(head)(\(arguments.joined(separator: ", ")))\(trailer)"
        guard line.count > maximumLineLength else { return [line] }
        return ["\(head)("] + argumentLines(arguments, indent: 4) + [")\(trailer)"]
    }

    static func argumentLines(_ arguments: [String], indent: Int) -> [String] {
        let padding = String(repeating: " ", count: indent)
        return arguments.enumerated().map { index, argument in
            padding + argument + (index < arguments.count - 1 ? "," : "")
        }
    }
}
