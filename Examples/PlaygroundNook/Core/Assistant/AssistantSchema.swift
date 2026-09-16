// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// The JSON Schema the model answers against, and the plain-text field guide it reads when the
/// provider cannot enforce a schema. Both are generated from ``AssistantSettingsCatalog``, so a
/// new setting reaches the model without anything here being edited.
///
/// The response is one object with its members in a fixed order: the explanation first, then what
/// could not be reproduced, then the patch. Order matters because the explanation is shown while
/// the rest of the answer is still arriving, which is what makes a slow local model or a CLI feel
/// alive rather than hung.
///
/// Providers that take a schema (`codex exec --output-schema`, the OpenAI Responses text format,
/// Ollama's `format`, an Anthropic tool's `input_schema`) get the field summaries as `description`
/// strings inside ``response``, so those providers do not also need ``fieldGuide`` in the prompt.
public enum AssistantSchema {
    /// The member names of the response, in the order the model is asked to write them.
    public enum ResponseKey: String, CaseIterable, Sendable {
        case explanation
        case notReproduced
        case patch
    }

    /// The schema for the whole response.
    public static let response: AssistantJSON = .object([
        ("$schema", .string("https://json-schema.org/draft/2020-12/schema")),
        ("title", .string("PlaygroundNookChange")),
        ("type", .string("object")),
        (
            "properties",
            .object([
                (
                    ResponseKey.explanation.rawValue,
                    .object([
                        ("type", .string("string")),
                        (
                            "description",
                            .string(
                                "One or two plain sentences saying what you changed and why. "
                                    + "No markdown, no lists, no code."
                            )
                        ),
                    ])
                ),
                (
                    ResponseKey.notReproduced.rawValue,
                    .object([
                        ("type", .string("array")),
                        ("items", .object([("type", .string("string"))])),
                        (
                            "description",
                            .string(
                                "Anything asked for that these settings cannot express, one short "
                                    + "phrase each, such as a custom content layout or a font that is not one of the "
                                    + "four system designs. Empty when everything was reproduced."
                            )
                        ),
                    ])
                ),
                (ResponseKey.patch.rawValue, patch),
            ])
        ),
        ("required", .array(ResponseKey.allCases.map { .string($0.rawValue) })),
        ("additionalProperties", .bool(false)),
    ])

    /// The schema for the patch alone: the shape of a preset, with every field optional.
    public static let patch: AssistantJSON = {
        var root = SchemaNode()
        for field in AssistantSettingsCatalog.fields {
            root.insert(field, at: field.path.components[...])
        }
        guard case .object(var members) = root.schema else { return root.schema }
        members.append(
            AssistantJSON.Member(
                "description",
                .string("Only the fields you are changing. Leave every other field out.")
            )
        )
        return .object(members)
    }()

    /// Every field as one line, grouped as the playground groups them. Used by providers that
    /// cannot take a schema, and by the request inspector so a person can read exactly what the
    /// model was told.
    public static let fieldGuide: String = {
        var lines: [String] = []
        for group in AssistantFieldGroup.allCases {
            let fields = AssistantSettingsCatalog.fields(in: group)
            guard !fields.isEmpty else { continue }
            lines.append("")
            lines.append("## \(group.title)")
            for field in fields {
                var line = "\(field.path.text): \(field.typeDescription)"
                if field.isNullable {
                    line += " or null"
                }
                line += ", default \(field.defaultValue.text). \(field.summary)"
                lines.append(line)
            }
        }
        return lines.dropFirst().joined(separator: "\n")
    }()
}

// MARK: - Building the patch schema

/// A node of the tree the flat catalog is folded into on the way to a nested schema. Members keep
/// the order the catalog lists them in, so the schema is the same bytes every run.
private struct SchemaNode {
    private indirect enum Content {
        case fields([(name: String, node: SchemaNode)])
        /// A list whose elements all have the shape of the node.
        case list(SchemaNode)
        case leaf(AssistantField)
    }

    private var content = Content.fields([])

    mutating func insert(_ field: AssistantField, at components: ArraySlice<AssistantFieldPath.Component>) {
        guard let first = components.first else {
            content = .leaf(field)
            return
        }
        let rest = components.dropFirst()
        switch first {
            case .eachElement:
                var element: SchemaNode
                if case .list(let existing) = content {
                    element = existing
                } else {
                    element = SchemaNode()
                }
                element.insert(field, at: rest)
                content = .list(element)
            case .key(let name):
                var members: [(name: String, node: SchemaNode)]
                if case .fields(let existing) = content {
                    members = existing
                } else {
                    members = []
                }
                if let index = members.firstIndex(where: { $0.name == name }) {
                    members[index].node.insert(field, at: rest)
                } else {
                    var node = SchemaNode()
                    node.insert(field, at: rest)
                    members.append((name, node))
                }
                content = .fields(members)
        }
    }

    var schema: AssistantJSON {
        switch content {
            case .leaf(let field):
                return Self.leafSchema(field)
            case .list(let element):
                return .object([
                    ("type", .string("array")),
                    ("items", element.schema),
                ])
            case .fields(let members):
                var properties: [AssistantJSON.Member] = []
                for member in members {
                    properties.append(AssistantJSON.Member(member.name, member.node.schema))
                }
                var object: [AssistantJSON.Member] = [
                    AssistantJSON.Member("type", .string("object")),
                    AssistantJSON.Member("properties", .object(properties)),
                ]
                // A companion is only meaningful with a name and a kind, and listing companions
                // replaces the whole list, so those two are the one place the schema requires
                // anything.
                let names = members.map(\.name)
                if names.contains("id"), names.contains("kind") {
                    object.append(
                        AssistantJSON.Member("required", .array([.string("id"), .string("kind")]))
                    )
                }
                object.append(AssistantJSON.Member("additionalProperties", .bool(false)))
                return .object(object)
        }
    }

    private static func leafSchema(_ field: AssistantField) -> AssistantJSON {
        var members: [AssistantJSON.Member] = []
        var description = field.summary

        switch field.kind {
            case .number(let minimum, let maximum, _):
                members.append(AssistantJSON.Member("type", Self.typeName("number", nullable: field.isNullable)))
                if let minimum {
                    members.append(AssistantJSON.Member("minimum", .number(minimum)))
                }
                if let maximum {
                    members.append(AssistantJSON.Member("maximum", .number(maximum)))
                }
            case .flag:
                members.append(AssistantJSON.Member("type", Self.typeName("boolean", nullable: field.isNullable)))
            case .text:
                members.append(AssistantJSON.Member("type", Self.typeName("string", nullable: field.isNullable)))
            case .color:
                members.append(AssistantJSON.Member("type", Self.typeName("string", nullable: field.isNullable)))
                members.append(
                    AssistantJSON.Member("pattern", .string("^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"))
                )
            case .choice(let choices):
                members.append(AssistantJSON.Member("type", Self.typeName("string", nullable: field.isNullable)))
                members.append(AssistantJSON.Member("enum", .array(choices.map { .string($0) })))
        }

        description += " Default \(field.defaultValue.text)."
        members.append(AssistantJSON.Member("description", .string(description)))
        return .object(members)
    }

    private static func typeName(_ name: String, nullable: Bool) -> AssistantJSON {
        nullable ? .array([.string(name), .string("null")]) : .string(name)
    }
}
