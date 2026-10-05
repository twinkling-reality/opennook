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

/// Every theme token the framework defines, grouped by the first part of its id, searchable, each
/// with what it resolves to now, whether it is overridden, and an editor for its kind.
///
/// The page is driven by `NookTokenDescriptor.all`, so a token the framework adds appears here with
/// nothing in the playground edited. Overrides are stored in `PlaygroundSettings.Theme.tokens`, so
/// they reach the live nook, the Swift export, the preset, and the theme file the way the Theme
/// page's own values do.
struct TokensPage: View {
    @ObservedObject var model: PlaygroundModel
    @ObservedObject var appState: AppState
    @State private var query = ""
    @State private var showsChangedOnly = false
    @State private var expandedGroups: Set<String> = []
    @State private var openToken: String?

    var body: some View {
        let theme = model.settings.theme.nookTheme
        let context = Self.context(for: theme, appState: appState)
        let resolver = ThemeColorResolver(theme: theme, context: context)
        let groups = visibleGroups
        PlaygroundPageView(page: .tokens) {
            SectionCard(
                title: "Find",
                help: "Every token a theme can set, by its id. A change here is a token override in the theme: "
                    + "it reaches the nook, the Swift, the preset, and the theme file."
            ) {
                ControlRow(title: "Search") {
                    TextField("Search", text: $query, prompt: Text("Token id, such as banner or radius"))
                        .labelsHidden()
                        .playgroundField()
                }
                SwitchRow(title: "Changed only", isOn: $showsChangedOnly)
            }

            if groups.isEmpty {
                Text(showsChangedOnly && query.isEmpty ? "No token is overridden yet." : "No token matches.")
                    .font(PlaygroundTheme.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            ForEach(groups) { group in
                CollapsibleCard(
                    title: group.title,
                    help: "\(group.tokens.count) \(group.tokens.count == 1 ? "token" : "tokens") under \(group.id).",
                    isExpanded: expansion(of: group),
                    isModified: group.tokens.contains { override(of: $0) != nil },
                    reset: { reset(group) }
                ) {
                    ForEach(group.tokens) { descriptor in
                        row(descriptor, theme: theme, context: context, resolver: resolver)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func row(
        _ descriptor: NookTokenDescriptor,
        theme: NookTheme,
        context: NookThemeContext,
        resolver: ThemeColorResolver
    ) -> some View {
        let resolved = theme.resolvedValue(for: descriptor.id, in: context)
        return TokenRow(
            descriptor: descriptor,
            override: override(of: descriptor),
            resolved: resolved,
            isOpen: openToken == descriptor.id,
            note: note(for: descriptor),
            resolver: resolver,
            seed: seed(for: descriptor, resolved: resolved, theme: theme),
            toggle: { toggle(descriptor) },
            set: { model.settings.theme.setTokenOverride($0, for: descriptor.id) }
        )
    }

    private func override(of descriptor: NookTokenDescriptor) -> NookTokenValue? {
        model.settings.theme.tokenOverride(descriptor.id)
    }

    /// Why a change here may not show, or where else the value is set.
    private func note(for descriptor: NookTokenDescriptor) -> String? {
        if let page = model.settings.pageOverriding(token: descriptor.id) {
            return "The \(page) page sets this too, and its value wins while it is changed there."
        }
        if let role = PlaygroundSettings.Theme.ColorRole(tokenID: descriptor.id) {
            return "The Theme page's \(role.title) color sets this token too."
        }
        return nil
    }

    /// The number a dimension editor starts from: the resolved value at the theme's scale 1.
    private func seed(for descriptor: NookTokenDescriptor, resolved: NookResolvedTokenValue?, theme: NookTheme)
        -> Double
    {
        guard case .dimension(let value)? = resolved else { return 0 }
        let multiplier: Double =
            switch descriptor.scaling {
                case .none: 1
                case .spacing, .type: theme.scale
                case .radius: theme.radius.factor
            }
        return multiplier > 0 ? value / multiplier : value
    }

    private func toggle(_ descriptor: NookTokenDescriptor) {
        withAnimation(.snappy(duration: 0.25)) {
            openToken = openToken == descriptor.id ? nil : descriptor.id
        }
    }

    private func reset(_ group: TokenGroup) {
        var theme = model.settings.theme
        for descriptor in group.tokens {
            theme.setTokenOverride(nil, for: descriptor.id)
        }
        model.settings.theme = theme
    }

    // MARK: - Groups

    /// The tokens of one id prefix, such as every `banner.` token.
    struct TokenGroup: Identifiable {
        let id: String
        let tokens: [NookTokenDescriptor]

        /// `topBar` as `Top bar`.
        var title: String { EnumTitles.title(id) }
    }

    /// Every group, in the order the framework lists its tokens.
    private static let allGroups: [TokenGroup] = {
        var order: [String] = []
        var members: [String: [NookTokenDescriptor]] = [:]
        for descriptor in NookTokenDescriptor.all {
            if members[descriptor.group] == nil { order.append(descriptor.group) }
            members[descriptor.group, default: []].append(descriptor)
        }
        return order.map { TokenGroup(id: $0, tokens: members[$0] ?? []) }
    }()

    private var visibleGroups: [TokenGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return Self.allGroups.compactMap { group in
            let tokens = group.tokens.filter { descriptor in
                (needle.isEmpty || descriptor.id.lowercased().contains(needle)
                    || group.title.lowercased().contains(needle))
                    && (!showsChangedOnly || override(of: descriptor) != nil)
            }
            return tokens.isEmpty ? nil : TokenGroup(id: group.id, tokens: tokens)
        }
    }

    /// Open while searching or showing only changes, so every match is in view; otherwise open
    /// when the person opened it.
    private func expansion(of group: TokenGroup) -> Binding<Bool> {
        Binding(
            get: { !query.isEmpty || showsChangedOnly || expandedGroups.contains(group.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroups.insert(group.id)
                } else {
                    expandedGroups.remove(group.id)
                    if !query.isEmpty || showsChangedOnly {
                        query = ""
                        showsChangedOnly = false
                    }
                }
            }
        )
    }

    /// The appearance the nook resolves its colors for now.
    static func context(for theme: NookTheme, appState: AppState) -> NookThemeContext {
        let isSystemDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return theme.context(
            preferences: appState.appearancePreferences,
            systemColorScheme: isSystemDark ? .dark : .light,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }
}

// MARK: - A token

/// One token: its id, what it resolves to, a reset when it is overridden, and its editor when open.
private struct TokenRow: View {
    let descriptor: NookTokenDescriptor
    let override: NookTokenValue?
    let resolved: NookResolvedTokenValue?
    let isOpen: Bool
    let note: String?
    let resolver: ThemeColorResolver
    let seed: Double
    let toggle: () -> Void
    let set: (NookTokenValue?) -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isOpen {
                if let note {
                    Text(note)
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.secondary)
                }
                EditorRows {
                    TokenValueEditor(
                        descriptor: descriptor,
                        value: Binding(get: { override ?? seedValue }, set: { set($0) }),
                        resolver: resolver,
                        seed: seed
                    )
                }
                .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 12)
                    Text(leafName)
                        .font(PlaygroundTheme.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .trackingHover($isHovered)
            .help(descriptor.id)
            .accessibilityLabel(descriptor.id)
            .accessibilityValue(isOpen ? "Editing" : "")
            if override != nil {
                ResetButton { set(nil) }
            }
            Spacer(minLength: 8)
            ResolvedTokenValueView(value: resolved)
            if override != nil {
                ModifiedDot()
            }
        }
    }

    /// The id without its group, which the card already shows: `cornerRadius` under Banner.
    private var leafName: String {
        let parts = descriptor.id.split(separator: ".", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : descriptor.id
    }

    /// What an editor starts from before anything is overridden: the default, or for a token
    /// that defaults to none, a value worth hearing or seeing.
    private var seedValue: NookTokenValue {
        if let value = descriptor.defaultValue { return value }
        switch descriptor.kind {
            case .sound: return .sound(.system("Pop"))
            case .shadow: return .shadow(NookShadowSpec())
            case .color: return .color(.accent)
            case .dimension: return .dimension(.points(seed))
            case .font: return .font(NookFontSpec(role: .typeBody))
            case .animation: return .animation(.reference(.springDefault))
            case .transition: return .transition(NookContentTransitionSpec())
        }
    }
}

/// The editor for a token's kind.
private struct TokenValueEditor: View {
    let descriptor: NookTokenDescriptor
    @Binding var value: NookTokenValue
    let resolver: ThemeColorResolver
    let seed: Double

    var body: some View {
        switch descriptor.kind {
            case .color:
                ColorValueEditor(value: colorBinding, resolver: resolver, excluding: descriptor.id)
            case .dimension:
                DimensionEditor(value: dimensionBinding, descriptor: descriptor, seed: seed)
            case .font:
                FontSpecEditor(value: fontBinding, excluding: descriptor.id)
            case .animation:
                AnimationSpecEditor(value: animationBinding, excluding: descriptor.id)
            case .transition:
                TransitionSpecEditor(value: transitionBinding)
            case .sound:
                SoundSpecEditor(value: soundBinding)
            case .shadow:
                ShadowSpecEditor(value: shadowBinding, resolver: resolver)
        }
    }

    private var colorBinding: Binding<NookColorValue> {
        Binding(
            get: {
                guard case .color(let color) = value else { return .accent }
                return color
            },
            set: { value = .color($0) }
        )
    }

    private var dimensionBinding: Binding<NookDimension> {
        Binding(
            get: {
                guard case .dimension(let dimension) = value else { return .points(seed) }
                return dimension
            },
            set: { value = .dimension($0) }
        )
    }

    private var fontBinding: Binding<NookFontSpec> {
        Binding(
            get: {
                guard case .font(let font) = value else { return NookFontSpec() }
                return font
            },
            set: { value = .font($0) }
        )
    }

    private var animationBinding: Binding<NookAnimationSpec> {
        Binding(
            get: {
                guard case .animation(let animation) = value else { return .reference(.springDefault) }
                return animation
            },
            set: { value = .animation($0) }
        )
    }

    private var transitionBinding: Binding<NookContentTransitionSpec> {
        Binding(
            get: {
                guard case .transition(let transition) = value else { return NookContentTransitionSpec() }
                return transition
            },
            set: { value = .transition($0) }
        )
    }

    private var soundBinding: Binding<NookSoundSpec> {
        Binding(
            get: {
                guard case .sound(let sound) = value else { return .system("Pop") }
                return sound
            },
            set: { value = .sound($0) }
        )
    }

    private var shadowBinding: Binding<NookShadowSpec> {
        Binding(
            get: {
                guard case .shadow(let shadow) = value else { return NookShadowSpec() }
                return shadow
            },
            set: { value = .shadow($0) }
        )
    }
}

// MARK: - Resolved values

/// What a token resolves to now, in a few words or a swatch.
struct ResolvedTokenValueView: View {
    let value: NookResolvedTokenValue?

    var body: some View {
        HStack(spacing: 6) {
            if case .color(let color)? = value {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay { Circle().strokeBorder(PlaygroundTheme.stroke) }
            }
            Text(Self.text(value))
                .font(PlaygroundTheme.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    static func text(_ value: NookResolvedTokenValue?) -> String {
        switch value {
            case nil:
                return ""
            case .color(let color)?:
                return PlaygroundColor(color).hex
            case .dimension(let number)?:
                return number.formatted(.number.precision(.fractionLength(0...2)))
            case .font(let font)?:
                var parts: [String] = []
                if case .points(let size)? = font.size {
                    parts.append(size.formatted(.number.precision(.fractionLength(0...1))) + " pt")
                }
                parts.append(EnumTitles.title((font.weight ?? .regular).rawValue))
                if let design = font.design, design != .default { parts.append(EnumTitles.title(design.rawValue)) }
                if let family = font.family { parts.append(family) }
                return parts.joined(separator: " ")
            case .animation(let animation)?:
                return animationText(animation)
            case .transition(let transition)?:
                var parts = ["opacity \(transition.opacity.formatted())"]
                if transition.blur != 0 { parts.append("blur \(transition.blur.formatted())") }
                if transition.scaleX != 1 || transition.scaleY != 1 {
                    parts.append("scale \(transition.scaleX.formatted()) x \(transition.scaleY.formatted())")
                }
                return parts.joined(separator: ", ")
            case .sound(let sound)?:
                guard let sound else { return "None" }
                let volume = (sound.volume ?? 1).formatted(.percent.precision(.fractionLength(0)))
                switch sound.source {
                    case .system(let name), .resource(let name): return "\(name) \(volume)"
                    case .file(let url): return "\(url.lastPathComponent) \(volume)"
                }
            case .shadow(let shadow)?:
                guard let shadow else { return "None" }
                return "radius \(shadow.radius.formatted()), y \(shadow.y.formatted())"
        }
    }

    private static func animationText(_ animation: NookAnimationSpec) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        switch animation {
            case .spring(let response, let damping, _):
                return "spring \(response.formatted(format)) s, \(damping.formatted(format))"
            case .springDuration(let duration, let bounce):
                return "spring \(duration.formatted(format)) s, bounce \(bounce.formatted(format))"
            case .preset(let preset, let duration, _):
                return "\(preset.rawValue) \(duration.formatted(format)) s"
            case .curve(let curve, let duration):
                return "\(EnumTitles.title(curve.rawValue).lowercased()) \(duration.formatted(format)) s"
            case .bezier(_, _, _, _, let duration):
                return "bezier \(duration.formatted(format)) s"
            case .reference(let id):
                return "{\(id.rawValue)}"
        }
    }
}
