// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookKit
import NookSurface
import SwiftUI

/// Everything PlaygroundNook changes about the chrome, as plain values. It is the source of
/// the live configuration (``makeConfiguration(home:companion:)``), of the Swift export, and of
/// JSON presets.
///
/// Every default is the framework's own, so an untouched playground shows the stock chrome and
/// the Swift export lists only what was changed. The user's appearance preferences (palette,
/// surface, layout, accent) are not part of it: they live in `AppState` as in any host, and a
/// ``PlaygroundPreset`` carries them alongside.
///
/// Decoding tolerates missing keys - each falls back to its default - so a preset written by
/// an earlier version of the playground still opens. A key that is present with a value of
/// the wrong type is still an error.
public struct PlaygroundSettings: Equatable, Sendable {
    public var theme = Theme()
    public var panel = Panel()
    public var metrics = Metrics()
    public var typography = Typography()
    public var motion = Motion()
    public var labels = Labels()
    public var topBar = TopBar()
    public var companions: [Companion] = []
    public var rimGlow = RimGlow()
    public var scrollEdgeFade = ScrollEdgeFade()
    public var behavior = Behavior()

    public init() {}

    public static let `default` = PlaygroundSettings()
}

// MARK: - Groups

extension PlaygroundSettings {
    /// Overrides on top of the live palette (`NookResolvedTheme.live(appState:)`). `nil` keeps
    /// the live color, which follows the user's palette and accent preferences.
    public struct Theme: Equatable, Sendable {
        public var accent: PlaygroundColor?
        public var fontDesign: FontDesign = .default
        public var primaryLabel: PlaygroundColor?
        public var secondaryLabel: PlaygroundColor?
        public var tertiaryLabel: PlaygroundColor?
        public var quaternaryLabel: PlaygroundColor?
        public var subtleFill: PlaygroundColor?
        public var subtleStroke: PlaygroundColor?
        public var headerInactiveIcon: PlaygroundColor?

        public init() {}

        /// One overridable `NookResolvedTheme` color. The raw value is the property name, on
        /// both `Theme` and `NookResolvedTheme`; the cases are in the order the playground lists
        /// and exports them.
        public enum ColorRole: String, CaseIterable, Identifiable, Sendable {
            case accent
            case primaryLabel
            case secondaryLabel
            case tertiaryLabel
            case quaternaryLabel
            case subtleFill
            case subtleStroke
            case headerInactiveIcon

            public var id: String { rawValue }

            public var title: String {
                switch self {
                    case .accent: "Accent"
                    case .primaryLabel: "Primary label"
                    case .secondaryLabel: "Secondary label"
                    case .tertiaryLabel: "Tertiary label"
                    case .quaternaryLabel: "Quaternary label"
                    case .subtleFill: "Subtle fill"
                    case .subtleStroke: "Subtle stroke"
                    case .headerInactiveIcon: "Inactive header icon"
                }
            }

            /// This role's color in a resolved palette.
            public func color(in theme: NookResolvedTheme) -> Color {
                switch self {
                    case .accent: theme.accent
                    case .primaryLabel: theme.primaryLabel
                    case .secondaryLabel: theme.secondaryLabel
                    case .tertiaryLabel: theme.tertiaryLabel
                    case .quaternaryLabel: theme.quaternaryLabel
                    case .subtleFill: theme.subtleFill
                    case .subtleStroke: theme.subtleStroke
                    case .headerInactiveIcon: theme.headerInactiveIcon
                }
            }

            func set(_ color: Color, in theme: inout NookResolvedTheme) {
                switch self {
                    case .accent: theme.accent = color
                    case .primaryLabel: theme.primaryLabel = color
                    case .secondaryLabel: theme.secondaryLabel = color
                    case .tertiaryLabel: theme.tertiaryLabel = color
                    case .quaternaryLabel: theme.quaternaryLabel = color
                    case .subtleFill: theme.subtleFill = color
                    case .subtleStroke: theme.subtleStroke = color
                    case .headerInactiveIcon: theme.headerInactiveIcon = color
                }
            }
        }

