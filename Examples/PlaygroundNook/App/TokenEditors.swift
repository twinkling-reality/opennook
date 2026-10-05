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

// Editors for the values a theme holds: colors, numbers, fonts, animations, transitions, sounds,
// and shadows. The Tokens page picks one by a token's kind, and the Theme and Effects pages reuse
// them, so a value is edited the same way wherever it appears. Each editor is a run of rows in
// the window's own controls.

// MARK: - Rows

/// A pop-up menu in a row's control column.
struct MenuRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Choice<Value>]
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help) {
            Picker(title, selection: $selection) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.value)
                }
            }
            .labelsHidden()
        }
    }
}

/// A number typed into a field or stepped, kept in `range`.
struct NumberRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = ""
    var help: String?

    var body: some View {
        ControlRow(title: title, help: help) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                TextField(title, value: clamped, format: .number.precision(.fractionLength(0...3)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .playgroundField()
                    .frame(width: 84)
                if !unit.isEmpty {
                    Text(unit)
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper(title, value: clamped, in: range, step: step)
                    .labelsHidden()
            }
        }
    }

    private var clamped: Binding<Double> {
        Binding(
            get: { value },
            set: { value = $0.isFinite ? min(max($0, range.lowerBound), range.upperBound) : value }
        )
    }
}

/// The editors' rows, set in from the row that opened them.
struct EditorRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(PlaygroundTheme.hairline)
                .frame(width: 2)
        }
    }
}

/// Resolves theme colors for swatches, with the theme and appearance the nook shows now.
struct ThemeColorResolver {
    let theme: NookTheme
    let context: NookThemeContext

    /// `value` as the chrome shows it, or as it shows it on dark or light chrome.
    func color(_ value: NookColorValue, isDark: Bool? = nil) -> Color {
        var context = context
        if let isDark { context.isDark = isDark }
        return theme.resolve(value, in: context)
    }

    /// `value` as an 8-bit color, for an editor that turns it into a plain color.
    func rgba(_ value: NookColorValue, isDark: Bool? = nil) -> PlaygroundColor {
        if case .hex(let rgba) = value { return rgba }
        return PlaygroundColor(color(value, isDark: isDark))
    }
}

// MARK: - Colors

/// A theme color: a plain color, a pair for dark and light chrome, the accent at an opacity, or
/// another color token.
struct ColorValueEditor: View {
    @Binding var value: NookColorValue
    let resolver: ThemeColorResolver
    /// The color token being edited, left out of the tokens it can refer to.
    var excluding: String?

    enum Form: Hashable {
        case color
        case pair
        case accent
        case token
    }

    var body: some View {
        SegmentedRow(
            title: "Form",
            selection: formBinding,
            choices: [Choice(.color, "Color"), Choice(.pair, "Dark/Light"), Choice(.accent, "Accent"), Choice(.token, "Token")],
            help: "A plain color, one for dark chrome and one for light, the accent, or another color token."
        )
        switch form {
            case .color:
                swatchRow("Color", value: $value, isDark: nil)
            case .pair:
                swatchRow("Dark", value: pairBinding(\.dark), isDark: true)
                swatchRow("Light", value: pairBinding(\.light), isDark: false)
            case .accent:
                SliderRow(
                    title: "Opacity",
                    value: opacityBinding,
                    range: 0...1,
                    step: 0.01,
                    defaultValue: 1,
                    format: .percent
                )
            case .token:
                MenuRow(title: "Token", selection: tokenBinding, choices: colorTokenChoices)
                SliderRow(
                    title: "Opacity",
                    value: opacityBinding,
                    range: 0...1,
                    step: 0.01,
                    defaultValue: 1,
                    format: .percent
                )
        }
    }

    static func form(of value: NookColorValue) -> Form {
        switch value {
            case .adaptive: .pair
            case .reference(let id, _): id == .accent ? .accent : .token
            case .hex, .srgb, .white, .black, .system, .hierarchical: .color
        }
    }

    private var form: Form { Self.form(of: value) }

    private var formBinding: Binding<Form> {
        Binding(
            get: { form },
            set: { newForm in
                guard newForm != form else { return }
                switch newForm {
                    case .color:
                        value = .hex(resolver.rgba(value))
                    case .pair:
                        value = .adaptive(
                            NookAdaptiveColor(
                                dark: .hex(resolver.rgba(value, isDark: true)),
                                light: .hex(resolver.rgba(value, isDark: false))
                            )
                        )
                    case .accent:
                        value = .accent
                    case .token:
                        let first = colorTokenChoices.first?.value ?? NookColorID.labelPrimary.rawValue
                        value = .reference(NookColorID(rawValue: first), opacity: nil)
                }
            }
        )
    }

