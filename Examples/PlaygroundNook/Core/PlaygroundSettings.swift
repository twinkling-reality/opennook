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
    public var companionDefaults = CompanionDefaults()
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

        /// One settable font. The raw value is the property name, which is also the key it
        /// encodes to and the name the assistant's field guide uses.
        public enum Role: String, CaseIterable, Sendable {
            case headerIcon
            case topBarLabel
            case bannerMessage
            case compactLeadingGlyph
        }

        public subscript(role: Role) -> FontSpec {
            get {
                switch role {
                    case .headerIcon: headerIcon
                    case .topBarLabel: topBarLabel
                    case .bannerMessage: bannerMessage
                    case .compactLeadingGlyph: compactLeadingGlyph
                }
            }
            set {
                switch role {
                    case .headerIcon: headerIcon = newValue
                    case .topBarLabel: topBarLabel = newValue
                    case .bannerMessage: bannerMessage = newValue
                    case .compactLeadingGlyph: compactLeadingGlyph = newValue
                }
            }
        }

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

        /// One settable spring, named as it encodes.
        public enum Role: String, CaseIterable, Sendable {
            case viewModeChange
            case statusBanner
        }

        public subscript(role: Role) -> SpringSpec {
            get {
                switch role {
                    case .viewModeChange: viewModeChange
                    case .statusBanner: statusBanner
                }
            }
            set {
                switch role {
                    case .viewModeChange: viewModeChange = newValue
                    case .statusBanner: statusBanner = newValue
                }
            }
        }

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

    /// `NookTopBarConfiguration`, minus the trailing items, which are host content, plus where
    /// the home view puts its header.
    public struct TopBar: Equatable, Sendable {
        public enum Width: String, Codable, CaseIterable, Sendable {
            case contentColumn
            case intrinsic
        }

        public enum NotchClearance: String, Codable, CaseIterable, Sendable {
            case automatic
            case manual
        }

        public var showsTopBar = TopBar.base.showsTopBar
        public var showsSettings = TopBar.base.showsSettings
        public var showsKeepOpenButton = TopBar.base.showsKeepOpenButton
        public var showsSettingsButton = TopBar.base.showsSettingsButton
        public var showsStatusBanner = TopBar.base.showsStatusBanner
        public var width: Width = .contentColumn
        public var notchClearance: NotchClearance = .automatic
        /// Whether the home view's header goes beside the notch, with
        /// `nookNotchAccessories(leading:trailing:)`, rather than in the content.
        public var notchAccessories = false
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
            topBar.notchClearance =
                switch notchClearance {
                    case .automatic: .automatic
                    case .manual: .manual
                }
            if leadingTitle != TopBar().leadingTitle {
                let title = leadingTitle
                topBar.leadingTitle = { _ in title }
            }
            topBar.leadingIcon = leadingIcon
        }
    }

    /// Puts the lock and gear back in the top bar when the companions stop holding one that
    /// `previous` held, so editing or removing the companion that carried them never loses them.
    /// A control the companions never held is left as it is.
    public mutating func restoreChromeControls(heldBy previous: [Companion]) {
        func held(_ type: Item.Kind, in companions: [Companion]) -> Bool {
            companions.contains { $0.holds(type) }
        }
        if held(.keepOpen, in: previous), !held(.keepOpen, in: companions) {
            topBar.showsKeepOpenButton = true
        }
        if held(.settings, in: previous), !held(.settings, in: companions) {
            topBar.showsSettingsButton = true
        }
    }

    /// One companion surface: its content as a list of ``Item``s, and everything else a
    /// parameter of `NookConfiguration.addCompanion`, with the same defaults.
    ///
    /// A group of controls is one companion with several items; a control that stands apart is a
    /// companion of its own. The style values - ``size``, ``presence``, ``fade``, ``stroke``,
    /// ``shadow``, and ``hover`` - are `nil` until set, and `nil` takes the value from
    /// ``PlaygroundSettings/companionDefaults``.
    public struct Companion: Identifiable, Equatable, Sendable {
        /// A starting point for a new companion. Also what an older preset's `kind` names, so a
        /// preset written before items existed opens with the same content.
        public enum Template: String, Codable, CaseIterable, Sendable {
            /// A pill of three buttons.
            case actions
            /// A single round button.
            case button
            /// The framework's keep-open and Settings buttons.
            case controls
            /// A short status label.
            case chip
            /// Nothing yet.
            case empty

            /// The items a companion made from this template starts with.
            public var items: [Item] {
                switch self {
                    case .actions:
                        [
                            Item(symbol: "backward.fill", title: "Previous"),
                            Item(symbol: "play.fill", title: "Play"),
                            Item(symbol: "forward.fill", title: "Next"),
                        ]
                    case .button:
                        [Item(symbol: "lightbulb", title: "Rim glow", action: .rimGlow)]
                    case .controls:
                        [Item(type: .keepOpen), Item(type: .settings)]
                    case .chip:
                        [Item(type: .label, symbol: "sparkles", title: "3 new")]
                    case .empty:
                        []
                }
            }
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

        /// How the items are arranged.
        public enum Layout: String, Codable, CaseIterable, Sendable {
            /// A row below the chrome, a column beside it.
            case automatic
            case row
            case column
        }

        /// `NookCompanionSize`.
        public enum Size: String, Codable, CaseIterable, Sendable {
            case small
            case regular
            case large

            public var nookSize: NookCompanionSize {
                switch self {
                    case .small: .small
                    case .regular: .regular
                    case .large: .large
                }
            }
        }

        /// `NookCompanionPresence`.
        public enum Presence: String, Codable, CaseIterable, Sendable {
            case fold
            case fade
            case slide
            case pop

            public var nookPresence: NookCompanionPresence {
                switch self {
                    case .fold: .fold
                    case .fade: .fade
                    case .slide: .slide
                    case .pop: .pop
                }
            }
        }

        /// `NookStandardCompanionStyle.Hover`.
        public enum Hover: String, Codable, CaseIterable, Sendable {
            case none
            case highlight
            case lift
            case glow

            public var nookHover: NookStandardCompanionStyle.Hover {
                switch self {
                    case .none: .none
                    case .highlight: .highlight
                    case .lift: .lift
                    case .glow: .glow
                }
            }
        }

        /// Most items a companion keeps; more than this is trimmed when settings are normalized.
        public static let maximumItems = 12

        public var id: String
        /// What the companion holds, in order.
        public var items: [Item]
        public var layout: Layout = .automatic
        public var anchor: Anchor = .below
        public var alignment: AnchorAlignment = .center
        /// The gap to the chrome, and to the companion before it unless ``gap`` is set.
        public var spacing = Double(NookCompanionSurface.defaultSpacing)
        /// The gap to the companion before it in a row below the chrome. `nil` uses ``spacing``.
        public var gap: Double?
        /// Where it sits across its row beside a taller companion. `nil` uses the framework's.
        public var rowAlignment: AnchorAlignment?
        public var visibility: Visibility = .expanded
        public var outline: Outline = .capsule
        /// Used by the `roundedRectangle` outline.
        public var cornerRadius: Double = 12
        public var backdrop: Backdrop = .inherit
        /// Used by the `solid` and `glass` backdrops.
        public var backdropColor = PlaygroundColor(red: 0.25, green: 0.55, blue: 0.98)
        public var size: Size?
        public var presence: Presence?
        /// The fill's strength at the far side from the chrome, from 0 to 1. 1 is no fade.
        public var fade: Double?
        /// Whether the surface has a hairline edge.
        public var stroke: Bool?
        /// Whether the surface has a soft shadow.
        public var shadow: Bool?
        public var hover: Hover?
        /// The companion's own accent, for its labels and tinted controls. `nil` uses the theme's.
        public var accent: PlaygroundColor?
        public var hidesInSettings = true
        public var accessibilityLabel: String?

        public init(id: String, items: [Item] = [], accessibilityLabel: String? = nil) {
            self.id = id
            self.items = items
            self.accessibilityLabel = accessibilityLabel
        }

        /// A companion made from `template`: its items, and the placement it suits.
        public init(id: String, template: Template, accessibilityLabel: String? = nil) {
            self.init(id: id, items: template.items, accessibilityLabel: accessibilityLabel)
            switch template {
                case .button:
                    outline = .circle
                case .controls:
                    anchor = .trailing
                    hidesInSettings = false
                case .actions, .chip, .empty:
                    break
            }
        }

        public var nookAnchor: NookCompanionAnchor {
            switch anchor {
                case .below: .below(alignment: alignment.nookAlignment)
                case .leading: .leading(alignment: alignment.nookAlignment)
                case .trailing: .trailing(alignment: alignment.nookAlignment)
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

        /// Whether every item is a button the size of a surface. Each of those draws its own
        /// surface, so the companion draws none: it takes the plain style, and its own shape,
        /// backdrop, and style values have nothing to paint.
        public var itemsAreSurfaces: Bool {
            !items.isEmpty && items.allSatisfy { $0.type == .button && $0.size == .surface }
        }

        /// Whether the companion's style differs from the defaults: a style value set here, or
        /// items that are surfaces of their own.
        public var overridesStyle: Bool {
            itemsAreSurfaces || fade != nil || stroke != nil || shadow != nil || hover != nil
        }

        /// The standard style with this companion's values over `defaults`, or the plain style when
        /// its items are surfaces of their own.
        public func style(over defaults: CompanionDefaults) -> NookStandardCompanionStyle {
            guard !itemsAreSurfaces else { return .plain }
            return CompanionDefaults.style(
                fade: fade ?? defaults.fade,
                stroke: stroke ?? defaults.stroke,
                shadow: shadow ?? defaults.shadow,
                hover: hover ?? defaults.hover
            )
        }

        /// How the items are arranged once ``Layout/automatic`` is decided.
        public var resolvedLayout: Layout {
            switch layout {
                case .automatic: anchor == .below ? .row : .column
                case .row, .column: layout
            }
        }

        /// Whether it holds the framework's lock or gear.
        public var holdsChromeControls: Bool {
            holds(.keepOpen) || holds(.settings)
        }

        /// Whether one of its items is of `type`.
        public func holds(_ type: Item.Kind) -> Bool {
            items.contains { $0.type == type }
        }

        /// The id a companion holding these items starts with.
        public var suggestedID: String {
            if holdsChromeControls { return "controls" }
            switch (items.count, items.first?.type) {
                case (0, _): return "companion"
                case (1, .label?): return "status"
                case (1, _): return "button"
                default: return items.allSatisfy { $0.type == .label } ? "labels" : "actions"
            }
        }

        /// The items in a few words, for a list row: `3 buttons`, `a label`, `lock and gear`.
        public var contentSummary: String {
            Item.summary(of: items)
        }
    }

    /// One thing a companion holds: a glyph button, a label, or one of the framework's own
    /// controls.
    public struct Item: Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            /// A glyph button that runs its ``action``.
            case button
            /// An icon and text.
            case label
            /// The framework's keep-open lock.
            case keepOpen
            /// The framework's Settings gear.
            case settings
        }

        /// What a button does in the playground. A host puts its own action in the exported
        /// Swift.
        public enum Action: String, Codable, CaseIterable, Sendable {
            case none
            /// Posts a status banner naming the button.
            case status
            /// Lights or dims the rim glow.
            case rimGlow
            /// Toggles keep-open, like the lock.
            case keepOpen
            /// Opens or closes Settings, like the gear.
            case settings
            /// Collapses the nook.
            case collapse
        }

        /// `NookGlyphButtonStyle.Fill`.
        public enum Fill: String, Codable, CaseIterable, Sendable {
            case none
            case subtle
            /// ``Item/fillColor``, or the accent when it is not set.
            case color
            /// The chrome's own material.
            case chrome
        }

        /// `NookGlyphButtonStyle.Size`.
        public enum Size: String, Codable, CaseIterable, Sendable {
            /// A control inside the surface.
            case control
            /// As tall as the surface, for a button that is a surface of its own.
            case surface
        }

        public var type: Kind
        /// An SF Symbol name. `nil` uses the type's own.
        public var symbol: String?
        /// A button's name, read by VoiceOver and shown as its tooltip, or a label's text.
        public var title: String?
        /// The glyph's color. `nil` uses the palette.
        public var tint: PlaygroundColor?
        public var fill: Fill = .none
        public var fillColor: PlaygroundColor?
        /// The fill's strength at the button's bottom, from 0 to 1. `nil` is no fade.
        public var fade: Double?
        public var size: Size = .control
        public var action: Action = .status

        public init(
            type: Kind = .button,
            symbol: String? = nil,
            title: String? = nil,
            action: Action = .status
        ) {
            self.type = type
            self.symbol = symbol
            self.title = title
            self.action = action
        }

        /// The symbol the item shows.
        public var displaySymbol: String? {
            if let symbol { return symbol }
            switch type {
                case .button: return action.defaultSymbol
                case .label: return nil
                case .keepOpen: return "lock.open"
                case .settings: return "gearshape"
            }
        }

        /// The item's name for lists and VoiceOver.
        public var displayTitle: String {
            if let title { return title }
            switch type {
                case .button: return action.defaultTitle
                case .label: return "Label"
                case .keepOpen: return "Keep open"
                case .settings: return "Settings"
            }
        }

        /// `items` in a few words: `3 buttons`, `a label`, `lock and gear`, `nothing`.
        public static func summary(of items: [Item]) -> String {
            guard !items.isEmpty else { return "nothing" }
            let types = items.map(\.type)
            if types == [.keepOpen, .settings] || types == [.settings, .keepOpen] { return "lock and gear" }
            let buttons = types.filter { $0 == .button }.count
            let labels = types.filter { $0 == .label }.count
            let chrome = items.count - buttons - labels
            var parts: [String] = []
            if buttons > 0 { parts.append(buttons == 1 ? "a button" : "\(buttons) buttons") }
            if labels > 0 { parts.append(labels == 1 ? "a label" : "\(labels) labels") }
            if chrome > 0 { parts.append(chrome == 1 ? "a chrome control" : "\(chrome) chrome controls") }
            return parts.joined(separator: " and ")
        }

        /// `items` by name: `Previous, Play, Next`.
        public static func titles(of items: [Item]) -> String {
            items.isEmpty ? "nothing" : items.map(\.displayTitle).joined(separator: ", ")
        }
    }

    /// `NookConfiguration.companionSize`, `companionPresence`, and `companionStyle`: how every
    /// companion looks unless it says otherwise.
    public struct CompanionDefaults: Equatable, Sendable {
        public var size: Companion.Size = .regular
        public var presence: Companion.Presence = .fold
        /// The fill's strength at a companion's far side from the chrome, from 0 to 1. 1 is no
        /// fade.
        public var fade: Double = 1
        public var stroke = false
        public var shadow = false
        public var hover: Companion.Hover = .none

        public init() {}

        /// The standard style these values describe.
        public var style: NookStandardCompanionStyle {
            Self.style(fade: fade, stroke: stroke, shadow: shadow, hover: hover)
        }

        static func style(
            fade: Double,
            stroke: Bool,
            shadow: Bool,
            hover: Companion.Hover
        ) -> NookStandardCompanionStyle {
            NookStandardCompanionStyle(
                fade: fade < 1 ? NookStandardCompanionStyle.Fade(start: 1, end: fade) : nil,
                stroke: stroke ? .hairline : nil,
                shadow: shadow ? .soft : nil,
                hover: hover.nookHover
            )
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

extension PlaygroundSettings.Companion.AnchorAlignment {
    public var nookAlignment: NookCompanionAnchor.Alignment {
        switch self {
            case .start: .start
            case .center: .center
            case .end: .end
        }
    }
}

extension PlaygroundSettings.Companion.Template {
    public var title: String {
        switch self {
            case .actions: "Action pill"
            case .button: "Round button"
            case .controls: "Nook controls"
            case .chip: "Status chip"
            case .empty: "Empty"
        }
    }

    public var suggestedAccessibilityLabel: String? {
        switch self {
            case .actions: "Actions"
            case .button: "Rim glow"
            case .controls: "Nook controls"
            case .chip: "Status"
            case .empty: nil
        }
    }
}

extension PlaygroundSettings.Item.Action {
    /// The glyph a button with this action shows when it names none.
    public var defaultSymbol: String {
        switch self {
            case .none: "circle"
            case .status: "bell"
            case .rimGlow: "lightbulb"
            case .keepOpen: "lock.open"
            case .settings: "gearshape"
            case .collapse: "chevron.up"
        }
    }

    /// The name a button with this action has when it names none.
    public var defaultTitle: String {
        switch self {
            case .none: "Button"
            case .status: "Notify"
            case .rimGlow: "Rim glow"
            case .keepOpen: "Keep open"
            case .settings: "Settings"
            case .collapse: "Collapse"
        }
    }
}

// MARK: - Normalizing

extension PlaygroundSettings {
    /// These settings with every value the chrome cannot use brought back into range: lengths
    /// and sizes no smaller than zero, a positive panel width, fades between 0 and 1, companion
    /// ids that are non-empty and unique (`NookConfiguration.addCompanion` traps on a duplicate),
    /// and no more than ``Companion/maximumItems`` items a companion, with blank names cleared.
    /// Applied to settings that did not come from the playground's own controls, such as an
    /// imported preset.
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

        for role in Typography.Role.allCases {
            settings.typography[role].size = min(max(typography[role].size, 1), 200)
        }
        for role in Motion.Role.allCases {
            let spring = motion[role]
            settings.motion[role] = SpringSpec(
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

        settings.companionDefaults.fade = Self.unit(companionDefaults.fade)

        var usedIDs = Set<String>()
        for index in settings.companions.indices {
            var companion = settings.companions[index]
            companion.id = Self.uniqueID(for: companion, avoiding: usedIDs)
            usedIDs.insert(companion.id)
            companion.spacing = max(companion.spacing, 0)
            companion.gap = companion.gap.map { max($0, 0) }
            companion.cornerRadius = max(companion.cornerRadius, 0)
            companion.fade = companion.fade.map(Self.unit)
            companion.accessibilityLabel = Self.trimmed(companion.accessibilityLabel)
            companion.items = companion.items.prefix(Companion.maximumItems).map { item in
                var item = item
                item.symbol = Self.trimmed(item.symbol)
                item.title = Self.trimmed(item.title)
                item.fade = item.fade.map(Self.unit)
                return item
            }
            settings.companions[index] = companion
        }
        return settings
    }

    /// `text` without surrounding white space, or `nil` when nothing is left.
    private static func trimmed(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `value` clamped to 0...1, with anything not a number read as 1.
    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 1
    }

    /// `companion`'s id, trimmed, or a fresh one when it is empty or already taken: the id its
    /// items suggest, then that id with `-2`, `-3`, and so on.
    public static func uniqueID(for companion: Companion, avoiding usedIDs: Set<String>) -> String {
        let trimmed = companion.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? companion.suggestedID : trimmed
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
        companionDefaults = try container.value(.companionDefaults, or: fallback.companionDefaults)
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
        notchClearance = try container.value(.notchClearance, or: fallback.notchClearance)
        notchAccessories = try container.value(.notchAccessories, or: fallback.notchAccessories)
        leadingTitle = try container.value(.leadingTitle, or: fallback.leadingTitle)
        leadingIcon = try container.decodeIfPresent(String.self, forKey: .leadingIcon)
    }
}

extension PlaygroundSettings.Companion: Codable {
    /// A preset written before companions held items named its content with `kind`.
    private enum LegacyKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.value(.id, or: "")
        let label = try container.decodeIfPresent(String.self, forKey: .accessibilityLabel)
        var items = try container.decodeIfPresent([PlaygroundSettings.Item].self, forKey: .items)
        if items == nil {
            // No items: the content is the template the preset names, or the action pill that
            // an unnamed companion always was.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            items = try legacy.value(.kind, or: Template.actions).items
        }
        self.init(id: id, items: items ?? [], accessibilityLabel: label)
        layout = try container.value(.layout, or: layout)
        anchor = try container.value(.anchor, or: anchor)
        alignment = try container.value(.alignment, or: alignment)
        spacing = try container.value(.spacing, or: spacing)
        gap = try container.decodeIfPresent(Double.self, forKey: .gap)
        rowAlignment = try container.decodeIfPresent(AnchorAlignment.self, forKey: .rowAlignment)
        visibility = try container.value(.visibility, or: visibility)
        outline = try container.value(.outline, or: outline)
        cornerRadius = try container.value(.cornerRadius, or: cornerRadius)
        backdrop = try container.value(.backdrop, or: backdrop)
        backdropColor = try container.value(.backdropColor, or: backdropColor)
        size = try container.decodeIfPresent(Size.self, forKey: .size)
        presence = try container.decodeIfPresent(Presence.self, forKey: .presence)
        fade = try container.decodeIfPresent(Double.self, forKey: .fade)
        stroke = try container.decodeIfPresent(Bool.self, forKey: .stroke)
        shadow = try container.decodeIfPresent(Bool.self, forKey: .shadow)
        hover = try container.decodeIfPresent(Hover.self, forKey: .hover)
        accent = try container.decodeIfPresent(PlaygroundColor.self, forKey: .accent)
        hidesInSettings = try container.value(.hidesInSettings, or: hidesInSettings)
    }
}

extension PlaygroundSettings.Item: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        self.init(
            type: try container.value(.type, or: fallback.type),
            symbol: try container.decodeIfPresent(String.self, forKey: .symbol),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            action: try container.value(.action, or: fallback.action)
        )
        tint = try container.decodeIfPresent(PlaygroundColor.self, forKey: .tint)
        fill = try container.value(.fill, or: fallback.fill)
        fillColor = try container.decodeIfPresent(PlaygroundColor.self, forKey: .fillColor)
        fade = try container.decodeIfPresent(Double.self, forKey: .fade)
        size = try container.value(.size, or: fallback.size)
    }
}

extension PlaygroundSettings.CompanionDefaults: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self()
        size = try container.value(.size, or: fallback.size)
        presence = try container.value(.presence, or: fallback.presence)
        fade = try container.value(.fade, or: fallback.fade)
        stroke = try container.value(.stroke, or: fallback.stroke)
        shadow = try container.value(.shadow, or: fallback.shadow)
        hover = try container.value(.hover, or: fallback.hover)
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
