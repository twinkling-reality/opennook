// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation
import NookKit

/// The theme tokens the assistant may override, read from the framework's token registry
/// (`NookTokenDescriptor.all`) rather than listed here, so a token the framework adds reaches the
/// model with nothing in the playground edited.
///
/// Tokens are one catalog field, `settings.theme.tokens`, holding an object keyed by token id.
/// Ids are dotted (`banner.cornerRadius`), so they cannot be catalog paths of their own; the
/// schema lists each id as a property of that object instead, and ``AssistantPatch`` rejects an
/// id the registry does not define.
enum AssistantTokenCatalog {
    /// The backdrop kinds a theme file writes, for the schema of a backdrop field.
    static let backdropKinds = [
        "framework", "solid", "vibrancy", "liquidGlass", "linearGradient", "radialGradient", "ellipticalGradient",
        "angularGradient", "mesh", "custom",
    ]

    /// How a value of each kind is written, in the words of a theme file.
    static func valueForm(_ kind: NookTokenDescriptor.Kind) -> String {
        switch kind {
            case .color:
                "\"#RRGGBB\" or \"#RRGGBBAA\", \"accent\", \"{another.color.id}\", {\"white\": 0.9}, "
                    + "{\"black\": 0.5}, or {\"dark\": color, \"light\": color}"
            case .dimension:
                "a number at scale 1 (points, an opacity 0 to 1, or seconds), or \"{another.number.id}\""
            case .font:
                "{\"size\": 11, \"weight\": \"semibold\", \"design\": \"rounded\", \"width\": \"condensed\"} "
                    + "or \"{type.body}\""
            case .animation:
                "{\"response\": 0.34, \"dampingFraction\": 0.86}, {\"curve\": \"easeOut\", \"duration\": 0.18}, "
                    + "or \"{spring.default}\""
            case .transition:
                "{\"opacity\": 0, \"blur\": 6, \"scale\": 0.97, \"anchor\": \"top\", \"animation\": animation}"
            case .sound:
                "{\"system\": \"Pop\", \"volume\": 0.6}, a macOS system sound by name"
            case .shadow:
                "{\"color\": color, \"radius\": 8, \"x\": 0, \"y\": 3}"
        }
    }

    /// The JSON types a value of `kind` may take in a patch, `null` included, which removes the
    /// override.
    private static func types(_ kind: NookTokenDescriptor.Kind) -> [String] {
        switch kind {
            case .color, .font, .animation: ["string", "object", "null"]
            case .dimension: ["number", "string", "object", "null"]
            case .transition, .sound, .shadow: ["object", "null"]
        }
    }

    /// `descriptor`'s default as a theme file writes it, or `null` for a token that defaults to
    /// none.
    static func defaultJSON(_ descriptor: NookTokenDescriptor) -> AssistantJSON {
        var tokens = NookThemeTokens()
        guard tokens.setValue(descriptor.defaultValue, for: descriptor.id), descriptor.defaultValue != nil,
            let data = try? JSONEncoder().encode(tokens),
            let json = AssistantJSON(parsing: data)
        else { return .null }
        return json[descriptor.id] ?? .null
    }

    /// The schema of the tokens object: one property per token id, typed by its kind.
    static let schemaMembers: [AssistantJSON.Member] = {
        var properties: [AssistantJSON.Member] = []
        for descriptor in NookTokenDescriptor.all {
            let description = "A \(descriptor.kind.rawValue). Default \(defaultJSON(descriptor).compactText)."
            properties.append(
                AssistantJSON.Member(
                    descriptor.id,
                    .object([
                        ("type", .array(types(descriptor.kind).map { .string($0) })),
                        ("description", .string(description)),
                    ])
                )
            )
        }
        return [
            AssistantJSON.Member("type", .string("object")),
            AssistantJSON.Member("properties", .object(properties)),
            AssistantJSON.Member("additionalProperties", .bool(false)),
        ]
    }()

    /// The schema of a backdrop field.
    static let backdropSchemaMembers: [AssistantJSON.Member] = [
        AssistantJSON.Member("type", .array([.string("object"), .string("null")])),
        AssistantJSON.Member(
            "properties",
            .object([("kind", .object([("type", .string("string")), ("enum", .array(backdropKinds.map { .string($0) }))]))])
        ),
    ]

    /// The token ids, one line per kind, for the field guide: how a value of that kind is
    /// written, then every id of it.
    static let guideLines: [String] = NookTokenDescriptor.Kind.allCases.compactMap { kind in
        let ids = NookTokenDescriptor.all.filter { $0.kind == kind }.map(\.id)
        guard !ids.isEmpty else { return nil }
        return "  \(kind.rawValue) tokens, written \(valueForm(kind)): \(ids.joined(separator: ", "))."
    }

    /// A one-line form of the backdrop kinds, for a backdrop field's summary.
    static let backdropForm =
        "Written as a theme file writes a backdrop: {\"kind\": \"linearGradient\", \"stops\": [\"#101014\", \"#000000\"], "
        + "\"start\": \"top\", \"end\": \"bottom\"}, {\"kind\": \"solid\", \"color\": \"#1C1C1E\"}, "
        + "{\"kind\": \"liquidGlass\", \"variant\": \"clear\", \"tint\": \"accent\", \"tintStrength\": 0.3}, "
        + "radialGradient (center, startRadius, endRadius), angularGradient (center, startAngle, endAngle), "
        + "mesh (width, height, points, colors), or framework; null is the framework's own."
}