    private func swatchRow(_ title: String, value: Binding<NookColorValue>, isDark: Bool?) -> some View {
        ControlRow(title: title) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(resolver.rgba(value.wrappedValue, isDark: isDark).hex)
                    .font(PlaygroundTheme.caption.monospaced())
                    .foregroundStyle(.secondary)
                ColorSwatch(
                    title: title,
                    color: Binding(
                        get: { resolver.color(value.wrappedValue, isDark: isDark) },
                        set: { value.wrappedValue = .hex(PlaygroundColor($0)) }
                    ),
                    supportsOpacity: true
                )
            }
        }
    }

    private func pairBinding(_ keyPath: WritableKeyPath<NookAdaptiveColor, NookColorValue>) -> Binding<NookColorValue> {
        Binding(
            get: {
                guard case .adaptive(let pair) = value else { return value }
                return pair[keyPath: keyPath]
            },
            set: { newValue in
                guard case .adaptive(var pair) = value else { return }
                pair[keyPath: keyPath] = newValue
                value = .adaptive(pair)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: {
                guard case .reference(_, let opacity) = value else { return 1 }
                return opacity ?? 1
            },
            set: { opacity in
                guard case .reference(let id, _) = value else { return }
                value = .reference(id, opacity: abs(opacity - 1) < 0.0005 ? nil : opacity)
            }
        )
    }

    private var tokenBinding: Binding<String> {
        Binding(
            get: {
                guard case .reference(let id, _) = value else { return "" }
                return id.rawValue
            },
            set: { id in
                guard case .reference(_, let opacity) = value else { return }
                value = .reference(NookColorID(rawValue: id), opacity: opacity)
            }
        )
    }

    private var colorTokenChoices: [Choice<String>] {
        NookTokenDescriptor.all
            .filter { $0.kind == .color && $0.id != excluding && $0.id != NookColorID.accent.rawValue }
            .map { Choice($0.id, $0.id) }
    }
}

// MARK: - Numbers

/// A number token: a value, or another number token times a factor.
struct DimensionEditor: View {
    @Binding var value: NookDimension
    let descriptor: NookTokenDescriptor
    /// The number a switch to a plain value starts from.
    let seed: Double

    var body: some View {
        SegmentedRow(
            title: "Form",
            selection: isReference,
            choices: [Choice(false, "Value"), Choice(true, "Token")],
            help: "A number, or another number token times a factor."
        )
        switch value {
            case .points:
                NumberRow(
                    title: "Value",
                    value: pointsBinding,
                    range: Self.editingRange(descriptor.unit),
                    step: Self.step(descriptor.unit),
                    unit: Self.unitText(descriptor.unit),
                    help: scalingHelp
                )
            case .reference:
                MenuRow(title: "Token", selection: referenceBinding, choices: referenceChoices)
                NumberRow(title: "Times", value: timesBinding, range: 0...10, step: 0.1)
        }
    }

    static func editingRange(_ unit: NookTokenDescriptor.Unit?) -> ClosedRange<Double> {
        switch unit {
            case .opacity?: 0...1
            case .seconds?: 0...10
            case .tracking?: -10...10
            case .points?, nil: 0...1000
        }
    }

    static func step(_ unit: NookTokenDescriptor.Unit?) -> Double {
        switch unit {
            case .opacity?, .seconds?, .tracking?: 0.01
            case .points?, nil: 0.5
        }
    }

    static func unitText(_ unit: NookTokenDescriptor.Unit?) -> String {
        switch unit {
            case .points?: "pt"
            case .seconds?: "s"
            case .opacity?, .tracking?, nil: ""
        }
    }

    private var scalingHelp: String? {
        switch descriptor.scaling {
            case .none: nil
            case .spacing, .type: "Written at scale 1: the theme's Scale multiplies it."
            case .radius: "Written at the standard radius: the theme's Corners multiplies it."
        }
    }

    private var isReference: Binding<Bool> {
        Binding(
            get: {
                if case .reference = value { return true }
                return false
            },
            set: { reference in
                if reference {
                    guard case .points = value else { return }
                    let first = referenceChoices.first?.value ?? NookDimensionID.spaceMD.rawValue
                    value = .token(NookDimensionID(rawValue: first))
                } else {
                    guard case .reference = value else { return }
                    value = .points(seed)
                }
            }
        )
    }

