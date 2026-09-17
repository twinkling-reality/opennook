// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookSurface
import SwiftUI

/// A host view floated beside the nook - an action pill under the expanded panel, a round
/// button beside it, a file basket - registered through ``NookConfiguration``.
///
/// The framework anchors it to the chrome (`NookCompanionAnchor`), shows it in the nook
/// states you choose (`NookCompanionVisibility`), draws it with a style
/// (`NookCompanionStyle`) at a size its controls share (`NookCompanionSize`), and moves it
/// with the chrome's expand and collapse, in every presentation mode and on every display. Its content renders in the same chrome environment as the home view: the
/// resolved palette (`\.nookResolvedTheme`), ``AppState`` as an environment object, the
/// module's services (`\.appServices`), and the chrome labels, metrics, motion, and
/// typography. Clicking it never takes focus away from the nook.
///
/// Register one with ``NookConfiguration/addCompanion(id:anchor:spacing:gap:rowAlignment:visibility:shape:backdrop:style:size:presence:hidesInSettings:accessibilityLabel:theme:content:)``:
///
/// ```swift
/// configuration.addCompanion(id: "actions", anchor: .below, visibility: .expanded) {
///     MyActionPill()
/// }
/// ```
///
/// Each companion is one surface: a group of controls is one companion, and a control that
/// stands apart is another. Leave ``style``, ``size``, and ``presence`` unset to use the
/// configuration's ``NookConfiguration/companionStyle``, ``NookConfiguration/companionSize``,
/// and ``NookConfiguration/companionPresence``. To change which companions exist while the
/// nook runs, put them in a ``NookCompanionSource``.
///
/// A companion belongs to the ``NookConfiguration`` that registered it, so in a multi-module
/// host it leaves the surface when its module is switched away, in the same transaction that
/// brings the incoming module's companions in.
///
/// `Sendable`: it is carried by a `Sendable` ``NookConfiguration``, and its closures are
/// `@Sendable @MainActor` like every other chrome content closure.
public struct NookCompanion: Identifiable, Sendable {
    /// Stable identity, unique within one configuration. It keys the surface's hover
    /// tracking and its accessibility identifier, `opennook.companion.<id>`.
    public let id: String

    /// Where the companion sits relative to the chrome.
    public var anchor: NookCompanionAnchor

    /// Gap, in points, between the companion and the chrome - or the companion before it in
    /// the same row, unless ``gap`` sets that. See `NookCompanionSurface/spacing`.
    public var spacing: CGFloat

    /// Gap, in points, between a `.below` companion and the companion before it in its row.
    /// `nil` uses ``spacing``, so setting it changes the gap without moving the companion
    /// further from the chrome.
    public var gap: CGFloat?

    /// Where the companion sits across its row when a neighbour is taller. `nil` centers a
    /// `.below` companion and follows the anchor's alignment in a side row.
    public var rowAlignment: NookCompanionAnchor.Alignment?

    /// The nook states the companion is shown in. Content can narrow this further at runtime
    /// with `nookCompanionVisibility(_:)`.
    public var visibility: NookCompanionVisibility

    /// The outline the companion is filled and hit-tested with.
    public var shape: NookCompanionShape

    /// What the companion paints behind its content. `NookCompanionBackdrop/inherit` (the
    /// default) follows the chrome, including the user's Liquid Glass setting.
    public var backdrop: NookCompanionBackdrop

    /// How the surface is drawn: fill, fade, edge, shadow, padding, height, and hover. `nil`
    /// (the default) uses the configuration's ``NookConfiguration/companionStyle``.
    public var style: AnyNookCompanionStyle?

    /// The size the surface shares with its controls. `nil` (the default) uses the
    /// configuration's ``NookConfiguration/companionSize``.
    public var size: NookCompanionSize?

    /// How the companion appears and disappears. `nil` (the default) uses the configuration's
    /// ``NookConfiguration/companionPresence``.
    public var presence: NookCompanionPresence?

    /// Whether the companion steps aside while the built-in Settings screen fills the
    /// expanded surface. Defaults to `true`: companions usually act on the home content,
    /// which Settings replaces. The compact state is unaffected.
    public var hidesInSettings: Bool

