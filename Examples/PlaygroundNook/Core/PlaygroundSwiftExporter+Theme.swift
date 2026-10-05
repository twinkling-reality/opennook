// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookKit
import NookSurface

/// Swift literals for a theme's values: token overrides of every kind and backdrop
/// descriptions. Each literal is the expression a host writes by hand for the same value, so
/// the export reads as ordinary code.
extension PlaygroundSwiftExporter {
    // MARK: - Token overrides

    /// One assignment per token override the theme's color roles do not already write, in id
    /// order.
    static func tokenOverrideLines(_ theme: PlaygroundSettings.Theme) -> [String] {
        var lines: [String] = []
        for id in theme.tokens.ids {
            let role = PlaygroundSettings.Theme.ColorRole(tokenID: id)
            // A role that is set writes its own line, and wins over the override.
            if let role, theme[role] != nil { continue }
            if role == .accent { continue }
            guard let descriptor = NookTokenDescriptor.named(id), let value = theme.tokens.value(for: id) else {
                continue
            }
            let target = "theme.tokens[\(tokenKey(descriptor, role: role))]"
            lines += assignment(target, literal(value))
        }
        // An override of the accent token replaces the accent knob, so it comes after it.
        if theme.accent == nil, let accent = theme.tokens[.accent] {
            lines += assignment("theme.tokens[.accent]", literal(accent))
        }
        return lines
    }

    /// The subscript key for a token: a role's named constant, or the id under its type.
    static func tokenKey(_ descriptor: NookTokenDescriptor, role: PlaygroundSettings.Theme.ColorRole?) -> String {
        if let role { return ".\(role.tokenName)" }
        let type =
            switch descriptor.kind {
                case .color: "NookColorID"
                case .dimension: "NookDimensionID"
                case .font: "NookFontID"
                case .animation: "NookAnimationID"
                case .transition: "NookTransitionID"
                case .sound: "NookSoundID"
                case .shadow: "NookShadowID"
            }
        return "\(type)(\(stringLiteral(descriptor.id)))"
    }

    /// The theme's backdrops, one assignment each.
    static func backdropLines(_ backdrops: NookThemeBackdrops) -> [String] {
        var lines: [String] = []
        let slots: [(String, NookBackdropDescription?)] = [
            ("solid", backdrops.solid),
            ("translucent", backdrops.translucent),
            ("liquidGlass", backdrops.liquidGlass),
        ]
        for (name, description) in slots {
            guard let description else { continue }
            lines += assignment("theme.backdrops.\(name)", literal(description))
        }
        switch backdrops.glassShading {
            case .even?: lines.append("theme.backdrops.glassShading = .even")
            case .notchFade?: lines.append("theme.backdrops.glassShading = .notchFade")
            case nil: break
        }
        return lines
    }

    // MARK: - Values

    static func literal(_ value: NookTokenValue) -> String {
        switch value {
            case .color(let color): literal(color)
            case .dimension(let dimension): literal(dimension)
            case .font(let font): literal(font)
            case .animation(let animation): literal(animation)
            case .transition(let transition): literal(transition)
            case .sound(let sound): literal(sound)
            case .shadow(let shadow): literal(shadow)
        }
    }

    static func literal(_ color: NookColorValue) -> String {
        switch color {
            case .hex(let rgba):
                return stringLiteral(rgba.hex)
            case .srgb(let red, let green, let blue, let opacity):
                return ".srgb(red: \(number(red)), green: \(number(green)), blue: \(number(blue)), "
                    + "opacity: \(number(opacity)))"
            case .white(let opacity):
                return ".white(opacity: \(number(opacity)))"
            case .black(let opacity):
                return ".black(opacity: \(number(opacity)))"
            case .system(let system):
                return ".system(.\(system.rawValue))"
            case .reference(let id, let opacity):
                if color == .accent { return ".accent" }
                guard let opacity else { return stringLiteral("{\(id.rawValue)}") }
                return ".reference(\(stringLiteral(id.rawValue)), opacity: \(number(opacity)))"
            case .adaptive(let adaptive):
                var arguments = ["dark: \(literal(adaptive.dark))", "light: \(literal(adaptive.light))"]
                let variants: [(String, NookColorValue?)] = [
                    ("darkSolid", adaptive.darkSolid),
                    ("lightSolid", adaptive.lightSolid),
                    ("darkReducedTransparency", adaptive.darkReducedTransparency),
                    ("lightReducedTransparency", adaptive.lightReducedTransparency),
                ]
                for (name, variant) in variants {
                    if let variant { arguments.append("\(name): \(literal(variant))") }
                }
                return ".adaptive(NookAdaptiveColor(\(arguments.joined(separator: ", "))))"
            case .hierarchical(let level):
                return ".hierarchical(.\(level.rawValue))"
        }
    }