    private var pointsBinding: Binding<Double> {
        Binding(
            get: {
                guard case .points(let points) = value else { return seed }
                return points
            },
            set: { value = .points($0) }
        )
    }

    private var referenceBinding: Binding<String> {
        Binding(
            get: {
                guard case .reference(let id, _) = value else { return "" }
                return id.rawValue
            },
            set: { id in
                guard case .reference(_, let times) = value else { return }
                value = .reference(NookDimensionID(rawValue: id), times: times)
            }
        )
    }

    private var timesBinding: Binding<Double> {
        Binding(
            get: {
                guard case .reference(_, let times) = value else { return 1 }
                return times
            },
            set: { times in
                guard case .reference(let id, _) = value else { return }
                value = .reference(id, times: times)
            }
        )
    }

    private var referenceChoices: [Choice<String>] {
        NookTokenDescriptor.all
            .filter { $0.kind == .dimension && $0.id != descriptor.id && $0.unit == descriptor.unit }
            .map { Choice($0.id, $0.id) }
    }
}

// MARK: - Fonts

/// A font: a role to start from, and a size and traits that replace the role's.
struct FontSpecEditor: View {
    @Binding var value: NookFontSpec
    /// The font token being edited, left out of the roles it can start from.
    var excluding: String?

    var body: some View {
        MenuRow(title: "Role", selection: roleBinding, choices: roleChoices, help: "The font this one starts from.")
        ControlRow(title: "Size", help: "Points at scale 1. Empty takes the role's size.") {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                TextField(
                    "Size",
                    value: sizeBinding,
                    format: .number.precision(.fractionLength(0...2)),
                    prompt: Text(sizePrompt)
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .playgroundField()
                .frame(width: 120)
                Text("pt")
                    .font(PlaygroundTheme.caption)
                    .foregroundStyle(.secondary)
            }
        }
        MenuRow(
            title: "Weight",
            selection: $value.weight,
            choices: [Choice<NookFontWeight?>(nil, "From role")]
                + NookFontWeight.allCases.map { Choice($0, EnumTitles.title($0.rawValue)) }
        )
        MenuRow(
            title: "Design",
            selection: $value.design,
            choices: [Choice<NookFontDesign?>(nil, "From theme")]
                + NookFontDesign.allCases.map { Choice($0, EnumTitles.title($0.rawValue)) }
        )
        MenuRow(
            title: "Width",
            selection: $value.width,
            choices: [Choice<NookFontWidth?>(nil, "From theme")]
                + NookFontWidth.allCases.map { Choice($0, EnumTitles.title($0.rawValue)) }
        )
        TextRow(title: "Family", text: familyBinding, prompt: "System font", help: "An installed font family's name.")
        MenuRow(
            title: "Digits",
            selection: $value.monospacedDigits,
            choices: [Choice<Bool?>(nil, "From role"), Choice(true, "Monospaced"), Choice(false, "Proportional")]
        )
    }

    private var roleBinding: Binding<String> {
        Binding(
            get: { value.role?.rawValue ?? "" },
            set: { value.role = $0.isEmpty ? nil : NookFontID(rawValue: $0) }
        )
    }

    private var roleChoices: [Choice<String>] {
        [Choice("", "None")]
            + NookTokenDescriptor.all.filter { $0.kind == .font && $0.id != excluding }.map { Choice($0.id, $0.id) }
    }

    private var sizeBinding: Binding<Double?> {
        Binding(
            get: {
                guard case .points(let size)? = value.size else { return nil }
                return size
            },
            set: { size in
                value.size = size.map { .points(min(max($0, 1), 200)) }
            }
        )
    }

    private var sizePrompt: String {
        if case .reference(let id, _)? = value.size { return "{\(id.rawValue)}" }
        return "From role"
    }

    private var familyBinding: Binding<String> {
        Binding(
            get: { value.family ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                value.family = trimmed.isEmpty ? nil : trimmed
            }
        )
    }
}

/// Display names for the framework's enumerations, by raw value: `semibold` as `Semibold`,
/// `easeInOut` as `Ease in out`.
enum EnumTitles {
    static func title(_ rawValue: String) -> String {
        guard let first = rawValue.first else { return rawValue }
        var words: [String] = []
        var current = String(first).uppercased()
        for character in rawValue.dropFirst() {
            if character.isUppercase {
                words.append(current)
                current = String(character).lowercased()
            } else {
                current.append(character)
            }
        }
        words.append(current)
        return words.joined(separator: " ")
    }
}

