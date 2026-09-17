// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import AppKit
import SwiftUI

/// The controls window's look: neutral surfaces that follow light and dark mode, light type,
/// and pill buttons. The accent color is kept for actions and selection.
enum PlaygroundTheme {
    /// The backdrop's top and bottom: grey to near black, like the nook, or white to soft grey.
    static let canvasTop = Color.adaptive(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(white: 0.17, alpha: 1))
    static let canvasBottom = Color.adaptive(
        light: NSColor(white: 0.915, alpha: 1),
        dark: NSColor(white: 0.045, alpha: 1)
    )
    // Surfaces are translucent so they sit evenly on every part of the gradient.
    static let panel = Color.adaptive(light: NSColor(white: 1, alpha: 0.6), dark: NSColor(white: 1, alpha: 0.04))
    static let card = Color.adaptive(light: NSColor(white: 1, alpha: 0.78), dark: NSColor(white: 1, alpha: 0.05))
    static let codeBackground = Color.adaptive(
        light: NSColor(white: 1, alpha: 0.7),
        dark: NSColor(white: 0, alpha: 0.28)
    )
    static let stroke = Color.adaptive(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.07))
    static let hairline = Color.adaptive(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.06))
    static let controlFill = Color.adaptive(
        light: NSColor(white: 0, alpha: 0.05),
        dark: NSColor(white: 1, alpha: 0.08)
    )
    static let controlHoverFill = Color.adaptive(
        light: NSColor(white: 0, alpha: 0.09),
        dark: NSColor(white: 1, alpha: 0.15)
    )
    static let hoverFill = Color.adaptive(light: NSColor(white: 0, alpha: 0.035), dark: NSColor(white: 1, alpha: 0.05))
    static let selectedFill = Color.adaptive(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.1))
    /// The raised segment of a pill picker.
    static let thumb = Color.adaptive(light: NSColor(white: 1, alpha: 1), dark: NSColor(white: 1, alpha: 0.17))
    /// Laid over the material of a surface that floats above the page, so what is behind it reads as
    /// depth rather than as content. Without it a saturated page element, such as a page badge, shows
    /// straight through and looks like a rendering fault.
    static let floatingScrim = Color.adaptive(
        light: NSColor(white: 0.99, alpha: 0.72),
        dark: NSColor(white: 0.13, alpha: 0.76)
    )
    static let accent = Color.accentColor
    static let destructive = Color(nsColor: .systemRed)

    static let cardRadius: CGFloat = 14
    static let panelRadius: CGFloat = 16

    static let pageTitle = Font.system(size: 28, weight: .light)
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11.5, weight: .regular)
    static let sectionTitle = Font.system(size: 12, weight: .regular)
}

private enum AssistantDockedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var assistantDocked: Bool {
        get { self[AssistantDockedKey.self] }
        set { self[AssistantDockedKey.self] = newValue }
    }
}

extension Color {
    /// A color with its own value for light and for dark mode.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        )
    }
}

extension PlaygroundPage {
    enum Group: CaseIterable, Identifiable {
        case look
        case chrome
        case share

        var id: Self { self }

        var title: String {
            switch self {
                case .look: "Look"
                case .chrome: "Chrome"
                case .share: "Share"
            }
        }

        var pages: [PlaygroundPage] {
            PlaygroundPage.allCases.filter { $0.group == self }
        }
    }

    var group: Group {
        switch self {
            case .appearance, .theme, .panel, .typeAndMotion: .look
            case .topBar, .companions, .effects, .behavior: .chrome
            case .presets: .share
        }
    }
}

// MARK: - Surfaces

extension View {
    /// A rounded surface with a hairline edge.
    func surface(
        _ fill: Color = PlaygroundTheme.card,
        radius: CGFloat = PlaygroundTheme.cardRadius
    ) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(PlaygroundTheme.stroke)
            }
    }

    /// A plain text field on a soft rounded fill.
    func playgroundField() -> some View {
        textFieldStyle(.plain)
            .font(PlaygroundTheme.body)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(PlaygroundTheme.controlFill)
            )
    }
}

/// The window's backdrop: a quiet vertical gradient with a faint sheen along the top.
struct PlaygroundBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [PlaygroundTheme.canvasTop, PlaygroundTheme.canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [Color.white.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 640
            )
        }
        .ignoresSafeArea()
    }
}