    static func literal(_ dimension: NookDimension) -> String {
        switch dimension {
            case .points(let value):
                return number(value)
            case .reference(let id, let times):
                if times == 1 { return "NookDimension.token(\(stringLiteral(id.rawValue)))" }
                return "NookDimension.reference(\(stringLiteral(id.rawValue)), times: \(number(times)))"
        }
    }

    static func literal(_ font: NookFontSpec) -> String {
        if let role = font.role, font == NookFontSpec(role: role) {
            return "NookFontSpec.role(\(stringLiteral(role.rawValue)))"
        }
        var arguments: [String] = []
        if let role = font.role { arguments.append("role: \(stringLiteral(role.rawValue))") }
        if let size = font.size { arguments.append("size: \(literal(size))") }
        if let weight = font.weight { arguments.append("weight: .\(weight.rawValue)") }
        if let design = font.design { arguments.append("design: .\(design.rawValue)") }
        if let width = font.width { arguments.append("width: .\(width.rawValue)") }
        if let family = font.family { arguments.append("family: \(stringLiteral(family))") }
        if let digits = font.monospacedDigits { arguments.append("monospacedDigits: \(digits)") }
        return "NookFontSpec(\(arguments.joined(separator: ", ")))"
    }

    static func literal(_ animation: NookAnimationSpec) -> String {
        switch animation {
            case .spring(let response, let damping, let blend):
                let blendArgument = blend == 0 ? "" : ", blendDuration: \(number(blend))"
                return ".spring(response: \(number(response)), dampingFraction: \(number(damping))\(blendArgument))"
            case .springDuration(let duration, let bounce):
                return ".springDuration(duration: \(number(duration)), bounce: \(number(bounce)))"
            case .preset(let preset, let duration, let extraBounce):
                let bounce = extraBounce == 0 ? "" : ", extraBounce: \(number(extraBounce))"
                return ".preset(.\(preset.rawValue), duration: \(number(duration))\(bounce))"
            case .curve(let curve, let duration):
                return ".curve(.\(curve.rawValue), duration: \(number(duration)))"
            case .bezier(let x1, let y1, let x2, let y2, let duration):
                return ".bezier(x1: \(number(x1)), y1: \(number(y1)), x2: \(number(x2)), y2: \(number(y2)), "
                    + "duration: \(number(duration)))"
            case .reference(let id):
                return ".reference(\(stringLiteral(id.rawValue)))"
        }
    }

    static func literal(_ transition: NookContentTransitionSpec) -> String {
        let fallback = NookContentTransitionSpec()
        var arguments: [String] = []
        if transition.opacity != fallback.opacity { arguments.append("opacity: \(number(transition.opacity))") }
        if transition.blur != fallback.blur { arguments.append("blur: \(number(transition.blur))") }
        if transition.scaleX != fallback.scaleX { arguments.append("scaleX: \(number(transition.scaleX))") }
        if transition.scaleY != fallback.scaleY { arguments.append("scaleY: \(number(transition.scaleY))") }
        if transition.anchor != fallback.anchor { arguments.append("anchor: \(literal(transition.anchor))") }
        if transition.offsetX != fallback.offsetX { arguments.append("offsetX: \(number(transition.offsetX))") }
        if transition.offsetY != fallback.offsetY { arguments.append("offsetY: \(number(transition.offsetY))") }
        if let animation = transition.animation { arguments.append("animation: \(literal(animation))") }
        return "NookContentTransitionSpec(\(arguments.joined(separator: ", ")))"
    }