// MARK: - Animations

/// An animation: a spring, a named spring, a timing curve, a Bezier curve, or another animation
/// token.
struct AnimationSpecEditor: View {
    @Binding var value: NookAnimationSpec
    /// The animation token being edited, left out of the tokens it can refer to.
    var excluding: String?

    enum Form: String, Hashable, CaseIterable {
        case spring
        case springDuration
        case preset
        case curve
        case bezier
        case reference

        var title: String {
            switch self {
                case .spring: "Spring"
                case .springDuration: "Spring by duration"
                case .preset: "Named spring"
                case .curve: "Timing curve"
                case .bezier: "Bezier curve"
                case .reference: "Token"
            }
        }
    }

    var body: some View {
        MenuRow(title: "Kind", selection: formBinding, choices: Form.allCases.map { Choice($0, $0.title) })
        fields
    }

    @ViewBuilder
    private var fields: some View {
        switch value {
            case .spring(let response, let damping, let blend):
                NumberRow(
                    title: "Response",
                    value: number(response) { .spring(response: $0, dampingFraction: damping, blendDuration: blend) },
                    range: 0.01...5,
                    step: 0.01,
                    unit: "s"
                )
                NumberRow(
                    title: "Damping",
                    value: number(damping) { .spring(response: response, dampingFraction: $0, blendDuration: blend) },
                    range: 0.01...2,
                    step: 0.01
                )
                NumberRow(
                    title: "Blend",
                    value: number(blend) { .spring(response: response, dampingFraction: damping, blendDuration: $0) },
                    range: 0...5,
                    step: 0.01,
                    unit: "s"
                )
            case .springDuration(let duration, let bounce):
                NumberRow(
                    title: "Duration",
                    value: number(duration) { .springDuration(duration: $0, bounce: bounce) },
                    range: 0.01...5,
                    step: 0.01,
                    unit: "s"
                )
                NumberRow(
                    title: "Bounce",
                    value: number(bounce) { .springDuration(duration: duration, bounce: $0) },
                    range: -1...1,
                    step: 0.05
                )
            case .preset(let preset, let duration, let extraBounce):
                MenuRow(
                    title: "Spring",
                    selection: Binding(
                        get: { preset },
                        set: { value = .preset($0, duration: duration, extraBounce: extraBounce) }
                    ),
                    choices: NookSpringPreset.allCases.map { Choice($0, EnumTitles.title($0.rawValue)) }
                )
                NumberRow(
                    title: "Duration",
                    value: number(duration) { .preset(preset, duration: $0, extraBounce: extraBounce) },
                    range: 0.01...5,
                    step: 0.01,
                    unit: "s"
                )
                NumberRow(
                    title: "Extra bounce",
                    value: number(extraBounce) { .preset(preset, duration: duration, extraBounce: $0) },
                    range: -1...1,
                    step: 0.05
                )
            case .curve(let curve, let duration):
                MenuRow(
                    title: "Curve",
                    selection: Binding(get: { curve }, set: { value = .curve($0, duration: duration) }),
                    choices: NookTimingCurve.allCases.map { Choice($0, EnumTitles.title($0.rawValue)) }
                )
                NumberRow(
                    title: "Duration",
                    value: number(duration) { .curve(curve, duration: $0) },
                    range: 0...5,
                    step: 0.01,
                    unit: "s"
                )
            case .bezier(let x1, let y1, let x2, let y2, let duration):
                bezierRows(x1: x1, y1: y1, x2: x2, y2: y2, duration: duration)
            case .reference(let id):
                MenuRow(
                    title: "Token",
                    selection: Binding(get: { id.rawValue }, set: { value = .reference(NookAnimationID(rawValue: $0)) }),
                    choices: referenceChoices
                )
        }
    }

    @ViewBuilder
    private func bezierRows(x1: Double, y1: Double, x2: Double, y2: Double, duration: Double) -> some View {
        NumberRow(
            title: "Control 1 x",
            value: number(x1) { .bezier(x1: $0, y1: y1, x2: x2, y2: y2, duration: duration) },
            range: 0...1,
            step: 0.05
        )
        NumberRow(
            title: "Control 1 y",
            value: number(y1) { .bezier(x1: x1, y1: $0, x2: x2, y2: y2, duration: duration) },
            range: -2...3,
            step: 0.05
        )
        NumberRow(
            title: "Control 2 x",
            value: number(x2) { .bezier(x1: x1, y1: y1, x2: $0, y2: y2, duration: duration) },
            range: 0...1,
            step: 0.05
        )
        NumberRow(
            title: "Control 2 y",
            value: number(y2) { .bezier(x1: x1, y1: y1, x2: x2, y2: $0, duration: duration) },
            range: -2...3,
            step: 0.05
        )
        NumberRow(
            title: "Duration",
            value: number(duration) { .bezier(x1: x1, y1: y1, x2: x2, y2: y2, duration: $0) },
            range: 0...5,
            step: 0.01,
            unit: "s"
        )
    }

