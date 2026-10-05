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

/// `NookTheme.backdrops`: what the chrome paints behind its content for each surface style, as
/// a solid color, a frosted material, Liquid Glass, a gradient, or a mesh.
struct ThemeBackdropCard: View {
    @ObservedObject var model: PlaygroundModel
    let resolver: ThemeColorResolver
    /// The surface style whose backdrop the card edits.
    @Binding var slot: NookSurfaceStyle

    enum Kind: String, CaseIterable, Hashable {
        case framework
        case solid
        case vibrancy
        case liquidGlass
        case linearGradient
        case radialGradient
        case ellipticalGradient
        case angularGradient
        case mesh
        case custom

        var title: String {
            switch self {
                case .framework: "Framework's"
                case .solid: "Solid color"
                case .vibrancy: "Frosted material"
                case .liquidGlass: "Liquid Glass"
                case .linearGradient: "Linear gradient"
                case .radialGradient: "Radial gradient"
                case .ellipticalGradient: "Elliptical gradient"
                case .angularGradient: "Angular gradient"
                case .mesh: "Mesh gradient"
                case .custom: "Host view"
            }
        }
    }

    enum Shading: Hashable {
        case behavior
        case even
        case notchFade
    }

    var body: some View {
        SectionCard(
            title: "Backdrop",
            help: "What the chrome paints behind its content. Each Material has its own; the nook paints the one "
                + "for the Material picked on the Appearance page.",
            isModified: !backdrops.isEmpty,
            reset: { model.settings.theme.backdrops = NookThemeBackdrops() }
        ) {
            SegmentedRow(
                title: "Material",
                selection: $slot,
                choices: [Choice(.solid, "Solid"), Choice(.translucent, "Translucent"), Choice(.liquidGlass, "Glass")]
            )
            MenuRow(title: "Kind", selection: kindBinding, choices: kindChoices)
            if let description = backdrops[slot] {
                BackdropDescriptionEditor(
                    description: Binding(get: { description }, set: { setDescription($0) }),
                    resolver: resolver
                )
            }
            SegmentedRow(
                title: "Glass shading",
                selection: shadingBinding,
                choices: [Choice(.behavior, "Behavior's"), Choice(.even, "Even"), Choice(.notchFade, "Notch fade")],
                help: "How the framework's own Liquid Glass is shaded under this theme. Behavior's leaves it to the "
                    + "Behavior page."
            )
        }
    }

    private var backdrops: NookThemeBackdrops { model.settings.theme.backdrops }

    private func setDescription(_ description: NookBackdropDescription?) {
        switch slot {
            case .solid: model.settings.theme.backdrops.solid = description
            case .translucent: model.settings.theme.backdrops.translucent = description
            case .liquidGlass: model.settings.theme.backdrops.liquidGlass = description
        }
    }

    static func kind(of description: NookBackdropDescription?) -> Kind {
        switch description {
            case nil, .framework?: .framework
            case .solid?: .solid
            case .vibrancy?: .vibrancy
            case .liquidGlass?: .liquidGlass
            case .linearGradient?: .linearGradient
            case .radialGradient?: .radialGradient
            case .ellipticalGradient?: .ellipticalGradient
            case .angularGradient?: .angularGradient
            case .mesh?: .mesh
            case .custom?, .unknown?: .custom
        }
    }

    /// A host view can only be named by a theme file, so it is offered only while one is set.
    private var kindChoices: [Choice<Kind>] {
        Kind.allCases
            .filter { $0 != .custom || Self.kind(of: backdrops[slot]) == .custom }
            .map { Choice($0, $0.title) }
    }

    private var kindBinding: Binding<Kind> {
        Binding(
            get: { Self.kind(of: backdrops[slot]) },
            set: { kind in
                guard kind != Self.kind(of: backdrops[slot]) else { return }
                setDescription(Self.starter(kind))
            }
        )
    }