    static func literal(_ sound: NookSoundSpec) -> String {
        let volume = sound.volume.map { ", volume: \(number($0))" } ?? ""
        switch sound.source {
            case .system(let name):
                return "NookSoundSpec.system(\(stringLiteral(name))\(volume))"
            case .resource(let name):
                return "NookSoundSpec(.resource(\(stringLiteral(name)))\(volume))"
            case .file(let url):
                let path = url.isFileURL ? url.path : url.absoluteString
                return "NookSoundSpec(.file(URL(fileURLWithPath: \(stringLiteral(path))))\(volume))"
        }
    }

    static func literal(_ shadow: NookShadowSpec) -> String {
        let fallback = NookShadowSpec()
        var arguments: [String] = []
        if shadow.color != fallback.color { arguments.append("color: \(literal(shadow.color))") }
        if shadow.radius != fallback.radius { arguments.append("radius: \(number(shadow.radius))") }
        if shadow.x != fallback.x { arguments.append("x: \(number(shadow.x))") }
        if shadow.y != fallback.y { arguments.append("y: \(number(shadow.y))") }
        return "NookShadowSpec(\(arguments.joined(separator: ", ")))"
    }

    static func literal(_ point: NookUnitPointSpec) -> String {
        if let name = Self.unitPointNames.first(where: { $0.point == point })?.name {
            return ".\(name)"
        }
        return "NookUnitPointSpec(x: \(number(point.x)), y: \(number(point.y)))"
    }

    private static let unitPointNames: [(name: String, point: NookUnitPointSpec)] = [
        ("center", .center), ("leading", .leading), ("trailing", .trailing), ("top", .top), ("bottom", .bottom),
        ("topLeading", .topLeading), ("topTrailing", .topTrailing), ("bottomLeading", .bottomLeading),
        ("bottomTrailing", .bottomTrailing),
    ]

    static func literal(_ gradient: NookGradientSpec) -> String {
        if gradient.stops.allSatisfy({ $0.location == nil }) {
            return "NookGradientSpec(colors: [\(gradient.stops.map { literal($0.color) }.joined(separator: ", "))])"
        }
        let stops = gradient.stops.map { stop in
            let location = stop.location.map { ", location: \(number($0))" } ?? ""
            return ".init(color: \(literal(stop.color))\(location))"
        }
        return "NookGradientSpec(stops: [\(stops.joined(separator: ", "))])"
    }

    static func literal(_ number: NookAdaptiveNumber) -> String {
        number.dark == number.light
            ? self.number(number.dark)
            : "NookAdaptiveNumber(dark: \(self.number(number.dark)), light: \(self.number(number.light)))"
    }