    /// A binding to one number of the animation, writing the animation `make` builds from it.
    private func number(_ current: Double, _ make: @escaping (Double) -> NookAnimationSpec) -> Binding<Double> {
        Binding(get: { current }, set: { value = make($0) })
    }

    private var form: Form {
        switch value {
            case .spring: .spring
            case .springDuration: .springDuration
            case .preset: .preset
            case .curve: .curve
            case .bezier: .bezier
            case .reference: .reference
        }
    }

    private var formBinding: Binding<Form> {
        Binding(
            get: { form },
            set: { newForm in
                guard newForm != form else { return }
                let duration = value.nominalDuration ?? 0.35
                switch newForm {
                    case .spring: value = .spring(response: duration, dampingFraction: 0.86)
                    case .springDuration: value = .springDuration(duration: duration, bounce: 0.15)
                    case .preset: value = .preset(.snappy, duration: duration)
                    case .curve: value = .curve(.easeOut, duration: duration)
                    case .bezier: value = .bezier(x1: 0.2, y1: 0, x2: 0, y2: 1, duration: duration)
                    case .reference:
                        let first = referenceChoices.first?.value ?? NookAnimationID.springDefault.rawValue
                        value = .reference(NookAnimationID(rawValue: first))
                }
            }
        )
    }

    private var referenceChoices: [Choice<String>] {
        NookTokenDescriptor.all.filter { $0.kind == .animation && $0.id != excluding }.map { Choice($0.id, $0.id) }
    }
}

// MARK: - Transitions

/// How content enters or leaves: the hidden end's opacity, blur, scale, anchor, and offset, and the
/// curve it moves on.
struct TransitionSpecEditor: View {
    @Binding var value: NookContentTransitionSpec

    var body: some View {
        SliderRow(
            title: "Opacity",
            value: $value.opacity,
            range: 0...1,
            step: 0.01,
            defaultValue: 0,
            format: .percent,
            help: "The opacity at the hidden end."
        )
        NumberRow(title: "Blur", value: $value.blur, range: 0...100, step: 0.5, unit: "pt")
        NumberRow(title: "Scale x", value: $value.scaleX, range: 0...4, step: 0.01)
        NumberRow(title: "Scale y", value: $value.scaleY, range: 0...4, step: 0.01)
        UnitPointRow(title: "Anchor", point: $value.anchor)
        NumberRow(title: "Offset x", value: $value.offsetX, range: -1000...1000, step: 1, unit: "pt")
        NumberRow(title: "Offset y", value: $value.offsetY, range: -1000...1000, step: 1, unit: "pt")
        SegmentedRow(
            title: "Curve",
            selection: hasCurve,
            choices: [Choice(false, "Surface's"), Choice(true, "Own")],
            help: "The surface's own expand and collapse curve, or one of its own."
        )
        if value.animation != nil {
            AnimationSpecEditor(value: animationBinding)
        }
    }

    private var hasCurve: Binding<Bool> {
        Binding(
            get: { value.animation != nil },
            set: { value.animation = $0 ? (value.animation ?? .curve(.easeOut, duration: 0.25)) : nil }
        )
    }

    private var animationBinding: Binding<NookAnimationSpec> {
        Binding(
            get: { value.animation ?? .curve(.easeOut, duration: 0.25) },
            set: { value.animation = $0 }
        )
    }
}

/// A point of a unit square, for an anchor, a gradient's ends, or its center, picked by name. A
/// point a file set that has no name is offered as it is.
struct UnitPointRow: View {
    let title: String
    @Binding var point: NookUnitPointSpec
    var help: String?

    private static let named: [(name: String, title: String, point: NookUnitPointSpec)] = [
        ("topLeading", "Top leading", .topLeading), ("top", "Top", .top), ("topTrailing", "Top trailing", .topTrailing),
        ("leading", "Leading", .leading), ("center", "Center", .center), ("trailing", "Trailing", .trailing),
        ("bottomLeading", "Bottom leading", .bottomLeading), ("bottom", "Bottom", .bottom),
        ("bottomTrailing", "Bottom trailing", .bottomTrailing),
    ]