        /// The override for `role`, or `nil` for the live color.
        public subscript(role: ColorRole) -> PlaygroundColor? {
            get {
                switch role {
                    case .accent: accent
                    case .primaryLabel: primaryLabel
                    case .secondaryLabel: secondaryLabel
                    case .tertiaryLabel: tertiaryLabel
                    case .quaternaryLabel: quaternaryLabel
                    case .subtleFill: subtleFill
                    case .subtleStroke: subtleStroke
                    case .headerInactiveIcon: headerInactiveIcon
                }
            }
            set {
                switch role {
                    case .accent: accent = newValue
                    case .primaryLabel: primaryLabel = newValue
                    case .secondaryLabel: secondaryLabel = newValue
                    case .tertiaryLabel: tertiaryLabel = newValue
                    case .quaternaryLabel: quaternaryLabel = newValue
                    case .subtleFill: subtleFill = newValue
                    case .subtleStroke: subtleStroke = newValue
                    case .headerInactiveIcon: headerInactiveIcon = newValue
                }
            }
        }

        /// Writes the overrides into a resolved palette.
        public func apply(to theme: inout NookResolvedTheme) {
            for role in ColorRole.allCases {
                if let color = self[role] {
                    role.set(color.color, in: &theme)
                }
            }
            theme.fontDesign = fontDesign.design
        }
    }

    public enum FontDesign: String, Codable, CaseIterable, Sendable {
        case `default`
        case rounded
        case serif
        case monospaced

        public var design: Font.Design {
            switch self {
                case .default: .default
                case .rounded: .rounded
                case .serif: .serif
                case .monospaced: .monospaced
            }
        }
    }

    /// The panel's width and shape: `NookConfiguration.expandedWidth` and
    /// `NookConfiguration.style`.
    public struct Panel: Equatable, Sendable {
        public var expandedWidth = Double(NookLayout.width)
        public var topCornerRadius = Double(Panel.defaultStyle.topCornerRadius)
        public var bottomCornerRadius = Double(Panel.defaultStyle.bottomCornerRadius)
        public var insetTop = Double(Panel.defaultStyle.expandedContentInsets.top)
        public var insetBottom = Double(Panel.defaultStyle.expandedContentInsets.bottom)
        public var insetLeading = Double(Panel.defaultStyle.expandedContentInsets.leading)
        public var insetTrailing = Double(Panel.defaultStyle.expandedContentInsets.trailing)

        public init() {}

        static let defaultStyle = NookConfiguration.defaultStyle

        /// The style these values describe, or `nil` when it is the framework's default.
        public var style: NookStyle? {
            let style = NookStyle(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                expandedContentInsets: NookEdgeInsets(
                    top: insetTop,
                    bottom: insetBottom,
                    leading: insetLeading,
                    trailing: insetTrailing
                )
            )
            return style == Self.defaultStyle ? nil : style
        }
    }

    /// A few of the most visible `NookChromeMetrics` values.
    public struct Metrics: Equatable, Sendable {
        public var edgePadding = Double(Metrics.base.edgePadding)
        public var expandedColumnSpacing = Double(Metrics.base.expandedColumnSpacing)
        public var topBarHeight = Double(Metrics.base.topBarHeight)
        public var headerIconSize = Double(Metrics.base.headerIconSize)
        public var headerIconCornerRadius = Double(Metrics.base.headerIconCornerRadius)
        public var compactSlotSize = Double(Metrics.base.compactSlotSize)
        public var bannerCornerRadius = Double(Metrics.base.bannerCornerRadius)

        public init() {}

        static let base = NookChromeMetrics.default

        public var chromeMetrics: NookChromeMetrics {
            var metrics = Self.base
            metrics.edgePadding = edgePadding
            metrics.expandedColumnSpacing = expandedColumnSpacing
            metrics.topBarHeight = topBarHeight
            metrics.headerIconSize = headerIconSize
            metrics.headerIconCornerRadius = headerIconCornerRadius
            metrics.compactSlotSize = compactSlotSize
            metrics.bannerCornerRadius = bannerCornerRadius
            return metrics
        }
    }

    /// A few `NookChromeTypography` roles. The defaults restate the framework's fonts, which
    /// cannot be read back from a `Font`; `PlaygroundNookTests` checks that they still match.
    public struct Typography: Equatable, Sendable {
        public var headerIcon = FontSpec(size: 11, weight: .semibold)
        public var topBarLabel = FontSpec(size: 11, weight: .regular)
        public var bannerMessage = FontSpec(size: 10.5, weight: .medium)
        public var compactLeadingGlyph = FontSpec(size: 10, weight: .semibold)

        public init() {}

