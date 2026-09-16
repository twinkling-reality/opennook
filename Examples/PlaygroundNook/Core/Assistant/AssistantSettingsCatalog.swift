// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookKit
import NookSurface

/// Which part of the playground a field belongs to, so a proposal can be grouped the way the
/// controls window already is.
///
/// It mirrors the window's page list without depending on it: the pages are a view concern in
/// the app target, and this module stays free of them. The app maps a group back to its page,
/// and `AssistantCatalogCoverageTests` checks the two stay in step.
public enum AssistantFieldGroup: String, CaseIterable, Sendable, Identifiable {
    case appearance
    case theme
    case panel
    case typeAndMotion
    case topBar
    case companions
    case effects
    case behavior

    public var id: String { rawValue }

    /// The group's name in a proposal, matching the page it corresponds to.
    public var title: String {
        switch self {
            case .appearance: "Appearance"
            case .theme: "Theme"
            case .panel: "Panel"
            case .typeAndMotion: "Type and Motion"
            case .topBar: "Top Bar"
            case .companions: "Companions"
            case .effects: "Effects"
            case .behavior: "Behavior"
        }
    }
}

/// Every value the assistant may change, described once, in one place.
///
/// This is the single source the model's JSON schema, its field guide, and the proposal card all
/// come from. Ranges are the ones the controls themselves offer, so a model is steered towards
/// values a person could have dialled in by hand; the patch merge normalizes whatever arrives
/// anyway, so a bound here is guidance and never the last line of defence.
///
/// Adding a value to ``PlaygroundSettings`` without adding it here fails
/// `AssistantCatalogCoverageTests`, which walks the JSON a fully populated preset encodes to and
/// compares it against ``fields``.
public enum AssistantSettingsCatalog {
    /// The fields, in the order the field guide lists them.
    public static let fields: [AssistantField] = appearanceFields + settingsFields

    /// The field at `path`, when the assistant is allowed to change it.
    public static func field(at path: AssistantFieldPath) -> AssistantField? {
        fields.first { $0.path == path }
    }

    public static func fields(in group: AssistantFieldGroup) -> [AssistantField] {
        fields.filter { $0.group == group }
    }

    // MARK: - Appearance

    private static var appearanceFields: [AssistantField] {
        let defaults = NookAppearancePreferences.default
        return [
            choice(
                "appearance.chromePalette",
                of: NookChromePalette.self,
                default: defaults.chromePalette.rawValue,
                "Follow the system appearance, or pin the chrome to dark or light."
            ),
            choice(
                "appearance.surfaceStyle",
                of: NookSurfaceStyle.self,
                default: defaults.surfaceStyle.rawValue,
                "Opaque like the notch, frosted so the wallpaper shows through, or Liquid Glass."
            ),
            choice(
                "appearance.presentation",
                of: NookPresentation.self,
                default: defaults.presentation.rawValue,
                "Fused to the notch, floating free of it, or automatic for the display."
            ),
            flag(
                "appearance.hapticFeedbackEnabled",
                default: defaults.hapticFeedbackEnabled,
                "Play a trackpad haptic when something finishes."
            ),
            choice(
                "appearance.accentPreset",
                of: NookAccentPreset.self,
                default: defaults.accentPreset.rawValue,
                "The tint of the chrome's own controls. An accent under theme wins over it."
            ),
            number(
                "appearance.backdropStrength",
                default: defaults.backdropStrength,
                0.15,
                1,
                .fraction,
                "How much a frosted backdrop darkens behind the content. Lower shows more wallpaper."
            ),
        ]
    }

    // MARK: - Settings

    private static var settingsFields: [AssistantField] {
        themeFields + panelFields + metricsFields + typographyFields + motionFields + labelFields + topBarFields
            + companionFields + effectFields + behaviorFields
    }

    private static var themeFields: [AssistantField] {
        let defaults = PlaygroundSettings.Theme()
        var fields = PlaygroundSettings.Theme.ColorRole.allCases.map { role in
            color("settings.theme.\(role.rawValue)", themeColorSummary(role))
        }
        fields.append(
            choice(
                "settings.theme.fontDesign",
                of: PlaygroundSettings.FontDesign.self,
                default: defaults.fontDesign.rawValue,
                "The type family for all chrome text. Only these four system designs exist."
            )
        )
        return fields
    }