    var body: some View {
        MenuRow(title: title, selection: selection, choices: choices, help: help)
    }

    private var currentName: String {
        Self.named.first { $0.point == point }?.name ?? "custom"
    }

    private var choices: [Choice<String>] {
        var choices = Self.named.map { Choice($0.name, $0.title) }
        if currentName == "custom" {
            choices.append(Choice("custom", "x \(point.x.formatted()), y \(point.y.formatted())"))
        }
        return choices
    }

    private var selection: Binding<String> {
        Binding(
            get: { currentName },
            set: { name in
                if let match = Self.named.first(where: { $0.name == name }) { point = match.point }
            }
        )
    }
}

// MARK: - Sounds

/// A sound: a system sound by name, a resource in the app bundle, or a file, at a volume.
struct SoundSpecEditor: View {
    @Binding var value: NookSoundSpec

    private static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
        "Submarine", "Tink",
    ]

    enum Source: Hashable {
        case system
        case resource
        case file
    }

    var body: some View {
        SegmentedRow(
            title: "Source",
            selection: sourceBinding,
            choices: [Choice(.system, "System"), Choice(.resource, "Resource"), Choice(.file, "File")],
            help: "A macOS system sound by name, a sound in the app's bundle, or a sound file."
        )
        ControlRow(title: "Name") {
            HStack(spacing: 8) {
                TextField("Name", text: nameBinding, prompt: Text(source == .file ? "/path/to/sound.caf" : "Pop"))
                    .labelsHidden()
                    .playgroundField()
                if source == .system {
                    Menu {
                        ForEach(Self.systemSounds, id: \.self) { name in
                            Button(name) { value.source = .system(name) }
                        }
                    } label: {
                        Image(systemName: "music.note.list")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .modifier(HoverCircle(size: 26))
                    .help("System sounds")
                    .accessibilityLabel("System sounds")
                }
                Button {
                    play()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(IconButtonStyle())
                .help("Play the sound")
                .accessibilityLabel("Play the sound")
            }
        }
        SliderRow(
            title: "Volume",
            value: volumeBinding,
            range: 0...1,
            step: 0.01,
            defaultValue: 1,
            format: .percent,
            help: "Multiplied by the theme's sound volume."
        )
    }

    private var source: Source {
        switch value.source {
            case .system: .system
            case .resource: .resource
            case .file: .file
        }
    }

    private var name: String {
        switch value.source {
            case .system(let name), .resource(let name): name
            case .file(let url): url.isFileURL ? url.path : url.absoluteString
        }
    }

    private var sourceBinding: Binding<Source> {
        Binding(
            get: { source },
            set: { newSource in
                guard newSource != source else { return }
                value.source = Self.source(newSource, named: name)
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(get: { name }, set: { value.source = Self.source(source, named: $0) })
    }

    private static func source(_ source: Source, named name: String) -> NookSoundSpec.Source {
        switch source {
            case .system: .system(name)
            case .resource: .resource(name)
            case .file: .file(URL(fileURLWithPath: name))
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { value.volume ?? 1 },
            set: { value.volume = abs($0 - 1) < 0.0005 ? nil : $0 }
        )
    }

    /// Plays the sound here, in the controls window, so it can be heard before the chrome plays it.
    private func play() {
        let sound: NSSound? =
            switch value.source {
                case .system(let name): NSSound(named: NSSound.Name(name))
                case .resource(let name): NSSound(named: NSSound.Name((name as NSString).deletingPathExtension))
                case .file(let url): NSSound(contentsOf: url, byReference: true)
            }
        sound?.volume = Float(value.volume ?? 1)
        sound?.play()
    }
}

// MARK: - Shadows

/// A shadow: its color, blur radius, and offset.
struct ShadowSpecEditor: View {
    @Binding var value: NookShadowSpec
    let resolver: ThemeColorResolver

    var body: some View {
        ColorValueEditor(value: $value.color, resolver: resolver)
        NumberRow(title: "Radius", value: $value.radius, range: 0...100, step: 0.5, unit: "pt")
        NumberRow(title: "Offset x", value: $value.x, range: -100...100, step: 0.5, unit: "pt")
        NumberRow(title: "Offset y", value: $value.y, range: -100...100, step: 0.5, unit: "pt")
    }
}