    /// What a backdrop of `kind` starts as: something that reads as itself at once.
    static func starter(_ kind: Kind) -> NookBackdropDescription? {
        let dark: NookColorValue = "#2A2A33"
        let black: NookColorValue = "#000000"
        switch kind {
            case .framework, .custom:
                return nil
            case .solid:
                return .solid(.reference(.surface, opacity: nil))
            case .vibrancy:
                return .vibrancy(NookBackdropDescription.Vibrancy(material: .hudWindow, darken: 0.3))
            case .liquidGlass:
                return .liquidGlass(NookBackdropDescription.LiquidGlass())
            case .linearGradient:
                return .linearGradient(.init(gradient: NookGradientSpec(colors: [dark, black])))
            case .radialGradient:
                return .radialGradient(.init(gradient: NookGradientSpec(colors: [dark, black]), center: .top))
            case .ellipticalGradient:
                return .ellipticalGradient(
                    .init(gradient: NookGradientSpec(colors: [dark, black]), center: .top, endRadius: 1)
                )
            case .angularGradient:
                return .angularGradient(
                    .init(gradient: NookGradientSpec(colors: ["#3B2A5C", "#1B3A5C", "#1B4D3E", "#3B2A5C"]))
                )
            case .mesh:
                return .mesh(MeshEditor.mesh(width: 2, height: 2, colors: ["#2A1E3A", "#1E2A3A", black, "#101018"]))
        }
    }

    private var shadingBinding: Binding<Shading> {
        Binding(
            get: {
                switch backdrops.glassShading {
                    case nil: .behavior
                    case .even?: .even
                    case .notchFade?: .notchFade
                }
            },
            set: { shading in
                switch shading {
                    case .behavior: model.settings.theme.backdrops.glassShading = nil
                    case .even: model.settings.theme.backdrops.glassShading = .even
                    case .notchFade: model.settings.theme.backdrops.glassShading = .notchFade
                }
            }
        )
    }
}

/// The values of one backdrop description, by its kind.
struct BackdropDescriptionEditor: View {
    @Binding var description: NookBackdropDescription
    let resolver: ThemeColorResolver

