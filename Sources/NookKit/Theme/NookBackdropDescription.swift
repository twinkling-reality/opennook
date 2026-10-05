// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// A chrome backdrop described as data, for a theme.
///
/// It describes what to paint; turning it into a `NookBackdrop` is the chrome's job, and a
/// description never holds a live view, so a theme can always be written out. A custom
/// backdrop view is named by ``custom(id:fallback:)`` and supplied in Swift by the host.
///
/// In a theme file every description is an object with a `kind`:
///
/// ```json
/// { "kind": "framework" }
/// { "kind": "solid", "color": "{color.surface}" }
/// { "kind": "vibrancy", "material": "sidebar", "blending": "behindWindow", "darken": { "dark": 0.52, "light": 0.1 } }
/// { "kind": "liquidGlass", "tint": "accent", "tintStrength": 0.3, "highlight": 0.6,
///   "shading": { "stops": [{ "black": 0.22 }, { "black": 0.09 }], "start": "top", "end": "bottom" } }
/// { "kind": "linearGradient", "stops": ["#101014", "#000000"], "start": "top", "end": "bottom" }
/// { "kind": "radialGradient", "stops": [...], "center": "top", "startRadius": 0, "endRadius": 300 }
/// { "kind": "angularGradient", "stops": [...], "center": "center", "startAngle": 0, "endAngle": 360 }
/// { "kind": "mesh", "width": 2, "height": 2, "points": [[0, 0], [1, 0], [0, 1], [1, 1]], "colors": [...] }
/// { "kind": "custom", "id": "com.example.aurora", "fallback": { "kind": "framework" } }
/// ```
///
/// A kind this version does not know decodes as ``unknown(kind:fallback:)`` rather than
/// failing, so a theme written by a newer build still opens.
public indirect enum NookBackdropDescription: Equatable, Sendable {
    /// The framework's own mapping from the person's surface style and strength.
    case framework
    case solid(NookColorValue)
    case vibrancy(Vibrancy)
    case liquidGlass(LiquidGlass)
    case linearGradient(LinearGradient)
    case radialGradient(RadialGradient)
    case angularGradient(AngularGradient)
    case mesh(Mesh)
    /// A backdrop view the host registers in Swift under `id`. `fallback` is painted when no
    /// view is registered under it.
    case custom(id: String, fallback: NookBackdropDescription?)
    /// A kind this version does not know. Its `fallback` is painted instead, if it has one.
    case unknown(kind: String, fallback: NookBackdropDescription?)

    /// The `NSVisualEffectView` materials a vibrancy backdrop can name.
    public enum Material: String, Codable, Sendable, CaseIterable {
        case titlebar
        case selection
        case menu
        case popover
        case sidebar
        case headerView
        case sheet
        case windowBackground
        case hudWindow
        case fullScreenUI
        case toolTip
        case contentBackground
        case underWindowBackground
        case underPageBackground
    }

    /// What a vibrancy material samples.
    public enum Blending: String, Codable, Sendable, CaseIterable {
        case behindWindow
        case withinWindow
    }

    /// A frosted material with an optional darken over it.
    public struct Vibrancy: Equatable, Sendable {
        public var material: Material
        public var blending: Blending
        /// 0...1 black composited over the material.
        public var darken: NookAdaptiveNumber
        /// Whether the person's backdrop strength multiplies ``darken``.
        public var scalesWithStrength: Bool

        public init(
            material: Material = .sidebar,
            blending: Blending = .behindWindow,
            darken: NookAdaptiveNumber = 0,
            scalesWithStrength: Bool = true
        ) {
            self.material = material
            self.blending = blending
            self.darken = darken
            self.scalesWithStrength = scalesWithStrength
        }
    }

    /// Liquid Glass with an optional tint and a linear legibility shading.
    public struct LiquidGlass: Equatable, Sendable {
        public var tint: NookColorValue?
        public var tintStrength: NookAdaptiveNumber
        public var highlight: Double
        public var shading: LinearGradient?
        /// Whether the person's backdrop strength multiplies ``tintStrength`` and the shading's
        /// opacity.
        public var scalesWithStrength: Bool

        public init(
            tint: NookColorValue? = nil,
            tintStrength: NookAdaptiveNumber = 0.3,
            highlight: Double = 0.6,
            shading: LinearGradient? = nil,
            scalesWithStrength: Bool = true
        ) {
            self.tint = tint
            self.tintStrength = tintStrength
            self.highlight = highlight
            self.shading = shading
            self.scalesWithStrength = scalesWithStrength
        }
    }

    public struct LinearGradient: Equatable, Sendable {
        public var gradient: NookGradientSpec
        public var start: NookUnitPointSpec
        public var end: NookUnitPointSpec

        public init(gradient: NookGradientSpec, start: NookUnitPointSpec = .top, end: NookUnitPointSpec = .bottom) {
            self.gradient = gradient
            self.start = start
            self.end = end
        }
    }

    public struct RadialGradient: Equatable, Sendable {
        public var gradient: NookGradientSpec
        public var center: NookUnitPointSpec
        public var startRadius: Double
        public var endRadius: Double

        public init(
            gradient: NookGradientSpec,
            center: NookUnitPointSpec = .center,
            startRadius: Double = 0,
            endRadius: Double = 300
        ) {
            self.gradient = gradient
            self.center = center
            self.startRadius = startRadius
            self.endRadius = endRadius
        }
    }

    public struct AngularGradient: Equatable, Sendable {
        public var gradient: NookGradientSpec
        public var center: NookUnitPointSpec
        /// Degrees.
        public var startAngle: Double
        /// Degrees.
        public var endAngle: Double

        public init(
            gradient: NookGradientSpec,
            center: NookUnitPointSpec = .center,
            startAngle: Double = 0,
            endAngle: Double = 360
        ) {
            self.gradient = gradient
            self.center = center
            self.startAngle = startAngle
            self.endAngle = endAngle
        }
    }

    /// A mesh gradient: a `width` by `height` grid of points in the unit square, one color each.
    public struct Mesh: Equatable, Sendable {
        public var width: Int
        public var height: Int
        /// `width * height` points, each `[x, y]`.
        public var points: [[Double]]
        /// `width * height` colors.
        public var colors: [NookColorValue]
        public var smoothsColors: Bool

        public init(width: Int, height: Int, points: [[Double]], colors: [NookColorValue], smoothsColors: Bool = true) {
            self.width = width
            self.height = height
            self.points = points
            self.colors = colors
            self.smoothsColors = smoothsColors
        }

        /// Whether the grid is well formed: positive size, `width * height` points of two
        /// coordinates each, and as many colors.
        public var isWellFormed: Bool {
            let count = width * height
            return width > 0 && height > 0 && points.count == count && colors.count == count
                && points.allSatisfy { $0.count == 2 }
        }
    }
}