        /// Only the roles that differ from the defaults are replaced, so an untouched value
        /// leaves the framework's own fonts in place.
        public var chromeTypography: NookChromeTypography {
            var typography = NookChromeTypography.default
            let defaults = Typography()
            if headerIcon != defaults.headerIcon { typography.headerIcon = headerIcon.font }
            if topBarLabel != defaults.topBarLabel { typography.topBarLabel = topBarLabel.font }
            if bannerMessage != defaults.bannerMessage { typography.bannerMessage = bannerMessage.font }
            if compactLeadingGlyph != defaults.compactLeadingGlyph {
                typography.compactLeadingGlyph = compactLeadingGlyph.font
            }
            return typography
        }
    }

    public struct FontSpec: Codable, Equatable, Sendable {
        public var size: Double
        public var weight: FontWeight

        public init(size: Double, weight: FontWeight) {
            self.size = size
            self.weight = weight
        }

        public var font: Font { .system(size: size, weight: weight.weight) }
    }

    public enum FontWeight: String, Codable, CaseIterable, Sendable {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black

        public var weight: Font.Weight {
            switch self {
                case .ultraLight: .ultraLight
                case .thin: .thin
                case .light: .light
                case .regular: .regular
                case .medium: .medium
                case .semibold: .semibold
                case .bold: .bold
                case .heavy: .heavy
                case .black: .black
            }
        }
    }

    /// Two `NookChromeMotion` springs. Like ``Typography``, the defaults restate the
    /// framework's, and the tests keep them honest.
    public struct Motion: Equatable, Sendable {
        public var viewModeChange = SpringSpec(response: 0.38, dampingFraction: 0.84)
        public var statusBanner = SpringSpec(response: 0.34, dampingFraction: 0.86)

        public init() {}

        public var chromeMotion: NookChromeMotion {
            var motion = NookChromeMotion.default
            let defaults = Motion()
            if viewModeChange != defaults.viewModeChange { motion.viewModeChange = viewModeChange.animation }
            if statusBanner != defaults.statusBanner { motion.statusBanner = statusBanner.animation }
            return motion
        }
    }

    public struct SpringSpec: Codable, Equatable, Sendable {
        public var response: Double
        public var dampingFraction: Double

        public init(response: Double, dampingFraction: Double) {
            self.response = response
            self.dampingFraction = dampingFraction
        }

        public var animation: Animation {
            .spring(response: response, dampingFraction: dampingFraction)
        }
    }

    /// `NookChromeLabels`, all four strings.
    public struct Labels: Equatable, Sendable {
        public var settingsBreadcrumb = Labels.base.settingsBreadcrumb
        public var keepOpenHelp = Labels.base.keepOpenHelp
        public var settingsHelp = Labels.base.settingsHelp
        public var dismissHelp = Labels.base.dismissHelp

        public init() {}

        static let base = NookChromeLabels.default

        public var chromeLabels: NookChromeLabels {
            NookChromeLabels(
                settingsBreadcrumb: settingsBreadcrumb,
                keepOpenHelp: keepOpenHelp,
                settingsHelp: settingsHelp,
                dismissHelp: dismissHelp
            )
        }
    }

    /// `NookTopBarConfiguration`, minus the trailing items, which are host content.
    public struct TopBar: Equatable, Sendable {
        public enum Width: String, Codable, CaseIterable, Sendable {
            case contentColumn
            case intrinsic
        }

        public var showsTopBar = TopBar.base.showsTopBar
        public var showsSettings = TopBar.base.showsSettings
        public var showsKeepOpenButton = TopBar.base.showsKeepOpenButton
        public var showsSettingsButton = TopBar.base.showsSettingsButton
        public var showsStatusBanner = TopBar.base.showsStatusBanner
        public var width: Width = .contentColumn
        /// The framework's default title, restated because it is only reachable through a
        /// closure that takes an `AppState`.
        public var leadingTitle = "Home"
        /// An SF Symbol name, or `nil` for the brand mark.
        public var leadingIcon: String?

        public init() {}

        static let base = NookTopBarConfiguration.default

        public func apply(to topBar: inout NookTopBarConfiguration) {
            topBar.showsTopBar = showsTopBar
            topBar.showsSettings = showsSettings
            topBar.showsKeepOpenButton = showsKeepOpenButton
            topBar.showsSettingsButton = showsSettingsButton
            topBar.showsStatusBanner = showsStatusBanner
            topBar.width =
                switch width {
                    case .contentColumn: .contentColumn
                    case .intrinsic: .intrinsic
                }
            if leadingTitle != TopBar().leadingTitle {
                let title = leadingTitle
                topBar.leadingTitle = { _ in title }
            }
            topBar.leadingIcon = leadingIcon
        }
    }