    private static func themeColorSummary(_ role: PlaygroundSettings.Theme.ColorRole) -> String {
        switch role {
            case .accent:
                "The color of active controls and selection throughout the chrome."
            case .primaryLabel:
                "The color of the most prominent text."
            case .secondaryLabel:
                "The color of supporting text."
            case .tertiaryLabel:
                "The color of the faintest readable text."
            case .quaternaryLabel:
                "The color of decorative text and separators."
            case .subtleFill:
                "The fill behind small controls and chips."
            case .subtleStroke:
                "The hairline around small controls and chips."
            case .headerInactiveIcon:
                "The color of a top bar icon that is not active."
        }
    }

    private static var panelFields: [AssistantField] {
        let defaults = PlaygroundSettings.Panel()
        return [
            number(
                "settings.panel.expandedWidth",
                default: defaults.expandedWidth,
                320,
                760,
                .points,
                "How wide the panel is once expanded."
            ),
            number(
                "settings.panel.topCornerRadius",
                default: defaults.topCornerRadius,
                0,
                40,
                .points,
                "How round the panel's top corners are, where it meets the notch."
            ),
            number(
                "settings.panel.bottomCornerRadius",
                default: defaults.bottomCornerRadius,
                0,
                48,
                .points,
                "How round the panel's bottom corners are."
            ),
            number(
                "settings.panel.insetTop",
                default: defaults.insetTop,
                0,
                32,
                .points,
                "The gap between the panel's top edge and its content."
            ),
            number(
                "settings.panel.insetBottom",
                default: defaults.insetBottom,
                0,
                32,
                .points,
                "The gap between the panel's bottom edge and its content."
            ),
            number(
                "settings.panel.insetLeading",
                default: defaults.insetLeading,
                0,
                32,
                .points,
                "The gap between the panel's leading edge and its content."
            ),
            number(
                "settings.panel.insetTrailing",
                default: defaults.insetTrailing,
                0,
                32,
                .points,
                "The gap between the panel's trailing edge and its content."
            ),
        ]
    }

    private static var metricsFields: [AssistantField] {
        let defaults = PlaygroundSettings.Metrics()
        return [
            number(
                "settings.metrics.edgePadding",
                default: defaults.edgePadding,
                0,
                24,
                .points,
                "The padding inside the chrome's own edges."
            ),
            number(
                "settings.metrics.expandedColumnSpacing",
                default: defaults.expandedColumnSpacing,
                0,
                24,
                .points,
                "The vertical gap between rows of expanded content."
            ),
            number(
                "settings.metrics.topBarHeight",
                default: defaults.topBarHeight,
                16,
                44,
                .points,
                "How tall the top bar is."
            ),
            number(
                "settings.metrics.headerIconSize",
                default: defaults.headerIconSize,
                16,
                40,
                .points,
                "The size of the icon buttons in the top bar."
            ),
            number(
                "settings.metrics.headerIconCornerRadius",
                default: defaults.headerIconCornerRadius,
                0,
                20,
                .points,
                "How round those icon buttons are. Half the size makes them circles."
            ),
            number(
                "settings.metrics.compactSlotSize",
                default: defaults.compactSlotSize,
                16,
                36,
                .points,
                "The size of the small slots shown while the nook is collapsed."
            ),
            number(
                "settings.metrics.bannerCornerRadius",
                default: defaults.bannerCornerRadius,
                0,
                20,
                .points,
                "How round the status banner is."
            ),
        ]
    }

    private static var typographyFields: [AssistantField] {
        let defaults = PlaygroundSettings.Typography()
        return typographyRoles.flatMap { role, summary in
            let spec = defaults[role]
            return [
                number(
                    "settings.typography.\(role.rawValue).size",
                    default: spec.size,
                    8,
                    20,
                    .points,
                    "The size of \(summary) Half points are allowed."
                ),
                choice(
                    "settings.typography.\(role.rawValue).weight",
                    of: PlaygroundSettings.FontWeight.self,
                    default: spec.weight.rawValue,
                    "The weight of \(summary)"
                ),
            ]
        }
    }