    var body: some View {
        switch description {
            case .framework:
                EmptyView()
            case .solid(let color):
                ColorValueEditor(
                    value: Binding(get: { color }, set: { description = .solid($0) }),
                    resolver: resolver
                )
            case .vibrancy(let vibrancy):
                VibrancyEditor(
                    vibrancy: Binding(get: { vibrancy }, set: { description = .vibrancy($0) }),
                    resolver: resolver
                )
            case .liquidGlass(let glass):
                GlassEditor(glass: Binding(get: { glass }, set: { description = .liquidGlass($0) }), resolver: resolver)
            case .linearGradient(let gradient):
                GradientStopsEditor(
                    gradient: Binding(get: { gradient.gradient }, set: { updated in
                        var gradient = gradient
                        gradient.gradient = updated
                        description = .linearGradient(gradient)
                    }),
                    resolver: resolver
                )
                UnitPointRow(title: "Start", point: linear(\.start, in: gradient))
                UnitPointRow(title: "End", point: linear(\.end, in: gradient))
            case .radialGradient(let gradient):
                RadialGradientEditor(
                    gradient: Binding(get: { gradient }, set: { description = .radialGradient($0) }),
                    resolver: resolver
                )
            case .ellipticalGradient(let gradient):
                EllipticalGradientEditor(
                    gradient: Binding(get: { gradient }, set: { description = .ellipticalGradient($0) }),
                    resolver: resolver
                )
            case .angularGradient(let gradient):
                AngularGradientEditor(
                    gradient: Binding(get: { gradient }, set: { description = .angularGradient($0) }),
                    resolver: resolver
                )
            case .mesh(let mesh):
                MeshEditor(mesh: Binding(get: { mesh }, set: { description = .mesh($0) }), resolver: resolver)
            case .custom(let id, _):
                ControlRow(title: "View", help: "A theme file names a view the host registers in Swift.") {
                    Text(id)
                        .font(PlaygroundTheme.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            case .unknown(let kind, _):
                ControlRow(title: "Kind", help: "A kind this build does not know; its fallback is painted.") {
                    Text(kind)
                        .font(PlaygroundTheme.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func linear(
        _ keyPath: WritableKeyPath<NookBackdropDescription.LinearGradient, NookUnitPointSpec>,
        in gradient: NookBackdropDescription.LinearGradient
    ) -> Binding<NookUnitPointSpec> {
        Binding(
            get: { gradient[keyPath: keyPath] },
            set: { point in
                var gradient = gradient
                gradient[keyPath: keyPath] = point
                description = .linearGradient(gradient)
            }
        )
    }
}

// MARK: - Materials

/// A frosted `NSVisualEffectView` material with a darken pass over it.
private struct VibrancyEditor: View {
    @Binding var vibrancy: NookBackdropDescription.Vibrancy
    let resolver: ThemeColorResolver

    var body: some View {
        MenuRow(
            title: "Material",
            selection: $vibrancy.material,
            choices: NookBackdropDescription.Material.allCases.map { Choice($0, EnumTitles.title($0.rawValue)) }
        )
        SegmentedRow(
            title: "Blending",
            selection: $vibrancy.blending,
            choices: [Choice(.behindWindow, "Behind window"), Choice(.withinWindow, "Within window")]
        )
        SliderRow(
            title: "Darken, dark",
            value: $vibrancy.darken.dark,
            range: 0...1,
            step: 0.01,
            defaultValue: 0,
            format: .percent,
            help: "How much of the darken color covers the material on dark chrome."
        )
        SliderRow(
            title: "Darken, light",
            value: $vibrancy.darken.light,
            range: 0...1,
            step: 0.01,
            defaultValue: 0,
            format: .percent,
            help: "How much of the darken color covers the material on light chrome."
        )
        OptionalColorRow(
            title: "Darken color",
            value: $vibrancy.darkenColor,
            fallback: .black(opacity: 1),
            fallbackTitle: "Black",
            resolver: resolver
        )
        SwitchRow(
            title: "Follows strength",
            isOn: $vibrancy.scalesWithStrength,
            help: "Whether the person's backdrop strength scales the darken."
        )
    }
}

/// Liquid Glass: Apple's material variant, a tint, and the approximation's sheen and rim.
private struct GlassEditor: View {
    @Binding var glass: NookBackdropDescription.LiquidGlass
    let resolver: ThemeColorResolver

    var body: some View {
        SegmentedRow(
            title: "Variant",
            selection: variantBinding,
            choices: [Choice(.regular, "Regular"), Choice(.clear, "Clear")],
            help: "Apple's glass material on macOS 26: regular, or the clearer variant."
        )
        OptionalColorRow(title: "Tint", value: $glass.tint, fallback: nil, fallbackTitle: "None", resolver: resolver)
        SliderRow(
            title: "Tint strength",
            value: tintStrength,
            range: 0...1,
            step: 0.01,
            defaultValue: 0.3,
            format: .percent
        )
        SliderRow(
            title: "Highlight",
            value: $glass.highlight,
            range: 0...1,
            step: 0.01,
            defaultValue: 0.6,
            format: .percent,
            help: "The sheen of the glass before macOS 26."
        )
        OptionalColorRow(
            title: "Highlight color",
            value: $glass.highlightColor,
            fallback: .white(opacity: 1),
            fallbackTitle: "White",
            resolver: resolver
        )
        SliderRow(
            title: "Rim width",
            value: rimWidth,
            range: 0...4,
            step: 0.25,
            defaultValue: 1,
            help: "The rim of the glass before macOS 26."
        )
        MenuRow(
            title: "Fallback",
            selection: $glass.fallbackMaterial,
            choices: [Choice<NookBackdropDescription.Material?>(nil, "Surface's")]
                + NookBackdropDescription.Material.allCases.map { Choice($0, EnumTitles.title($0.rawValue)) },
            help: "The material the glass is drawn with before macOS 26."
        )
        SwitchRow(
            title: "Follows strength",
            isOn: $glass.scalesWithStrength,
            help: "Whether the person's backdrop strength scales the tint."
        )
    }

    private var variantBinding: Binding<NookBackdropDescription.GlassVariant> {
        Binding(
            get: { glass.variant ?? .regular },
            set: { glass.variant = $0 == .regular ? nil : $0 }
        )
    }

    private var tintStrength: Binding<Double> {
        Binding(
            get: { glass.tintStrength.dark },
            set: { glass.tintStrength = NookAdaptiveNumber($0) }
        )
    }

    private var rimWidth: Binding<Double> {
        Binding(
            get: { glass.rimWidth ?? 1 },
            set: { glass.rimWidth = abs($0 - 1) < 0.0005 ? nil : $0 }
        )
    }
}

/// A color that is optional: the swatch sets it, and the reset puts the fallback back.
private struct OptionalColorRow: View {
    let title: String
    @Binding var value: NookColorValue?
    let fallback: NookColorValue?
    let fallbackTitle: String
    let resolver: ThemeColorResolver

    var body: some View {
        ControlRow(title: title, isModified: value != nil) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if value == nil {
                    Text(fallbackTitle)
                        .font(PlaygroundTheme.caption)
                        .foregroundStyle(.tertiary)
                }
                ColorSwatch(
                    title: title,
                    color: Binding(
                        get: { (value ?? fallback).map { resolver.color($0) } ?? .clear },
                        set: { value = .hex(PlaygroundColor($0)) }
                    ),
                    supportsOpacity: true
                )
            }
        } reset: {
            value = nil
        }
    }
}

// MARK: - Gradients

/// A gradient's stops: a color each, at a location from 0 to 1.
struct GradientStopsEditor: View {
    @Binding var gradient: NookGradientSpec
    let resolver: ThemeColorResolver

    private static let maximumStops = 8

    var body: some View {
        ForEach(Array(gradient.stops.indices), id: \.self) { index in
            stopRow(index)
        }
        ControlRow(title: "Stops", help: "Even spreads the stops at equal distances.") {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    spreadEvenly()
                } label: {
                    Label("Even", systemImage: "equal")
                }
                .disabled(gradient.stops.allSatisfy { $0.location == nil })
                Button {
                    addStop()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(gradient.stops.count >= Self.maximumStops)
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private func stopRow(_ index: Int) -> some View {
        let locations = gradient.resolvedLocations
        let location = index < locations.count ? locations[index] : 0
        return ControlRow(title: "Stop \(index + 1)") {
            HStack(spacing: 8) {
                Slider(value: locationBinding(index, current: location), in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("Stop \(index + 1) location")
                Text(location.formatted(.percent.precision(.fractionLength(0))))
                    .font(PlaygroundTheme.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                ColorSwatch(title: "Stop \(index + 1) color", color: colorBinding(index), supportsOpacity: true)
                Button {
                    gradient.stops.remove(at: index)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(gradient.stops.count <= 2)
                .help("Remove the stop")
                .accessibilityLabel("Remove stop \(index + 1)")
            }
        }
    }

    private func locationBinding(_ index: Int, current: Double) -> Binding<Double> {
        Binding(
            get: { current },
            set: { location in
                guard gradient.stops.indices.contains(index) else { return }
                // Pin every stop where it is drawn, so moving one does not move the others.
                let locations = gradient.resolvedLocations
                for stop in gradient.stops.indices where gradient.stops[stop].location == nil {
                    gradient.stops[stop].location = locations[stop]
                }
                gradient.stops[index].location = (location * 100).rounded() / 100
            }
        )
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { gradient.stops.indices.contains(index) ? resolver.color(gradient.stops[index].color) : .clear },
            set: { color in
                guard gradient.stops.indices.contains(index) else { return }
                gradient.stops[index].color = .hex(PlaygroundColor(color))
            }
        )
    }

    private func spreadEvenly() {
        for index in gradient.stops.indices {
            gradient.stops[index].location = nil
        }
    }

    private func addStop() {
        let last = gradient.stops.last?.color ?? "#000000"
        let hasLocations = gradient.stops.contains { $0.location != nil }
        gradient.stops.append(NookGradientSpec.Stop(color: last, location: hasLocations ? 1 : nil))
    }
}

private struct RadialGradientEditor: View {
    @Binding var gradient: NookBackdropDescription.RadialGradient
    let resolver: ThemeColorResolver

    var body: some View {
        GradientStopsEditor(gradient: $gradient.gradient, resolver: resolver)
        UnitPointRow(title: "Center", point: $gradient.center)
        NumberRow(title: "Start radius", value: $gradient.startRadius, range: 0...2000, step: 10, unit: "pt")
        NumberRow(title: "End radius", value: $gradient.endRadius, range: 0...2000, step: 10, unit: "pt")
    }
}

private struct EllipticalGradientEditor: View {
    @Binding var gradient: NookBackdropDescription.EllipticalGradient
    let resolver: ThemeColorResolver

    var body: some View {
        GradientStopsEditor(gradient: $gradient.gradient, resolver: resolver)
        UnitPointRow(title: "Center", point: $gradient.center)
        NumberRow(
            title: "Start radius",
            value: $gradient.startRadius,
            range: 0...4,
            step: 0.05,
            help: "A fraction of the surface's half size."
        )
        NumberRow(
            title: "End radius",
            value: $gradient.endRadius,
            range: 0...4,
            step: 0.05,
            help: "A fraction of the surface's half size."
        )
    }
}

private struct AngularGradientEditor: View {
    @Binding var gradient: NookBackdropDescription.AngularGradient
    let resolver: ThemeColorResolver

    var body: some View {
        GradientStopsEditor(gradient: $gradient.gradient, resolver: resolver)
        UnitPointRow(title: "Center", point: $gradient.center)
        NumberRow(title: "Start angle", value: $gradient.startAngle, range: -720...720, step: 15, unit: "deg")
        NumberRow(title: "End angle", value: $gradient.endAngle, range: -720...720, step: 15, unit: "deg")
    }
}

// MARK: - Mesh

/// A mesh gradient on an even grid: two by two or three by three colors.
struct MeshEditor: View {
    @Binding var mesh: NookBackdropDescription.Mesh
    let resolver: ThemeColorResolver

    var body: some View {
        SegmentedRow(
            title: "Grid",
            selection: sizeBinding,
            choices: [Choice(2, "2 x 2"), Choice(3, "3 x 3")],
            help: "The colors sit on an even grid, from the top leading corner."
        )
        ForEach(0..<mesh.height, id: \.self) { row in
            ControlRow(title: "Row \(row + 1)") {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(0..<mesh.width, id: \.self) { column in
                        ColorSwatch(
                            title: "Row \(row + 1), column \(column + 1)",
                            color: colorBinding(row * mesh.width + column),
                            supportsOpacity: true
                        )
                    }
                }
            }
        }
        SwitchRow(title: "Smooth colors", isOn: $mesh.smoothsColors)
    }

    /// A `width` by `height` mesh with its points on an even grid.
    static func mesh(width: Int, height: Int, colors: [NookColorValue]) -> NookBackdropDescription.Mesh {
        var points: [[Double]] = []
        for row in 0..<height {
            for column in 0..<width {
                points.append([Double(column) / Double(max(width - 1, 1)), Double(row) / Double(max(height - 1, 1))])
            }
        }
        return NookBackdropDescription.Mesh(width: width, height: height, points: points, colors: colors)
    }

    private var sizeBinding: Binding<Int> {
        Binding(
            get: { mesh.width == 3 && mesh.height == 3 ? 3 : 2 },
            set: { size in
                guard size != mesh.width || size != mesh.height else { return }
                mesh = Self.resampled(mesh, to: size)
            }
        )
    }

    /// `mesh` on a `size` by `size` grid, each color taken from the nearest point of the old one.
    static func resampled(_ mesh: NookBackdropDescription.Mesh, to size: Int) -> NookBackdropDescription.Mesh {
        var colors: [NookColorValue] = []
        for row in 0..<size {
            for column in 0..<size {
                let x = Double(column) / Double(size - 1)
                let y = Double(row) / Double(size - 1)
                let oldColumn = Int((x * Double(max(mesh.width - 1, 0))).rounded())
                let oldRow = Int((y * Double(max(mesh.height - 1, 0))).rounded())
                let index = oldRow * mesh.width + oldColumn
                colors.append(mesh.colors.indices.contains(index) ? mesh.colors[index] : "#000000")
            }
        }
        var resampled = Self.mesh(width: size, height: size, colors: colors)
        resampled.smoothsColors = mesh.smoothsColors
        return resampled
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { mesh.colors.indices.contains(index) ? resolver.color(mesh.colors[index]) : .clear },
            set: { color in
                guard mesh.colors.indices.contains(index) else { return }
                mesh.colors[index] = .hex(PlaygroundColor(color))
            }
        )
    }
}