    /// One companion surface. The content is one of a few demo views (``Kind``); everything
    /// else maps onto a parameter of `NookConfiguration.addCompanion`, with the same defaults.
    public struct Companion: Identifiable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            /// A pill of icon buttons.
            case actions
            /// A single round button.
            case button
            /// The framework's keep-open and Settings buttons.
            case controls
            /// A short status label.
            case chip
        }

        public enum Anchor: String, Codable, CaseIterable, Sendable {
            case below
            case leading
            case trailing
        }

        public enum AnchorAlignment: String, Codable, CaseIterable, Sendable {
            case start
            case center
            case end
        }

        public enum Visibility: String, Codable, CaseIterable, Sendable {
            case expanded
            case compact
            case both
        }

        public enum Outline: String, Codable, CaseIterable, Sendable {
            case capsule
            case circle
            case roundedRectangle
        }

        public enum Backdrop: String, Codable, CaseIterable, Sendable {
            /// The chrome's backdrop.
            case inherit
            /// A solid fill in ``Companion/backdropColor``.
            case solid
            /// Liquid Glass tinted with ``Companion/backdropColor``.
            case glass
            /// No backdrop; the content draws its own.
            case none
        }

        public var id: String
        public var kind: Kind
        public var anchor: Anchor = .below
        public var alignment: AnchorAlignment = .center
        public var spacing = Double(NookCompanionSurface.defaultSpacing)
        public var visibility: Visibility = .expanded
        public var outline: Outline = .capsule
        /// Used by the `roundedRectangle` outline.
        public var cornerRadius: Double = 12
        public var backdrop: Backdrop = .inherit
        /// Used by the `solid` and `glass` backdrops.
        public var backdropColor = PlaygroundColor(red: 0.25, green: 0.55, blue: 0.98)
        public var hidesInSettings = true
        public var accessibilityLabel: String?

        public init(id: String, kind: Kind, accessibilityLabel: String? = nil) {
            self.id = id
            self.kind = kind
            self.accessibilityLabel = accessibilityLabel
        }

        public var nookAnchor: NookCompanionAnchor {
            let alignment: NookCompanionAnchor.Alignment =
                switch self.alignment {
                    case .start: .start
                    case .center: .center
                    case .end: .end
                }
            return switch anchor {
                case .below: .below(alignment: alignment)
                case .leading: .leading(alignment: alignment)
                case .trailing: .trailing(alignment: alignment)
            }
        }

        public var nookVisibility: NookCompanionVisibility {
            switch visibility {
                case .expanded: .expanded
                case .compact: .compact
                case .both: .both
            }
        }

        public var nookShape: NookCompanionShape {
            switch outline {
                case .capsule: .capsule
                case .circle: .circle
                case .roundedRectangle: .roundedRectangle(cornerRadius: cornerRadius)
            }
        }

        public var nookBackdrop: NookCompanionBackdrop {
            switch backdrop {
                case .inherit: .inherit
                case .solid: .custom(.solid(backdropColor.color))
                case .glass: .custom(.liquidGlass(NookBackdrop.LiquidGlass(tint: backdropColor.color)))
                case .none: .none
            }
        }
    }

    /// `NookRimGlowStyle`, all five values.
    public struct RimGlow: Equatable, Sendable {
        public var lineWidth = Double(RimGlow.base.lineWidth)
        public var glowRadius = Double(RimGlow.base.glowRadius)
        public var intensity = RimGlow.base.intensity
        public var pulses = RimGlow.base.pulses
        public var followsAmbientColor = RimGlow.base.followsAmbientColor

        public init() {}

        static let base = NookRimGlowStyle.standard

        public var style: NookRimGlowStyle {
            NookRimGlowStyle(
                lineWidth: lineWidth,
                glowRadius: glowRadius,
                intensity: intensity,
                pulses: pulses,
                followsAmbientColor: followsAmbientColor
            )
        }
    }

    /// `NookConfiguration.scrollEdgeFade`: off by default, `NookScrollEdgeFade.standard` when
    /// switched on without other changes.
    public struct ScrollEdgeFade: Equatable, Sendable {
        public var isEnabled = false
        public var top = ScrollEdgeFade.base.edges.contains(.top)
        public var bottom = ScrollEdgeFade.base.edges.contains(.bottom)
        public var leading = ScrollEdgeFade.base.edges.contains(.leading)
        public var trailing = ScrollEdgeFade.base.edges.contains(.trailing)
        public var length = Double(ScrollEdgeFade.base.length)

        public init() {}

        static let base = NookScrollEdgeFade.standard

        public var edges: Edge.Set {
            var edges: Edge.Set = []
            if top { edges.insert(.top) }
            if bottom { edges.insert(.bottom) }
            if leading { edges.insert(.leading) }
            if trailing { edges.insert(.trailing) }
            return edges
        }

        public var fade: NookScrollEdgeFade? {
            isEnabled ? NookScrollEdgeFade(edges: edges, length: length) : nil
        }
    }

    /// `NookChromeBehavior.hoverBehavior`.
    public struct Behavior: Equatable, Sendable {
        public var hoverKeepsVisible = Behavior.base.contains(.keepVisible)
        public var hoverHaptics = Behavior.base.contains(.hapticFeedback)

        public init() {}

        static let base = NookChromeBehavior.default.hoverBehavior

        public var hoverBehavior: NookHoverBehavior {
            var behavior: NookHoverBehavior = []
            if hoverKeepsVisible { behavior.insert(.keepVisible) }
            if hoverHaptics { behavior.insert(.hapticFeedback) }
            return behavior
        }
    }
}