    private static var typographyRoles: [(PlaygroundSettings.Typography.Role, String)] {
        PlaygroundSettings.Typography.Role.allCases.map { role in
            switch role {
                case .headerIcon: (role, "the glyphs in the top bar's icon buttons.")
                case .topBarLabel: (role, "the top bar's title.")
                case .bannerMessage: (role, "the status banner's message.")
                case .compactLeadingGlyph: (role, "the glyph in the collapsed nook's leading slot.")
            }
        }
    }

    private static var motionFields: [AssistantField] {
        let defaults = PlaygroundSettings.Motion()
        return PlaygroundSettings.Motion.Role.allCases.flatMap { role in
            let spring = defaults[role]
            let subject =
                switch role {
                    case .viewModeChange: "the panel switches between home and Settings"
                    case .statusBanner: "the status banner arrives and leaves"
                }
            return [
                number(
                    "settings.motion.\(role.rawValue).response",
                    default: spring.response,
                    0.1,
                    1.5,
                    .seconds,
                    "How long the spring takes as \(subject). Lower is snappier."
                ),
                number(
                    "settings.motion.\(role.rawValue).dampingFraction",
                    default: spring.dampingFraction,
                    0.2,
                    1.2,
                    .none,
                    "How much the spring settles as \(subject). Below 1 overshoots and bounces."
                ),
            ]
        }
    }

    private static var labelFields: [AssistantField] {
        let defaults = PlaygroundSettings.Labels()
        return [
            text(
                "settings.labels.settingsBreadcrumb",
                default: defaults.settingsBreadcrumb,
                "The word the Settings screen is titled with."
            ),
            text(
                "settings.labels.keepOpenHelp",
                default: defaults.keepOpenHelp,
                "The tooltip on the top bar's lock button."
            ),
            text(
                "settings.labels.settingsHelp",
                default: defaults.settingsHelp,
                "The tooltip on the top bar's gear button."
            ),
            text(
                "settings.labels.dismissHelp",
                default: defaults.dismissHelp,
                "The tooltip on the control that closes the panel."
            ),
        ]
    }

    private static var topBarFields: [AssistantField] {
        let defaults = PlaygroundSettings.TopBar()
        return [
            flag(
                "settings.topBar.showsTopBar",
                default: defaults.showsTopBar,
                "Whether the panel has a top bar at all. Off leaves only the content."
            ),
            flag(
                "settings.topBar.showsSettings",
                default: defaults.showsSettings,
                "Whether the built-in Settings screen can be reached."
            ),
            flag(
                "settings.topBar.showsKeepOpenButton",
                default: defaults.showsKeepOpenButton,
                "Whether the lock sits in the top bar. Off keeps the feature but frees the slot, "
                    + "so a companion of kind controls can hold it instead."
            ),
            flag(
                "settings.topBar.showsSettingsButton",
                default: defaults.showsSettingsButton,
                "Whether the gear sits in the top bar. Off works like the lock above."
            ),
            flag(
                "settings.topBar.showsStatusBanner",
                default: defaults.showsStatusBanner,
                "Whether short status messages appear under the top bar."
            ),
            choice(
                "settings.topBar.width",
                of: PlaygroundSettings.TopBar.Width.self,
                default: defaults.width.rawValue,
                "Whether the top bar spans the content column or only fits its own items."
            ),
            choice(
                "settings.topBar.notchClearance",
                of: PlaygroundSettings.TopBar.NotchClearance.self,
                default: defaults.notchClearance.rawValue,
                "Whether expanded content is kept clear of the physical notch automatically."
            ),
            flag(
                "settings.topBar.notchAccessories",
                default: defaults.notchAccessories,
                "Whether the home view's header sits beside the notch rather than below it."
            ),
            text(
                "settings.topBar.leadingTitle",
                default: defaults.leadingTitle,
                "The title at the leading end of the top bar."
            ),
            AssistantField(
                path: AssistantFieldPath("settings.topBar.leadingIcon"),
                group: .topBar,
                kind: .text,
                summary: "An SF Symbol name beside that title, such as \"music.note\". Null uses the brand mark.",
                defaultValue: .null,
                isNullable: true
            ),
        ]
    }