/// A page's symbol on a soft disc, heading the page.
struct PageBadge: View {
    let page: PlaygroundPage
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(PlaygroundTheme.controlFill)
            Circle()
                .strokeBorder(PlaygroundTheme.stroke)
            Image(systemName: page.systemImage)
                .font(.system(size: size * 0.4, weight: .ultraLight))
                .foregroundStyle(.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

extension View {
    /// Keeps `isHovered` in step with the pointer, with a quick fade.
    func trackingHover(_ isHovered: Binding<Bool>) -> some View {
        onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered.wrappedValue = hovering }
        }
    }
}

/// A capsule button: the accent color for the main action, a soft fill for the rest, red for
/// resets. Every kind brightens under the pointer.
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case destructive
    }

    var kind = Kind.secondary

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, kind: kind)
    }

    private struct PillButton: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: kind == .primary ? .medium : .regular))
                .labelStyle(PillLabelStyle())
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(fill))
                .overlay {
                    if kind == .primary {
                        Capsule().fill(Color.white.opacity(isActive ? 0.16 : 0))
                    }
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .trackingHover($isHovered)
        }

        private var isActive: Bool { isHovered && isEnabled }

        private var fill: Color {
            switch kind {
                case .primary: PlaygroundTheme.accent
                case .secondary: isActive ? PlaygroundTheme.controlHoverFill : PlaygroundTheme.controlFill
                case .destructive: PlaygroundTheme.destructive.opacity(isActive ? 0.22 : 0.12)
            }
        }

        private var foreground: Color {
            switch kind {
                case .primary: .white
                case .secondary: .primary
                case .destructive: PlaygroundTheme.destructive
            }
        }
    }
}

private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 11, weight: .regular))
            configuration.title
        }
    }
}

/// A round, icon-only button. Give it a `help(_:)` tooltip: the icon alone does not say what
/// it does.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, size: size)
    }

    private struct IconButton: View {
        let configuration: Configuration
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: size * 0.46, weight: .regular))
                .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(isActive ? PlaygroundTheme.controlHoverFill : PlaygroundTheme.controlFill)
                )
                .contentShape(Circle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .trackingHover($isHovered)
        }

        private var isActive: Bool { isHovered && isEnabled }
    }
}

/// A full-width row that lights up while hovered, and stays lit while selected.
struct HighlightRowButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        HighlightRow(configuration: configuration, isSelected: isSelected)
    }

    private struct HighlightRow: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(fill)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .trackingHover($isHovered)
        }

        private var fill: Color {
            if isSelected || configuration.isPressed { return PlaygroundTheme.selectedFill }
            return isHovered && isEnabled ? PlaygroundTheme.hoverFill : .clear
        }
    }
}

/// The window's top-right controls: labeled capsules that take the accent color while on.
struct TopPillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(TopPillButtonStyle(isOn: configuration.isOn))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

struct TopPillButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        TopPill(configuration: configuration, isOn: isOn)
    }

    private struct TopPill: View {
        let configuration: Configuration
        let isOn: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .labelStyle(TopPillLabelStyle())
                .foregroundStyle(isOn ? PlaygroundTheme.accent : Color.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
                .trackingHover($isHovered)
        }

        private var fill: Color {
            if isOn {
                return PlaygroundTheme.accent.opacity(isHovered ? 0.24 : 0.15)
            }
            return isHovered ? PlaygroundTheme.controlHoverFill : PlaygroundTheme.controlFill
        }
    }
}

private struct TopPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 11.5, weight: .regular))
            configuration.title
                .font(.system(size: 12.5, weight: .regular))
        }
    }
}

/// A soft circle behind a borderless control while the pointer is over it.
struct HoverCircle: ViewModifier {
    var size: CGFloat = 24
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(Circle().fill(isHovered ? PlaygroundTheme.controlHoverFill : .clear))
            .contentShape(Circle())
            .trackingHover($isHovered)
    }
}

// MARK: - Picker

/// A segmented choice: a soft capsule with a raised, sliding segment. The segments share the
/// width the picker is given.
struct PillPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Choice<Value>]
    @Namespace private var thumb
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices) { choice in
                let isSelected = choice.value == selection
                let isHovered = choice.value == hovered
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = choice.value }
                } label: {
                    Text(choice.title)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(isSelected || isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(PlaygroundTheme.thumb)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            } else if isHovered {
                                Capsule()
                                    .fill(PlaygroundTheme.hoverFill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        if hovering {
                            hovered = choice.value
                        } else if hovered == choice.value {
                            hovered = nil
                        }
                    }
                }
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(PlaygroundTheme.controlFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// One option of a picker.
struct Choice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }

    var id: Value { value }
}