extension PlaygroundSettings.Companion.Kind {
    public var title: String {
        switch self {
            case .actions: "Action pill"
            case .button: "Round button"
            case .controls: "Nook controls"
            case .chip: "Status chip"
        }
    }

    public var suggestedAccessibilityLabel: String {
        switch self {
            case .actions: "Actions"
            case .button: "Rim glow"
            case .controls: "Nook controls"
            case .chip: "Status"
        }
    }

    /// The id a new companion of this kind starts with.
    public var suggestedID: String {
        switch self {
            case .actions: "actions"
            case .button: "button"
            case .controls: "controls"
            case .chip: "status"
        }
    }
}

// MARK: - Normalizing

extension PlaygroundSettings {
    /// These settings with every value the chrome cannot use brought back into range: lengths
    /// and sizes no smaller than zero, a positive panel width, and companion ids that are
    /// non-empty and unique (`NookConfiguration.addCompanion` traps on a duplicate). Applied to
    /// settings that did not come from the playground's own controls, such as an imported
    /// preset.
    public func normalized() -> PlaygroundSettings {
        var settings = self
        settings.panel.expandedWidth = min(max(panel.expandedWidth, 100), 2000)
        settings.panel.topCornerRadius = max(panel.topCornerRadius, 0)
        settings.panel.bottomCornerRadius = max(panel.bottomCornerRadius, 0)
        settings.panel.insetTop = max(panel.insetTop, 0)
        settings.panel.insetBottom = max(panel.insetBottom, 0)
        settings.panel.insetLeading = max(panel.insetLeading, 0)
        settings.panel.insetTrailing = max(panel.insetTrailing, 0)

        settings.metrics.edgePadding = max(metrics.edgePadding, 0)
        settings.metrics.expandedColumnSpacing = max(metrics.expandedColumnSpacing, 0)
        settings.metrics.topBarHeight = max(metrics.topBarHeight, 0)
        settings.metrics.headerIconSize = max(metrics.headerIconSize, 0)
        settings.metrics.headerIconCornerRadius = max(metrics.headerIconCornerRadius, 0)
        settings.metrics.compactSlotSize = max(metrics.compactSlotSize, 0)
        settings.metrics.bannerCornerRadius = max(metrics.bannerCornerRadius, 0)

        for keyPath in [\Typography.headerIcon, \.topBarLabel, \.bannerMessage, \.compactLeadingGlyph] {
            settings.typography[keyPath: keyPath].size = min(max(typography[keyPath: keyPath].size, 1), 200)
        }
        for keyPath in [\Motion.viewModeChange, \.statusBanner] {
            let spring = motion[keyPath: keyPath]
            settings.motion[keyPath: keyPath] = SpringSpec(
                response: max(spring.response, 0.01),
                dampingFraction: min(max(spring.dampingFraction, 0.01), 2)
            )
        }

        let icon = topBar.leadingIcon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        settings.topBar.leadingIcon = icon.isEmpty ? nil : icon

        settings.rimGlow.lineWidth = max(rimGlow.lineWidth, 0)
        settings.rimGlow.glowRadius = max(rimGlow.glowRadius, 0)
        settings.rimGlow.intensity = min(max(rimGlow.intensity, 0), 1)
        settings.scrollEdgeFade.length = max(scrollEdgeFade.length, 0)

        var usedIDs = Set<String>()
        for index in settings.companions.indices {
            var companion = settings.companions[index]
            companion.id = Self.uniqueID(for: companion, avoiding: usedIDs)
            usedIDs.insert(companion.id)
            companion.spacing = max(companion.spacing, 0)
            companion.cornerRadius = max(companion.cornerRadius, 0)
            let label = companion.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            companion.accessibilityLabel = label.isEmpty ? nil : label
            settings.companions[index] = companion
        }
        return settings
    }

