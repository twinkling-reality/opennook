// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Where one value sits in a ``PlaygroundPreset``, as the keys of the JSON it encodes to:
/// `settings.panel.expandedWidth`, or `settings.companions[].outline` for a value that every
/// element of a list carries.
///
/// The path is text rather than a key path because key path literals cannot be held in a
/// `Sendable` table, and because the model, the JSON schema, the patch merge, and the decoder's
/// own error messages all speak in these same dotted names. One vocabulary end to end means the
/// path in a model's answer, in a repair message, and in a proposal row is literally the same
/// string.
public struct AssistantFieldPath: Sendable, Hashable {
    public enum Component: Sendable, Hashable {
        case key(String)
        /// Every element of the list named by the component before it.
        case eachElement
    }

    public let components: [Component]

    public init(components: [Component]) {
        self.components = components
    }

    /// Reads a dotted path, where `[]` marks a list: `settings.companions[].id`.
    public init(_ text: String) {
        var components: [Component] = []
        for piece in text.split(separator: ".") {
            var name = piece
            var isList = false
            if name.hasSuffix("[]") {
                name = name.dropLast(2)
                isList = true
            }
            if !name.isEmpty {
                components.append(.key(String(name)))
            }
            if isList {
                components.append(.eachElement)
            }
        }
        self.init(components: components)
    }

    public var text: String {
        var text = ""
        for component in components {
            switch component {
                case .key(let name):
                    text += text.isEmpty ? name : ".\(name)"
                case .eachElement:
                    text += "[]"
            }
        }
        return text
    }

    /// The path with its first component dropped, or `nil` at the end of the path. Used to walk
    /// a path into a nested structure one level at a time.
    public var rest: AssistantFieldPath? {
        components.isEmpty ? nil : AssistantFieldPath(components: Array(components.dropFirst()))
    }

    public var first: Component? {
        components.first
    }
}

/// One value the assistant is allowed to change, described well enough to generate both the JSON
/// schema the model answers against and the one-line field guide it reads.
///
/// Everything here is derived from ``PlaygroundSettings`` and `NookAppearancePreferences` in
/// ``AssistantSettingsCatalog``, including the defaults, which are read from the real model
/// rather than restated. `AssistantCatalogCoverageTests` fails when a settings field has no entry.
public struct AssistantField: Sendable, Equatable, Identifiable {
    /// What kind of value it is, and what a valid one looks like.
    public enum Kind: Sendable, Equatable {
        /// A number, with the bounds `PlaygroundSettings.normalized()` would clamp it to.
        case number(minimum: Double?, maximum: Double?, unit: Unit)
        case flag
        case text
        /// `#RRGGBB` or `#RRGGBBAA`, as ``PlaygroundColor`` stores it.
        case color
        /// One of a fixed set of names, in the order the playground lists them.
        case choice([String])
    }

    /// What a number counts, so the guide can say `pt` rather than leave it to be guessed.
    public enum Unit: Sendable, Equatable {
        case points
        case seconds
        /// Zero to one.
        case fraction
        case none

        var suffix: String {
            switch self {
                case .points: " pt"
                case .seconds: " s"
                case .fraction, .none: ""
            }
        }
    }

    public let path: AssistantFieldPath
    /// Which part of the playground it belongs to, used to group a proposal.
    public let group: AssistantFieldGroup
    public let kind: Kind
    /// One line, in plain words, saying what the value does. This is what the model reads.
    public let summary: String
    /// The value a preset has when it does not mention this field, as JSON.
    public let defaultValue: AssistantJSON
    /// Whether `null` is a legal value, which for a theme color means "follow the live palette".
    public let isNullable: Bool

    public init(
        path: AssistantFieldPath,
        group: AssistantFieldGroup,
        kind: Kind,
        summary: String,
        defaultValue: AssistantJSON,
        isNullable: Bool = false
    ) {
        self.path = path
        self.group = group
        self.kind = kind
        self.summary = summary
        self.defaultValue = defaultValue
        self.isNullable = isNullable
    }

    public var id: String { path.text }

    /// The type name the field guide prints: `number`, `true or false`, `text`, `color`, or the
    /// choices themselves.
    public var typeDescription: String {
        switch kind {
            case .number(let minimum, let maximum, let unit):
                var text = "number"
                switch (minimum, maximum) {
                    case (let low?, let high?):
                        text += " \(AssistantJSON.numberText(low)) to \(AssistantJSON.numberText(high))"
                    case (let low?, nil):
                        text += " \(AssistantJSON.numberText(low)) or more"
                    case (nil, let high?):
                        text += " up to \(AssistantJSON.numberText(high))"
                    case (nil, nil):
                        break
                }
                return text + unit.suffix
            case .flag:
                return "true or false"
            case .text:
                return "text"
            case .color:
                return "color such as \"#1C1C1E\""
            case .choice(let choices):
                return choices.map { "\"\($0)\"" }.joined(separator: " | ")
        }
    }
}