    private static var companionFields: [AssistantField] {
        let defaults = PlaygroundSettings.Companion(id: "", kind: .actions)
        return [
            text(
                "settings.companions[].id",
                group: .companions,
                default: "",
                "A short unique name for this companion, such as \"sleep-timer\". Required."
            ),
            choice(
                "settings.companions[].kind",
                group: .companions,
                of: PlaygroundSettings.Companion.Kind.self,
                default: defaults.kind.rawValue,
                "What the companion holds: a pill of icon buttons, one round button, the nook's "
                    + "own lock and gear, or a short status label. Required."
            ),
            choice(
                "settings.companions[].anchor",
                group: .companions,
                of: PlaygroundSettings.Companion.Anchor.self,
                default: defaults.anchor.rawValue,
                "Which side of the panel it sits on."
            ),
            choice(
                "settings.companions[].alignment",
                group: .companions,
                of: PlaygroundSettings.Companion.AnchorAlignment.self,
                default: defaults.alignment.rawValue,
                "Where along that side it sits."
            ),
            number(
                "settings.companions[].spacing",
                group: .companions,
                default: defaults.spacing,
                0,
                40,
                .points,
                "The gap between it and the panel."
            ),
            choice(
                "settings.companions[].visibility",
                group: .companions,
                of: PlaygroundSettings.Companion.Visibility.self,
                default: defaults.visibility.rawValue,
                "Whether it shows while the nook is expanded, while it is collapsed, or both."
            ),
            choice(
                "settings.companions[].outline",
                group: .companions,
                of: PlaygroundSettings.Companion.Outline.self,
                default: defaults.outline.rawValue,
                "Its shape. Use circle for a single round button."
            ),
            number(
                "settings.companions[].cornerRadius",
                group: .companions,
                default: defaults.cornerRadius,
                0,
                30,
                .points,
                "How round it is, used only by the roundedRectangle outline."
            ),
            choice(
                "settings.companions[].backdrop",
                group: .companions,
                of: PlaygroundSettings.Companion.Backdrop.self,
                default: defaults.backdrop.rawValue,
                "Its background: the chrome's own, a solid color, Liquid Glass, or none."
            ),
            AssistantField(
                path: AssistantFieldPath("settings.companions[].backdropColor"),
                group: .companions,
                kind: .color,
                summary: "The color for the solid and glass backdrops.",
                defaultValue: .string(defaults.backdropColor.hex)
            ),
            flag(
                "settings.companions[].hidesInSettings",
                group: .companions,
                default: defaults.hidesInSettings,
                "Whether it disappears while the Settings screen is showing."
            ),
            AssistantField(
                path: AssistantFieldPath("settings.companions[].accessibilityLabel"),
                group: .companions,
                kind: .text,
                summary: "What VoiceOver calls it. Always set one.",
                defaultValue: .null,
                isNullable: true
            ),
        ]
    }

    private static var effectFields: [AssistantField] {
        let rim = PlaygroundSettings.RimGlow()
        let fade = PlaygroundSettings.ScrollEdgeFade()
        return [
            number(
                "settings.rimGlow.lineWidth",
                group: .effects,
                default: rim.lineWidth,
                0,
                6,
                .points,
                "How thick the glowing rim around the panel is."
            ),
            number(
                "settings.rimGlow.glowRadius",
                group: .effects,
                default: rim.glowRadius,
                0,
                30,
                .points,
                "How far that glow spreads."
            ),
            number(
                "settings.rimGlow.intensity",
                group: .effects,
                default: rim.intensity,
                0,
                1,
                .fraction,
                "How bright the glow is."
            ),
            flag(
                "settings.rimGlow.pulses",
                group: .effects,
                default: rim.pulses,
                "Whether the glow breathes rather than holding steady."
            ),
            flag(
                "settings.rimGlow.followsAmbientColor",
                group: .effects,
                default: rim.followsAmbientColor,
                "Whether the glow takes its color from the content instead of the caller."
            ),
            flag(
                "settings.scrollEdgeFade.isEnabled",
                group: .effects,
                default: fade.isEnabled,
                "Whether scrolling content softens where it meets the panel's edges."
            ),
            flag(
                "settings.scrollEdgeFade.top",
                group: .effects,
                default: fade.top,
                "Whether that softening applies at the top edge."
            ),
            flag(
                "settings.scrollEdgeFade.bottom",
                group: .effects,
                default: fade.bottom,
                "Whether that softening applies at the bottom edge."
            ),
            flag(
                "settings.scrollEdgeFade.leading",
                group: .effects,
                default: fade.leading,
                "Whether that softening applies at the leading edge."
            ),
            flag(
                "settings.scrollEdgeFade.trailing",
                group: .effects,
                default: fade.trailing,
                "Whether that softening applies at the trailing edge."
            ),
            number(
                "settings.scrollEdgeFade.length",
                group: .effects,
                default: fade.length,
                0,
                60,
                .points,
                "How far that softening reaches in from the edge."
            ),
        ]
    }