    static func literal(_ backdrop: NookBackdropDescription) -> String {
        switch backdrop {
            case .framework:
                return ".framework"
            case .solid(let color):
                return ".solid(\(literal(color)))"
            case .vibrancy(let vibrancy):
                let fallback = NookBackdropDescription.Vibrancy()
                var arguments: [String] = []
                if vibrancy.material != fallback.material { arguments.append("material: .\(vibrancy.material.rawValue)") }
                if vibrancy.blending != fallback.blending { arguments.append("blending: .\(vibrancy.blending.rawValue)") }
                if vibrancy.darken != fallback.darken { arguments.append("darken: \(literal(vibrancy.darken))") }
                if !vibrancy.scalesWithStrength { arguments.append("scalesWithStrength: false") }
                if let color = vibrancy.darkenColor { arguments.append("darkenColor: \(literal(color))") }
                return ".vibrancy(.init(\(arguments.joined(separator: ", "))))"
            case .liquidGlass(let glass):
                let fallback = NookBackdropDescription.LiquidGlass()
                var arguments: [String] = []
                if let tint = glass.tint { arguments.append("tint: \(literal(tint))") }
                if glass.tintStrength != fallback.tintStrength {
                    arguments.append("tintStrength: \(literal(glass.tintStrength))")
                }
                if glass.highlight != fallback.highlight { arguments.append("highlight: \(number(glass.highlight))") }
                if let shading = glass.shading { arguments.append("shading: \(linearLiteral(shading))") }
                if !glass.scalesWithStrength { arguments.append("scalesWithStrength: false") }
                if let variant = glass.variant { arguments.append("variant: .\(variant.rawValue)") }
                if let material = glass.fallbackMaterial { arguments.append("fallbackMaterial: .\(material.rawValue)") }
                if let color = glass.highlightColor { arguments.append("highlightColor: \(literal(color))") }
                if let width = glass.rimWidth { arguments.append("rimWidth: \(number(width))") }
                return ".liquidGlass(.init(\(arguments.joined(separator: ", "))))"
            case .linearGradient(let gradient):
                return ".linearGradient(\(linearLiteral(gradient)))"
            case .radialGradient(let gradient):
                return ".radialGradient(.init(gradient: \(literal(gradient.gradient)), center: \(literal(gradient.center)), "
                    + "startRadius: \(number(gradient.startRadius)), endRadius: \(number(gradient.endRadius))))"
            case .ellipticalGradient(let gradient):
                return ".ellipticalGradient(.init(gradient: \(literal(gradient.gradient)), "
                    + "center: \(literal(gradient.center)), startRadius: \(number(gradient.startRadius)), "
                    + "endRadius: \(number(gradient.endRadius))))"
            case .angularGradient(let gradient):
                return ".angularGradient(.init(gradient: \(literal(gradient.gradient)), "
                    + "center: \(literal(gradient.center)), startAngle: \(number(gradient.startAngle)), "
                    + "endAngle: \(number(gradient.endAngle))))"
            case .mesh(let mesh):
                let points = mesh.points.map { "[\($0.map { number($0) }.joined(separator: ", "))]" }
                var arguments = [
                    "width: \(mesh.width)",
                    "height: \(mesh.height)",
                    "points: [\(points.joined(separator: ", "))]",
                    "colors: [\(mesh.colors.map { literal($0) }.joined(separator: ", "))]",
                ]
                if !mesh.smoothsColors { arguments.append("smoothsColors: false") }
                return ".mesh(.init(\(arguments.joined(separator: ", "))))"
            case .custom(let id, let fallback):
                let fallbackLiteral = fallback.map { literal($0) } ?? "nil"
                return ".custom(id: \(stringLiteral(id)), fallback: \(fallbackLiteral))"
            case .unknown(let kind, let fallback):
                let fallbackLiteral = fallback.map { literal($0) } ?? "nil"
                return ".unknown(kind: \(stringLiteral(kind)), fallback: \(fallbackLiteral))"
        }
    }

    private static func linearLiteral(_ gradient: NookBackdropDescription.LinearGradient) -> String {
        ".init(gradient: \(literal(gradient.gradient)), start: \(literal(gradient.start)), end: \(literal(gradient.end)))"
    }

    // MARK: - Layout

    /// `target = value` on one line, or with the value's outermost call broken one argument per
    /// line when that is too long.
    static func assignment(_ target: String, _ value: String) -> [String] {
        let line = "\(target) = \(value)"
        guard line.count > maximumLineLength, let parts = splitCall(value) else { return [line] }
        return ["\(target) = \(parts.head)("] + argumentLines(parts.arguments, indent: 4) + [")\(parts.tail)"]
    }

    /// `head(a, b, c)tail` split into its head, its top-level arguments, and what follows the
    /// closing parenthesis, or `nil` when `expression` is not a call with arguments. A call
    /// whose single argument is itself a call, like `.mesh(.init(...))`, is split inside the
    /// inner call.
    static func splitCall(_ expression: String) -> (head: String, arguments: [String], tail: String)? {
        let characters = Array(expression)
        guard let open = characters.firstIndex(of: "(") else { return nil }
        var depth = 0
        var inString = false
        var arguments: [String] = []
        var current = ""
        var close: Int?
        var index = open
        while index < characters.count {
            let character = characters[index]
            if inString {
                current.append(character)
                if character == "\\", index + 1 < characters.count {
                    current.append(characters[index + 1])
                    index += 2
                    continue
                }
                if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
                current.append(character)
            } else if character == "(" || character == "[" {
                if depth > 0 { current.append(character) }
                depth += 1
            } else if character == ")" || character == "]" {
                depth -= 1
                if depth == 0 {
                    close = index
                    break
                }
                current.append(character)
            } else if character == ",", depth == 1 {
                arguments.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        guard let close else { return nil }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { arguments.append(last) }
        guard !arguments.isEmpty else { return nil }
        var head = String(characters[..<open])
        var tail = String(characters[(close + 1)...])
        if arguments.count == 1, let inner = splitCall(arguments[0]) {
            head += "(" + inner.head
            tail = inner.tail + ")" + tail
            return (head, inner.arguments, tail)
        }
        return (head, arguments, tail)
    }
}