    /// `companion`'s id, trimmed, or a fresh one when it is empty or already taken: the kind's
    /// suggested id, then that id with `-2`, `-3`, and so on.
    public static func uniqueID(for companion: Companion, avoiding usedIDs: Set<String>) -> String {
        let trimmed = companion.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? companion.kind.suggestedID : trimmed
        guard usedIDs.contains(base) else { return base }
        var suffix = 2
        while usedIDs.contains("\(base)-\(suffix)") { suffix += 1 }
        return "\(base)-\(suffix)"
    }
}

// MARK: - Decoding

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when the key is absent. A value of the wrong type
    /// still throws, so a malformed preset is reported rather than silently reset.
    fileprivate func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

extension PlaygroundSettings: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        theme = try container.value(.theme, or: fallback.theme)
        panel = try container.value(.panel, or: fallback.panel)
        metrics = try container.value(.metrics, or: fallback.metrics)
        typography = try container.value(.typography, or: fallback.typography)
        motion = try container.value(.motion, or: fallback.motion)
        labels = try container.value(.labels, or: fallback.labels)
        topBar = try container.value(.topBar, or: fallback.topBar)
        companions = try container.value(.companions, or: fallback.companions)
        rimGlow = try container.value(.rimGlow, or: fallback.rimGlow)
        scrollEdgeFade = try container.value(.scrollEdgeFade, or: fallback.scrollEdgeFade)
        behavior = try container.value(.behavior, or: fallback.behavior)
    }
}

extension PlaygroundSettings.Theme: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accent = try container.decodeIfPresent(PlaygroundColor.self, forKey: .accent)
        fontDesign = try container.value(.fontDesign, or: .default)
        primaryLabel = try container.decodeIfPresent(PlaygroundColor.self, forKey: .primaryLabel)
        secondaryLabel = try container.decodeIfPresent(PlaygroundColor.self, forKey: .secondaryLabel)
        tertiaryLabel = try container.decodeIfPresent(PlaygroundColor.self, forKey: .tertiaryLabel)
        quaternaryLabel = try container.decodeIfPresent(PlaygroundColor.self, forKey: .quaternaryLabel)
        subtleFill = try container.decodeIfPresent(PlaygroundColor.self, forKey: .subtleFill)
        subtleStroke = try container.decodeIfPresent(PlaygroundColor.self, forKey: .subtleStroke)
        headerInactiveIcon = try container.decodeIfPresent(PlaygroundColor.self, forKey: .headerInactiveIcon)
    }
}

extension PlaygroundSettings.Panel: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        expandedWidth = try container.value(.expandedWidth, or: fallback.expandedWidth)
        topCornerRadius = try container.value(.topCornerRadius, or: fallback.topCornerRadius)
        bottomCornerRadius = try container.value(.bottomCornerRadius, or: fallback.bottomCornerRadius)
        insetTop = try container.value(.insetTop, or: fallback.insetTop)
        insetBottom = try container.value(.insetBottom, or: fallback.insetBottom)
        insetLeading = try container.value(.insetLeading, or: fallback.insetLeading)
        insetTrailing = try container.value(.insetTrailing, or: fallback.insetTrailing)
    }
}