    private static var behaviorFields: [AssistantField] {
        let defaults = PlaygroundSettings.Behavior()
        return [
            flag(
                "settings.behavior.hoverKeepsVisible",
                group: .behavior,
                default: defaults.hoverKeepsVisible,
                "Whether the panel stays open while the pointer is over it."
            ),
            flag(
                "settings.behavior.hoverHaptics",
                group: .behavior,
                default: defaults.hoverHaptics,
                "Whether hovering the nook plays a haptic."
            ),
        ]
    }

    // MARK: - Building fields

    /// The group a path belongs to, from its first two components, so the common case needs no
    /// group argument and cannot disagree with the path.
    private static func inferredGroup(_ path: String) -> AssistantFieldGroup {
        if path.hasPrefix("appearance.") { return .appearance }
        if path.hasPrefix("settings.theme.") { return .theme }
        if path.hasPrefix("settings.panel.") || path.hasPrefix("settings.metrics.") { return .panel }
        if path.hasPrefix("settings.typography.") || path.hasPrefix("settings.motion.") { return .typeAndMotion }
        if path.hasPrefix("settings.topBar.") || path.hasPrefix("settings.labels.") { return .topBar }
        if path.hasPrefix("settings.companions") { return .companions }
        if path.hasPrefix("settings.rimGlow.") || path.hasPrefix("settings.scrollEdgeFade.") { return .effects }
        return .behavior
    }

    private static func number(
        _ path: String,
        group: AssistantFieldGroup? = nil,
        default defaultValue: Double,
        _ minimum: Double?,
        _ maximum: Double?,
        _ unit: AssistantField.Unit,
        _ summary: String
    ) -> AssistantField {
        AssistantField(
            path: AssistantFieldPath(path),
            group: group ?? inferredGroup(path),
            kind: .number(minimum: minimum, maximum: maximum, unit: unit),
            summary: summary,
            defaultValue: .number(defaultValue)
        )
    }

    private static func flag(
        _ path: String,
        group: AssistantFieldGroup? = nil,
        default defaultValue: Bool,
        _ summary: String
    ) -> AssistantField {
        AssistantField(
            path: AssistantFieldPath(path),
            group: group ?? inferredGroup(path),
            kind: .flag,
            summary: summary,
            defaultValue: .bool(defaultValue)
        )
    }

    private static func text(
        _ path: String,
        group: AssistantFieldGroup? = nil,
        default defaultValue: String,
        _ summary: String
    ) -> AssistantField {
        AssistantField(
            path: AssistantFieldPath(path),
            group: group ?? inferredGroup(path),
            kind: .text,
            summary: summary,
            defaultValue: .string(defaultValue)
        )
    }

    /// A theme color, which is null until something overrides the live palette.
    private static func color(_ path: String, _ summary: String) -> AssistantField {
        AssistantField(
            path: AssistantFieldPath(path),
            group: inferredGroup(path),
            kind: .color,
            summary: summary + " Null follows the user's own palette and accent.",
            defaultValue: .null,
            isNullable: true
        )
    }

    /// A field whose values are the cases of `type`, so a new case reaches the model with no
    /// change here.
    private static func choice<Value>(
        _ path: String,
        group: AssistantFieldGroup? = nil,
        of type: Value.Type,
        default defaultValue: String,
        _ summary: String
    ) -> AssistantField
    where Value: RawRepresentable & CaseIterable, Value.RawValue == String {
        AssistantField(
            path: AssistantFieldPath(path),
            group: group ?? inferredGroup(path),
            kind: .choice(Value.allCases.map(\.rawValue)),
            summary: summary,
            defaultValue: .string(defaultValue)
        )
    }
}