extension NookBackdropDescription: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        let kind = try container.required(String.self, "kind")
        switch kind {
            case "framework":
                self = .framework
            case "solid":
                self = .solid(try container.required(NookColorValue.self, "color"))
            case "vibrancy":
                self = .vibrancy(
                    Vibrancy(
                        material: try container.optional(Material.self, "material") ?? .sidebar,
                        blending: try container.optional(Blending.self, "blending") ?? .behindWindow,
                        darken: try container.optional(NookAdaptiveNumber.self, "darken") ?? 0,
                        scalesWithStrength: try container.optional(Bool.self, "scalesWithStrength") ?? true
                    )
                )
            case "liquidGlass":
                self = .liquidGlass(
                    LiquidGlass(
                        tint: try container.optional(NookColorValue.self, "tint"),
                        tintStrength: try container.optional(NookAdaptiveNumber.self, "tintStrength") ?? 0.3,
                        highlight: try container.optional(Double.self, "highlight") ?? 0.6,
                        shading: try container.optional(LinearGradient.self, "shading"),
                        scalesWithStrength: try container.optional(Bool.self, "scalesWithStrength") ?? true
                    )
                )
            case "linearGradient":
                self = .linearGradient(try LinearGradient(from: decoder))
            case "radialGradient":
                self = .radialGradient(
                    RadialGradient(
                        gradient: try container.required(NookGradientSpec.self, "stops"),
                        center: try container.optional(NookUnitPointSpec.self, "center") ?? .center,
                        startRadius: try container.optional(Double.self, "startRadius") ?? 0,
                        endRadius: try container.optional(Double.self, "endRadius") ?? 300
                    )
                )
            case "angularGradient":
                self = .angularGradient(
                    AngularGradient(
                        gradient: try container.required(NookGradientSpec.self, "stops"),
                        center: try container.optional(NookUnitPointSpec.self, "center") ?? .center,
                        startAngle: try container.optional(Double.self, "startAngle") ?? 0,
                        endAngle: try container.optional(Double.self, "endAngle") ?? 360
                    )
                )
            case "mesh":
                let mesh = Mesh(
                    width: try container.required(Int.self, "width"),
                    height: try container.required(Int.self, "height"),
                    points: try container.required([[Double]].self, "points"),
                    colors: try container.required([NookColorValue].self, "colors"),
                    smoothsColors: try container.optional(Bool.self, "smoothsColors") ?? true
                )
                guard mesh.isWellFormed else {
                    throw DecodingError.dataCorruptedError(
                        forKey: NookCodingKey("points"),
                        in: container,
                        debugDescription: "a mesh needs width * height points of [x, y] and as many colors"
                    )
                }
                self = .mesh(mesh)
            case "custom":
                self = .custom(
                    id: try container.required(String.self, "id"),
                    fallback: try container.optional(NookBackdropDescription.self, "fallback")
                )
            default:
                self = .unknown(kind: kind, fallback: try container.optional(NookBackdropDescription.self, "fallback"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        switch self {
            case .framework:
                try container.put("framework", "kind")
            case .solid(let color):
                try container.put("solid", "kind")
                try container.put(color, "color")
            case .vibrancy(let vibrancy):
                try container.put("vibrancy", "kind")
                try container.put(vibrancy.material, "material")
                try container.put(vibrancy.blending, "blending")
                try container.put(vibrancy.darken, "darken")
                if !vibrancy.scalesWithStrength { try container.put(false, "scalesWithStrength") }
            case .liquidGlass(let glass):
                try container.put("liquidGlass", "kind")
                try container.putIfPresent(glass.tint, "tint")
                try container.put(glass.tintStrength, "tintStrength")
                try container.put(glass.highlight, "highlight")
                try container.putIfPresent(glass.shading, "shading")
                if !glass.scalesWithStrength { try container.put(false, "scalesWithStrength") }
            case .linearGradient(let gradient):
                try container.put("linearGradient", "kind")
                try gradient.encodeMembers(into: &container)
            case .radialGradient(let gradient):
                try container.put("radialGradient", "kind")
                try container.put(gradient.gradient, "stops")
                try container.put(gradient.center, "center")
                try container.put(gradient.startRadius, "startRadius")
                try container.put(gradient.endRadius, "endRadius")
            case .angularGradient(let gradient):
                try container.put("angularGradient", "kind")
                try container.put(gradient.gradient, "stops")
                try container.put(gradient.center, "center")
                try container.put(gradient.startAngle, "startAngle")
                try container.put(gradient.endAngle, "endAngle")
            case .mesh(let mesh):
                try container.put("mesh", "kind")
                try container.put(mesh.width, "width")
                try container.put(mesh.height, "height")
                try container.put(mesh.points, "points")
                try container.put(mesh.colors, "colors")
                if !mesh.smoothsColors { try container.put(false, "smoothsColors") }
            case .custom(let id, let fallback):
                try container.put("custom", "kind")
                try container.put(id, "id")
                try container.putIfPresent(fallback, "fallback")
            case .unknown(let kind, let fallback):
                try container.put(kind, "kind")
                try container.putIfPresent(fallback, "fallback")
        }
    }
}

extension NookBackdropDescription.LinearGradient: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NookCodingKey.self)
        self.init(
            gradient: try container.required(NookGradientSpec.self, "stops"),
            start: try container.optional(NookUnitPointSpec.self, "start") ?? .top,
            end: try container.optional(NookUnitPointSpec.self, "end") ?? .bottom
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: NookCodingKey.self)
        try encodeMembers(into: &container)
    }

    func encodeMembers(into container: inout KeyedEncodingContainer<NookCodingKey>) throws {
        try container.put(gradient, "stops")
        try container.put(start, "start")
        try container.put(end, "end")
    }
}
