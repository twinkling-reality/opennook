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
/// the framework's defaults, so an untouched playground exports an empty configuration. The home
/// view appears as a placeholder to replace with your own. Each companion's content is written
/// out as a view of its own, with a comment where a button's action goes.
public enum PlaygroundSwiftExporter {
    public static func snippet(for preset: PlaygroundPreset) -> String {
        let settings = preset.settings
        let sections = [
            appearanceLines(preset.appearance),
            themeLines(settings.theme),
            panelLines(settings.panel),
            tokenLines(settings),
            topBarLines(settings.topBar),
            companionLines(settings),
            effectLines(rimGlow: settings.rimGlow, scrollEdgeFade: settings.scrollEdgeFade),
            behaviorLines(settings.behavior),
        ]
        .filter { !$0.isEmpty }

        var lines = ["import NookApp", "import SwiftUI", ""]
        lines += homeLines(settings.topBar)
        if sections.isEmpty {
            lines += ["", "// Every other setting is at its default."]
        }
        for section in sections {
            lines.append("")
            lines += section
        }
        lines += ["", "NookApp.main(configuration)"]
        let views = companionViewLines(settings)
        if !views.isEmpty {
            lines += ["", "// MARK: - Companion content", ""] + views
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Calls longer than this break onto one line per argument.
    static let maximumLineLength = 100

    // MARK: - Sections

    /// The configuration and its home view. A header beside the notch needs a view type of its
    /// own, since `setHome` takes a `Sendable` view and a modified view is not one.
    static func homeLines(_ topBar: PlaygroundSettings.TopBar) -> [String] {
        guard topBar.notchAccessories else {
            return [
                "var configuration = NookConfiguration()",
                "configuration.setHome { MyHomeView() }  // your home view",
            ]
        }
        return [
            "struct MyNookHome: View {",
            "    var body: some View {",
            "        MyHomeView()  // your home view",
            "            .nookNotchAccessories {",
            "                HeaderTitle()  // your view: an icon and a short title",
            "            } trailing: {",
            "                HeaderButtons()  // your view: a few icon buttons",
            "            }",
            "    }",
            "}",
            "",
            "var configuration = NookConfiguration()",
            "configuration.setHome { MyNookHome() }",
        ]
    }

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
        if topBar.notchClearance != defaults.notchClearance {
            lines.append("configuration.topBar.notchClearance = \(literal(topBar.notchClearance))")
        }
        if topBar.leadingTitle != defaults.leadingTitle {
            lines.append("configuration.topBar.leadingTitle = { _ in \(stringLiteral(topBar.leadingTitle)) }")
        }
        if topBar.leadingIcon != defaults.leadingIcon, let icon = topBar.leadingIcon {
            lines.append("configuration.topBar.leadingIcon = \(stringLiteral(icon))")
        }
        return lines
    }

    /// The companion defaults, then one `addCompanion` call per companion. A companion's content
    /// is the view ``companionViewLines(_:)`` writes for it.
    ///
    /// A companion with no items is hidden in the playground, so it is left out here, with a
    /// comment saying so.
    static func companionLines(_ settings: PlaygroundSettings) -> [String] {
        var lines = companionDefaultLines(settings.companionDefaults)
        if !lines.isEmpty, !settings.companions.isEmpty {
            lines.append("")
        }
        let blank = PlaygroundSettings.Companion(id: "")
        let exported = exportedCompanions(settings)
        let names = companionViewNames(exported)
        let accented = exported.contains { $0.accent != nil }
        if accented {
            lines.append("let chromeTheme = configuration.theme")
        }
        for companion in settings.companions where companion.items.isEmpty {
            lines.append("// \(stringLiteral(companion.id)) holds nothing yet, so it is left out.")
        }
        for (companion, name) in zip(exported, names) {
            var arguments = ["id: \(stringLiteral(companion.id))"]
            if companion.anchor != blank.anchor || companion.alignment != blank.alignment {
                arguments.append("anchor: \(anchorLiteral(companion))")
            }
            if differs(companion.spacing, blank.spacing) {
                arguments.append("spacing: \(number(companion.spacing))")
            }
            if let gap = companion.gap {
                arguments.append("gap: \(number(gap))")
            }
            if let rowAlignment = companion.rowAlignment {
                arguments.append("rowAlignment: \(literal(rowAlignment))")
            }
            if companion.visibility != blank.visibility {
                arguments.append("visibility: \(literal(companion.visibility))")
            }
            if companion.outline != blank.outline {
                arguments.append("shape: \(shapeLiteral(companion))")
            }
            if companion.backdrop != blank.backdrop {
                arguments.append("backdrop: \(backdropLiteral(companion))")
            }
            if companion.overridesStyle {
                arguments.append("style: \(styleLiteral(companion.style(over: settings.companionDefaults)))")
            }
            if let size = companion.size {
                arguments.append("size: \(literal(size))")
            }
            if let presence = companion.presence {
                arguments.append("presence: \(literal(presence))")
            }
            if companion.hidesInSettings != blank.hidesInSettings {
                arguments.append("hidesInSettings: \(companion.hidesInSettings)")
            }
            if let label = companion.accessibilityLabel {
                arguments.append("accessibilityLabel: \(stringLiteral(label))")
            }
            if let accent = companion.accent {
                // A closure argument never fits on one line, so this call always breaks.
                arguments.append(
                    "theme: { appState in\n"
                        + "        var theme = chromeTheme(appState)\n"
                        + "        theme.accent = \(literal(accent))\n"
                        + "        return theme\n"
                        + "    }"
                )
            }
            if accented, companion.accent != nil {
                lines += ["configuration.addCompanion("] + argumentLines(arguments, indent: 4) + [") {"]
            } else {
                lines += call("configuration.addCompanion", arguments: arguments, trailer: " {")
            }
            lines.append("    \(name)()")
            lines.append("}")
        }
        return lines.flatMap { $0.components(separatedBy: "\n") }
    }

    /// `configuration.companionSize`, `companionStyle`, and `companionPresence`, when they differ
    /// from the framework's.
    static func companionDefaultLines(_ defaults: PlaygroundSettings.CompanionDefaults) -> [String] {
        let fallback = PlaygroundSettings.CompanionDefaults()
        var lines: [String] = []
        if defaults.size != fallback.size {
            lines.append("configuration.companionSize = \(literal(defaults.size))")
        }
        if defaults.style != fallback.style {
            lines.append("configuration.companionStyle = \(styleLiteral(defaults.style))")
        }
        if defaults.presence != fallback.presence {
            lines.append("configuration.companionPresence = \(literal(defaults.presence))")
        }
        guard !lines.isEmpty else { return [] }
        return ["// How every companion looks and appears, unless it says otherwise."] + lines
    }

    /// A view per companion, holding its items: glyph buttons, labels, and the framework's lock and
    /// gear. Buttons take the companion's size from the environment through `.nookGlyph`, and
    /// labels and accent fills take the companion's palette from `\.nookResolvedTheme`, as they do
    /// in the playground.
    static func companionViewLines(_ settings: PlaygroundSettings) -> [String] {
        var lines: [String] = []
        let exported = exportedCompanions(settings)
        let names = companionViewNames(exported)
        for (companion, name) in zip(exported, names) {
            if !lines.isEmpty { lines.append("") }
            let items = companion.items
            let usesChromeActions = items.contains { item in
                item.type == .button && [.keepOpen, .settings, .collapse].contains(item.action)
            }
            let usesTheme = items.contains { item in
                item.type == .label || (item.type == .button && item.fill == .color && item.fillColor == nil)
            }
            lines.append("struct \(name): View {")
            if usesChromeActions {
                lines.append("    @Environment(\\.nookChromeActions) private var chromeActions")
            }
            if usesTheme {
                lines.append("    @Environment(\\.nookResolvedTheme) private var theme")
            }
            if usesChromeActions || usesTheme {
                lines.append("")
            }
            lines.append("    var body: some View {")
            let size = (companion.size ?? settings.companionDefaults.size).nookSize
            let hasButtons = items.contains { $0.type == .button }
            if items.count == 1 {
                lines += itemLines(items[0], indent: 8, containerStyled: false)
            } else {
                let stack = companion.resolvedLayout == .column ? "VStack" : "HStack"
                lines.append("        \(stack)(spacing: \(number(Double(size.controlSpacing)))) {")
                for item in items {
                    lines += itemLines(item, indent: 12, containerStyled: hasButtons)
                }
                lines.append("        }")
                if hasButtons {
                    lines.append("        .buttonStyle(.nookGlyph)")
                }
            }
            lines.append("    }")
            lines.append("}")
        }
        return lines
    }

    /// The companions the snippet writes: every one that holds something.
    static func exportedCompanions(_ settings: PlaygroundSettings) -> [PlaygroundSettings.Companion] {
        settings.companions.filter { !$0.items.isEmpty }
    }

    /// One item of a companion's content. `containerStyled` says whether the stack around it
    /// already applies `.nookGlyph`, so a button with no changes of its own needs none.
    static func itemLines(_ item: PlaygroundSettings.Item, indent: Int, containerStyled: Bool) -> [String] {
        let padding = String(repeating: " ", count: indent)
        switch item.type {
            case .keepOpen:
                return [padding + "NookKeepOpenButton()"]
            case .settings:
                return [padding + "NookSettingsButton()"]
            case .label:
                // The icon in its own color or the accent, the text in the palette's label color.
                var lines = [padding + "HStack(spacing: 6) {"]
                if let symbol = item.displaySymbol {
                    lines.append(padding + "    Image(systemName: \(stringLiteral(symbol)))")
                    lines.append(padding + "        .foregroundStyle(\(item.tint.map(literal) ?? "theme.accent"))")
                }
                if let title = item.title {
                    lines.append(padding + "    Text(\(stringLiteral(title)))")
                    lines.append(padding + "        .foregroundStyle(theme.primaryLabel)")
                    lines.append(padding + "        .lineLimit(1)")
                }
                lines.append(padding + "}")
                lines.append(padding + ".font(.system(size: 12, weight: .semibold))")
                lines.append(padding + ".padding(.horizontal, 8)")
                lines.append(padding + ".accessibilityElement(children: .combine)")
                return lines
            case .button:
                let symbol = item.displaySymbol ?? item.action.defaultSymbol
                let head = "Button(\(stringLiteral(item.displayTitle)), systemImage: \(stringLiteral(symbol)))"
                var lines = [padding + head + " " + actionLiteral(item.action)]
                let arguments = glyphStyleArguments(item)
                guard !arguments.isEmpty || !containerStyled else { return lines }
                let style = arguments.isEmpty ? ".nookGlyph" : ".nookGlyph(\(arguments.joined(separator: ", ")))"
                let line = padding + "    .buttonStyle(\(style))"
                if line.count <= maximumLineLength {
                    lines.append(line)
                } else {
                    lines.append(padding + "    .buttonStyle(")
                    lines.append(padding + "        .nookGlyph(")
                    lines += argumentLines(arguments, indent: indent + 12)
                    lines.append(padding + "        )")
                    lines.append(padding + "    )")
                }
                return lines
        }
    }

    /// What a button runs: the framework's chrome actions where the playground runs one, and a
    /// comment where the host's own action goes.
    static func actionLiteral(_ action: PlaygroundSettings.Item.Action) -> String {
        switch action {
            case .none: "{}"
            case .status: "{}  // your action"
            case .rimGlow: "{}  // your action, such as lighting the rim with .nookRimGlow(_:)"
            case .keepOpen: "{ chromeActions.toggleKeepOpen() }"
            case .settings: "{ chromeActions.toggleSettings() }"
            case .collapse: "{ chromeActions.collapse() }"
        }
    }

    /// The `.nookGlyph(...)` arguments for what `item` changes; empty for a plain glyph button.
    static func glyphStyleArguments(_ item: PlaygroundSettings.Item) -> [String] {
        var arguments: [String] = []
        if item.size == .surface {
            arguments.append("size: .surface")
        }
        if let tint = item.tint {
            arguments.append("foreground: \(literal(tint))")
        }
        switch item.fill {
            case .none:
                break
            case .subtle:
                arguments.append("fill: .subtle")
            case .color:
                arguments.append("fill: .color(\(item.fillColor.map(literal) ?? "theme.accent"))")
            case .chrome:
                arguments.append("fill: .chromeBackdrop")
        }
        if let fade = item.fade, item.fill != .none, fade < 1 {
            arguments.append("fade: \(fadeLiteral(fade))")
        }
        return arguments
    }

    /// A Swift type name for each companion's content view, unique within the snippet:
    /// `sleep-timer` becomes `SleepTimerCompanion`.
    static func companionViewNames(_ companions: [PlaygroundSettings.Companion]) -> [String] {
        var used = Set<String>(["MyHomeView", "MyNookHome", "HeaderTitle", "HeaderButtons"])
        return companions.map { companion in
            let words = companion.id.split { !$0.isLetter && !$0.isNumber }
            var base = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            if base.isEmpty || base.first?.isNumber == true || !base.unicodeScalars.allSatisfy(\.isASCII) {
                base = "Item" + base.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            }
            var name = base + "Companion"
            var suffix = 2
            while used.contains(name) {
                name = "\(base)Companion\(suffix)"
                suffix += 1
            }
            used.insert(name)
            return name
        }
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
        let defaults = PlaygroundSettings.Behavior()
        var lines: [String] = []
        if behavior.hoverKeepsVisible != defaults.hoverKeepsVisible || behavior.hoverHaptics != defaults.hoverHaptics {
            let value =
                switch (behavior.hoverKeepsVisible, behavior.hoverHaptics) {
                    case (true, true): ".all"
                    case (true, false): ".keepVisible"
                    case (false, true): ".hapticFeedback"
                    case (false, false): "[]"
                }
            lines.append("configuration.chromeBehavior.hoverBehavior = \(value)")
        }
        if behavior.glassShading != defaults.glassShading {
            lines.append("configuration.chromeBehavior.glassShading = .\(behavior.glassShading.rawValue)")
        }
        return lines
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

    static func literal(_ clearance: PlaygroundSettings.TopBar.NotchClearance) -> String {
        switch clearance {
            case .automatic: ".automatic"
            case .manual: ".manual"
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

    static func literal(_ size: PlaygroundSettings.Companion.Size) -> String {
        switch size {
            case .small: ".small"
            case .regular: ".regular"
            case .large: ".large"
        }
    }

    static func literal(_ presence: PlaygroundSettings.Companion.Presence) -> String {
        switch presence {
            case .fold: ".fold"
            case .fade: ".fade"
            case .slide: ".slide"
            case .pop: ".pop"
        }
    }

    static func literal(_ alignment: PlaygroundSettings.Companion.AnchorAlignment) -> String {
        switch alignment {
            case .start: ".start"
            case .center: ".center"
            case .end: ".end"
        }
    }

    /// A companion style: a preset's name when it is one, or `.standard(...)` with what differs.
    static func styleLiteral(_ style: NookStandardCompanionStyle) -> String {
        switch style {
            case .standard: return ".standard"
            case .faded: return ".faded"
            case .raised: return ".raised"
            case .plain: return ".plain"
            default: break
        }
        var arguments: [String] = []
        if let fade = style.fade {
            arguments.append("fade: \(fadeLiteral(fade.end))")
        }
        if style.stroke != nil {
            arguments.append("stroke: .hairline")
        }
        if style.shadow != nil {
            arguments.append("shadow: .soft")
        }
        switch style.hover {
            case .highlight: arguments.append("hover: .highlight")
            case .lift: arguments.append("hover: .lift")
            case .glow: arguments.append("hover: .glow")
            default: break
        }
        return ".standard(\(arguments.joined(separator: ", ")))"
    }

    /// A fade that runs from solid to `end`: `.standard`, `.toClear`, or `.init(end: 0.4)`.
    static func fadeLiteral(_ end: Double) -> String {
        let fade = NookStandardCompanionStyle.Fade(start: 1, end: end)
        if fade == .standard { return ".standard" }
        if fade == .toClear { return ".toClear" }
        return ".init(end: \(number(end)))"
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
