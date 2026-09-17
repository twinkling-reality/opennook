// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import NookSurface
import SwiftUI

/// Top-level Settings surface, rendered when the expanded nook is in `.settings` mode.
/// Composes the per-section groups (Appearance, Display, Shortcut & nook, Data, About)
/// into one scrolling stack. Each group's body is a public section a host's own Settings
/// screen can reuse (``NookAppearanceSettingsSection``, ``NookDisplaySettingsSection``,
/// ``NookShortcutSettingsSection``, ``NookResetSettingsSection``, ``NookAboutSettingsSection``),
/// each wrapped in a ``NookSettingsGroup``.
///
/// Layout is deliberately flat: section label, then content, on one shared left margin
/// (aligned with the top bar via `\.nookContentInsets`), separated by whitespace only,
/// no card fills, no rules.
struct SettingsView: View {
    @ObservedObject var appState: AppState
    /// Host-supplied sections rendered below the framework groups and above About.
    let hostSections: [NookSettingsSection]
    /// The framework groups to show. See ``NookConfiguration/settingsGroups``.
    var groups: NookSettingsGroups = .all

    @Environment(\.nookChromeMetrics) private var metrics

    /// Which sections are expanded. In-memory for the session; Appearance opens by default
    /// so the surface isn't a wall of collapsed headers on first entry.
    @State private var expandedSections: Set<String> = ["Appearance"]

    /// Caps Settings height from the main display so rows scroll instead of clipping below the notch panel.
    private var settingsScrollMaxHeight: CGFloat {
        guard let screen = NSScreen.main else {
            return 340
        }

        let visibleHeight = screen.visibleFrame.height
        return min(440, max(260, visibleHeight * 0.36))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: metrics.settingsSectionSpacing) {
                if groups.contains(.appearance) {
                    section("Appearance") {
                        NookAppearanceSettingsSection(appState: appState)
                    }
                }

                if groups.contains(.display) {
                    section("Display") {
                        NookDisplaySettingsSection(appState: appState)
                    }
                }

                if groups.contains(.shortcut) {
                    section("Shortcut & nook") {
                        NookShortcutSettingsSection(appState: appState)
                    }
                }

                if groups.contains(.data) {
                    section("Data") {
                        VStack(alignment: .leading, spacing: metrics.settingsGroupSpacing) {
                            SettingsDataCommandRow(
                                title: "Preview status banner",
                                subtitle: "Shows the transient message channel under the top bar",
                                icon: "text.bubble",
                                style: .standard,
                                action: {
                                    appState.errorMessage = "Something went wrong — try again."
                                    appState.showHome()
                                }
                            )
                            NookResetSettingsSection()
                        }
                    }
                }

                ForEach(hostSections) { hostSection in
                    section(hostSection.title) {
                        hostSection.content()
                    }
                }

                if groups.contains(.about) {
                    section("About") {
                        NookAboutSettingsSection()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, metrics.settingsContentBottomPadding)
        }
        // Follows the host's panel-wide opt-in (`NookConfiguration.scrollEdgeFade`); a
        // no-op while it is off.
        .nookScrollEdgeFade(axes: .vertical)
        .frame(maxWidth: .infinity, maxHeight: settingsScrollMaxHeight, alignment: .leading)
    }

    /// A collapsible section bound to ``expandedSections``.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NookSettingsGroup(
            title,
            isExpanded: Binding(
                get: { expandedSections.contains(title) },
                set: { open in
                    if open { expandedSections.insert(title) } else { expandedSections.remove(title) }
                }
            ),
            content: content
        )
    }
}

/// The framework groups of the built-in Settings screen, for showing some and hiding others
/// with ``NookConfiguration/settingsGroups``.
public struct NookSettingsGroups: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Theme, surface, layout, accent, and strength. See ``NookAppearanceSettingsSection``.
    public static let appearance = NookSettingsGroups(rawValue: 1 << 0)
    /// Which display the nook is on. See ``NookDisplaySettingsSection``.
    public static let display = NookSettingsGroups(rawValue: 1 << 1)
    /// The global shortcut, "Stay expanded", and haptic feedback. See ``NookShortcutSettingsSection``.
    public static let shortcut = NookSettingsGroups(rawValue: 1 << 2)
    /// The status banner preview and "Reset All Settings". See ``NookResetSettingsSection``.
    public static let data = NookSettingsGroups(rawValue: 1 << 3)
    /// The host's name, version, and tagline. See ``NookAboutSettingsSection``.
    public static let about = NookSettingsGroups(rawValue: 1 << 4)

    /// Every framework group - the built-in screen as it ships.
    public static let all: NookSettingsGroups = [.appearance, .display, .shortcut, .data, .about]
}

/// A collapsible Settings group - a disclosure header with the title, and the content indented
/// under a connector hairline - drawn the way the built-in Settings screen draws its own, for a
/// host that builds its own Settings screen from the framework's sections and its own.
///
/// ```swift
/// struct MySettings: View {
///     @EnvironmentObject private var appState: AppState
///
///     var body: some View {
///         ScrollView {
///             VStack(alignment: .leading, spacing: 16) {
///                 NookSettingsGroup("Account") { AccountRows() }
///                 NookSettingsGroup("Appearance") { NookAppearanceSettingsSection(appState: appState) }
///                 NookSettingsGroup("Display", isInitiallyExpanded: false) {
///                     NookDisplaySettingsSection(appState: appState)
///                 }
///                 NookSettingsGroup("Shortcut & nook", isInitiallyExpanded: false) {
///                     NookShortcutSettingsSection(appState: appState)
///                 }
///                 NookSettingsGroup("Data", isInitiallyExpanded: false) { NookResetSettingsSection() }
///             }
///         }
///     }
/// }
/// ```
public struct NookSettingsGroup<Content: View>: View {
    let title: String
    let binding: Binding<Bool>?
    let content: () -> Content

    @State private var isExpandedState: Bool

    /// A group that keeps its own open or closed state, starting open unless
    /// `isInitiallyExpanded` is `false`.
    public init(
        _ title: String,
        isInitiallyExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.binding = nil
        self.content = content
        _isExpandedState = State(initialValue: isInitiallyExpanded)
    }

    /// A group whose open or closed state lives in `isExpanded`.
    public init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.binding = isExpanded
        self.content = content
        _isExpandedState = State(initialValue: isExpanded.wrappedValue)
    }

    public var body: some View {
        SettingsDisclosureSection(
            title: title,
            isExpanded: binding ?? $isExpandedState,
            content: content
        )
    }
}

/// A settings section with a tap-to-toggle disclosure header and a left connector hairline
/// tying the indented content back to the header.
private struct SettingsDisclosureSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.nookResolvedTheme) private var theme
    @Environment(\.nookChromeTypography) private var typography
    @Environment(\.nookChromeMetrics) private var metrics

    var body: some View {
        let iconGutter = metrics.settingsDisclosureGutter
        VStack(alignment: .leading, spacing: metrics.settingsBlockSpacing) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: metrics.settingsInlineSpacing) {
                    Image(systemName: "chevron.right")
                        .font(typography.settingsDisclosureChevron)
                        .foregroundStyle(theme.quaternaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: iconGutter)
                    SettingsSectionLabel(title)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(alignment: .top, spacing: metrics.settingsGroupSpacing) {
                    // Connector: a thin vertical rule that fills the content height, tying the
                    // indented items back to the header. Centered under the chevron gutter.
                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .fill(theme.subtleStroke.opacity(metrics.settingsConnectorOpacity))
                        .frame(width: metrics.settingsConnectorWidth)

                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, (iconGutter - metrics.settingsConnectorWidth) / 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