    /// A label for the companion as a whole, read by VoiceOver before its contents.
    public var accessibilityLabel: String?

    /// Resolves this companion's palette. `nil` (the default) uses the registering
    /// configuration's ``NookConfiguration/theme``, so the companion matches the chrome.
    public var theme: (@Sendable @MainActor (AppState) -> NookResolvedTheme)?

    /// Builds the companion's content.
    public let content: @Sendable @MainActor () -> AnyView

    public init<Content: View & Sendable>(
        id: String,
        anchor: NookCompanionAnchor = .below,
        spacing: CGFloat = NookCompanionSurface.defaultSpacing,
        gap: CGFloat? = nil,
        rowAlignment: NookCompanionAnchor.Alignment? = nil,
        visibility: NookCompanionVisibility = .expanded,
        shape: NookCompanionShape = .capsule,
        backdrop: NookCompanionBackdrop = .inherit,
        style: AnyNookCompanionStyle? = nil,
        size: NookCompanionSize? = nil,
        presence: NookCompanionPresence? = nil,
        hidesInSettings: Bool = true,
        accessibilityLabel: String? = nil,
        theme: (@Sendable @MainActor (AppState) -> NookResolvedTheme)? = nil,
        @ViewBuilder content: @escaping @Sendable @MainActor () -> Content
    ) {
        self.id = id
        self.anchor = anchor
        self.spacing = spacing
        self.gap = gap
        self.rowAlignment = rowAlignment
        self.visibility = visibility
        self.shape = shape
        self.backdrop = backdrop
        self.style = style
        self.size = size
        self.presence = presence
        self.hidesInSettings = hidesInSettings
        self.accessibilityLabel = accessibilityLabel
        self.theme = theme
        self.content = { AnyView(content()) }
    }

    /// The accessibility identifier the chrome stamps on this companion.
    public var accessibilityIdentifier: String {
        NookCompanionSurface.accessibilityIdentifier(for: id)
    }
}

/// Renders a host companion inside the chrome environment, mirroring what
/// ``NookExpandedView`` gives the home view, so companion content can use the same
/// environment values and `@EnvironmentObject` as the rest of the chrome.
///
/// The surface renders companions in their own view tree, beside the chrome rather than
/// under ``NookExpandedView``, so nothing reaches them unless it is injected here - the same
/// reason ``NookCompactHost`` exists for the compact slots.
struct NookCompanionHost: View {
    @ObservedObject var appState: AppState
    let companion: NookCompanion
    let theme: @Sendable @MainActor (AppState) -> NookResolvedTheme
    let services: AppServices
    let labels: NookChromeLabels
    let metrics: NookChromeMetrics
    let motion: NookChromeMotion
    let typography: NookChromeTypography
    let branding: NookHostBranding
    let chromeActions: NookChromeActions

    var body: some View {
        let resolved = (companion.theme ?? theme)(appState)
        companion.content()
            .environment(\.nookResolvedTheme, resolved)
            .environment(\.nookChromeLabels, labels)
            .environment(\.nookChromeMetrics, metrics)
            .environment(\.nookChromeMotion, motion)
            .environment(\.nookChromeTypography, typography)
            .environment(\.nookHostBranding, branding)
            .environment(\.nookChromeActions, chromeActions)
            .environment(\.appServices, services)
            .environmentObject(appState)
            // The panel is non-activating, so controls would otherwise paint as inactive
            // until clicked - the same override the expanded surface applies.
            .environment(\.controlActiveState, .active)
            .tint(resolved.accent)
            .fontDesign(resolved.fontDesign)
            .preferredColorScheme(appState.appearancePreferences.chromeColorSchemeOverride)
            .nookCompanionVisibility(Self.settingsRestriction(for: companion, appState: appState))
    }

    /// Only the expanded state ever shows Settings, so stepping aside means dropping the
    /// expanded state - a companion that is also shown compact stays put there, even though
    /// `viewMode` still reads `.settings` after the nook collapses.
    static func settingsRestriction(for companion: NookCompanion, appState: AppState) -> NookCompanionVisibility {
        companion.hidesInSettings && appState.isSettingsView ? .compact : .both
    }
}