extension PlaygroundSettings.Metrics: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        edgePadding = try container.value(.edgePadding, or: fallback.edgePadding)
        expandedColumnSpacing = try container.value(.expandedColumnSpacing, or: fallback.expandedColumnSpacing)
        topBarHeight = try container.value(.topBarHeight, or: fallback.topBarHeight)
        headerIconSize = try container.value(.headerIconSize, or: fallback.headerIconSize)
        headerIconCornerRadius = try container.value(.headerIconCornerRadius, or: fallback.headerIconCornerRadius)
        compactSlotSize = try container.value(.compactSlotSize, or: fallback.compactSlotSize)
        bannerCornerRadius = try container.value(.bannerCornerRadius, or: fallback.bannerCornerRadius)
    }
}

extension PlaygroundSettings.Typography: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        headerIcon = try container.value(.headerIcon, or: fallback.headerIcon)
        topBarLabel = try container.value(.topBarLabel, or: fallback.topBarLabel)
        bannerMessage = try container.value(.bannerMessage, or: fallback.bannerMessage)
        compactLeadingGlyph = try container.value(.compactLeadingGlyph, or: fallback.compactLeadingGlyph)
    }
}

extension PlaygroundSettings.Motion: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        viewModeChange = try container.value(.viewModeChange, or: fallback.viewModeChange)
        statusBanner = try container.value(.statusBanner, or: fallback.statusBanner)
    }
}

extension PlaygroundSettings.Labels: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        settingsBreadcrumb = try container.value(.settingsBreadcrumb, or: fallback.settingsBreadcrumb)
        keepOpenHelp = try container.value(.keepOpenHelp, or: fallback.keepOpenHelp)
        settingsHelp = try container.value(.settingsHelp, or: fallback.settingsHelp)
        dismissHelp = try container.value(.dismissHelp, or: fallback.dismissHelp)
    }
}

extension PlaygroundSettings.TopBar: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        showsTopBar = try container.value(.showsTopBar, or: fallback.showsTopBar)
        showsSettings = try container.value(.showsSettings, or: fallback.showsSettings)
        showsKeepOpenButton = try container.value(.showsKeepOpenButton, or: fallback.showsKeepOpenButton)
        showsSettingsButton = try container.value(.showsSettingsButton, or: fallback.showsSettingsButton)
        showsStatusBanner = try container.value(.showsStatusBanner, or: fallback.showsStatusBanner)
        width = try container.value(.width, or: fallback.width)
        leadingTitle = try container.value(.leadingTitle, or: fallback.leadingTitle)
        leadingIcon = try container.decodeIfPresent(String.self, forKey: .leadingIcon)
    }
}

extension PlaygroundSettings.Companion: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.value(.id, or: "")
        let kind = try container.value(.kind, or: Kind.actions)
        let label = try container.decodeIfPresent(String.self, forKey: .accessibilityLabel)
        self.init(id: id, kind: kind, accessibilityLabel: label)
        anchor = try container.value(.anchor, or: anchor)
        alignment = try container.value(.alignment, or: alignment)
        spacing = try container.value(.spacing, or: spacing)
        visibility = try container.value(.visibility, or: visibility)
        outline = try container.value(.outline, or: outline)
        cornerRadius = try container.value(.cornerRadius, or: cornerRadius)
        backdrop = try container.value(.backdrop, or: backdrop)
        backdropColor = try container.value(.backdropColor, or: backdropColor)
        hidesInSettings = try container.value(.hidesInSettings, or: hidesInSettings)
    }
}

extension PlaygroundSettings.RimGlow: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        lineWidth = try container.value(.lineWidth, or: fallback.lineWidth)
        glowRadius = try container.value(.glowRadius, or: fallback.glowRadius)
        intensity = try container.value(.intensity, or: fallback.intensity)
        pulses = try container.value(.pulses, or: fallback.pulses)
        followsAmbientColor = try container.value(.followsAmbientColor, or: fallback.followsAmbientColor)
    }
}

extension PlaygroundSettings.ScrollEdgeFade: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        isEnabled = try container.value(.isEnabled, or: fallback.isEnabled)
        top = try container.value(.top, or: fallback.top)
        bottom = try container.value(.bottom, or: fallback.bottom)
        leading = try container.value(.leading, or: fallback.leading)
        trailing = try container.value(.trailing, or: fallback.trailing)
        length = try container.value(.length, or: fallback.length)
    }
}

extension PlaygroundSettings.Behavior: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        hoverKeepsVisible = try container.value(.hoverKeepsVisible, or: fallback.hoverKeepsVisible)
        hoverHaptics = try container.value(.hoverHaptics, or: fallback.hoverHaptics)
    }
}
