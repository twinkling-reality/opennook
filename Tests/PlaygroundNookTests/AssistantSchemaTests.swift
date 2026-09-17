// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// The generated schema and field guide. The schema is handed to `codex exec --output-schema` and
/// to the OpenAI and Ollama format options, so it has to be JSON Schema a stranger would accept,
/// not just something this app can read back.
final class AssistantSchemaTests: XCTestCase {
    // MARK: - JSON

    func testTheSchemaIsValidJSON() throws {
        let text = AssistantSchema.response.text
        let reparsed = try XCTUnwrap(AssistantJSON(parsing: text), "the schema is not valid JSON")
        XCTAssertEqual(reparsed.text, AssistantJSON(parsing: reparsed.text)?.text)
    }

    func testTheSchemaIsTheSameBytesEveryTime() {
        XCTAssertEqual(AssistantSchema.response.text, AssistantSchema.response.text)
        XCTAssertEqual(AssistantSchema.fieldGuide, AssistantSchema.fieldGuide)
    }

    // MARK: - The response object

    /// The explanation comes first because it is shown while the patch is still arriving.
    func testTheResponseAsksForTheExplanationFirst() throws {
        let properties = try XCTUnwrap(AssistantSchema.response["properties"]?.members)
        XCTAssertEqual(properties.map(\.name), ["explanation", "notReproduced", "patch"])

        let required = try XCTUnwrap(AssistantSchema.response["required"]?.arrayValue)
        XCTAssertEqual(required.compactMap(\.stringValue), ["explanation", "notReproduced", "patch"])
    }

    func testTheResponseTakesNoOtherKeys() {
        XCTAssertEqual(AssistantSchema.response["additionalProperties"], .bool(false))
        XCTAssertEqual(AssistantSchema.response["type"], .string("object"))
    }

    // MARK: - The patch

    func testThePatchCoversAppearanceAndSettings() throws {
        let properties = try XCTUnwrap(AssistantSchema.patch["properties"]?.members)
        XCTAssertEqual(properties.map(\.name), ["appearance", "settings"])
    }

    /// Nothing in the patch is required: it carries only what changed. The exceptions are the
    /// elements of lists, which are written whole.
    func testNothingInThePatchIsRequiredExceptWhatAListElementNeeds() throws {
        var requiring: [String] = []
        collectRequired(in: AssistantSchema.patch, at: "patch", into: &requiring)
        XCTAssertEqual(
            requiring,
            [
                "patch.properties.settings.properties.companions.items",
                "patch.properties.settings.properties.companions.items.properties.items.items",
            ]
        )
    }

    func testACompanionRequiresItsNameAndAnItemItsType() throws {
        let companions = try XCTUnwrap(
            AssistantSchema.patch["properties"]?["settings"]?["properties"]?["companions"]
        )
        XCTAssertEqual(companions["type"], .string("array"))
        let companion = try XCTUnwrap(companions["items"])
        XCTAssertEqual(companion["required"]?.arrayValue?.compactMap(\.stringValue), ["id"])
        XCTAssertEqual(companion["additionalProperties"], .bool(false))

        let items = try XCTUnwrap(companion["properties"]?["items"])
        XCTAssertEqual(items["type"], .string("array"))
        XCTAssertEqual(items["items"]?["required"]?.arrayValue?.compactMap(\.stringValue), ["type"])
        XCTAssertEqual(
            items["items"]?["properties"]?["type"]?["enum"]?.arrayValue?.compactMap(\.stringValue),
            ["button", "label", "keepOpen", "settings"]
        )
    }

    /// A value that is null until set says so in its type, so a schema-enforcing provider accepts
    /// the null that means "use the default".
    func testANullableCompanionValueAcceptsNull() throws {
        let size = try XCTUnwrap(
            AssistantSchema.patch["properties"]?["settings"]?["properties"]?["companions"]?["items"]?["properties"]?[
                "size"
            ]
        )
        XCTAssertEqual(size["type"], .array([.string("string"), .string("null")]))
    }

    /// One leaf in full, so a change to how fields are rendered is visible in a diff rather than
    /// spread across assertions.
    func testANumberLeafCarriesItsBoundsAndDefault() throws {
        let width = try XCTUnwrap(
            AssistantSchema.patch["properties"]?["settings"]?["properties"]?["panel"]?["properties"]?["expandedWidth"]
        )
        XCTAssertEqual(
            width.text,
            """
            {
              "type": "number",
              "minimum": 320,
              "maximum": 760,
              "description": "How wide the panel is once expanded. Default 520."
            }
            """
        )
    }

    func testAChoiceLeafListsItsCases() throws {
        let design = try XCTUnwrap(
            AssistantSchema.patch["properties"]?["settings"]?["properties"]?["theme"]?["properties"]?["fontDesign"]
        )
        XCTAssertEqual(design["type"], .string("string"))
        XCTAssertEqual(
            design["enum"]?.arrayValue?.compactMap(\.stringValue),
            PlaygroundSettings.FontDesign.allCases.map(\.rawValue)
        )
    }

    /// A theme color follows the live palette until it is overridden, so null is a real value for
    /// it and the schema has to allow it.
    func testANullableLeafAllowsNull() throws {
        let accent = try XCTUnwrap(
            AssistantSchema.patch["properties"]?["settings"]?["properties"]?["theme"]?["properties"]?["accent"]
        )
        XCTAssertEqual(accent["type"]?.arrayValue?.compactMap(\.stringValue), ["string", "null"])
        XCTAssertEqual(accent["pattern"], .string("^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"))
    }

    // MARK: - The field guide

    func testTheFieldGuideNamesEveryFieldOnce() {
        let lines = AssistantSchema.fieldGuide.split(separator: "\n", omittingEmptySubsequences: false)
        for field in AssistantSettingsCatalog.fields {
            let matches = lines.filter { $0.hasPrefix("\(field.path.text):") }
            XCTAssertEqual(matches.count, 1, "\(field.path.text) appears \(matches.count) times in the field guide")
        }
    }

    func testTheFieldGuideGroupsFieldsUnderHeadings() {
        for group in AssistantFieldGroup.allCases {
            XCTAssertTrue(
                AssistantSchema.fieldGuide.contains("## \(group.title)"),
                "the field guide has no \(group.title) heading"
            )
        }
    }

    func testAFieldGuideLineCarriesTheTypeTheRangeAndTheDefault() {
        XCTAssertTrue(
            AssistantSchema.fieldGuide.contains(
                "settings.panel.expandedWidth: number 320 to 760 pt, default 520. "
                    + "How wide the panel is once expanded."
            ),
            AssistantSchema.fieldGuide
        )
        XCTAssertTrue(
            AssistantSchema.fieldGuide.contains(
                "settings.theme.accent: color such as \"#1C1C1E\" or null, default null."
            )
        )
    }

    // MARK: - Helpers

    /// The paths of every object in `json` that requires any of its properties.
    private func collectRequired(in json: AssistantJSON, at path: String, into requiring: inout [String]) {
        guard case .object(let members) = json else { return }
        if members.contains(where: { $0.name == "required" }) {
            requiring.append(path)
        }
        for member in members where member.name != "required" && member.name != "enum" {
            collectRequired(in: member.value, at: "\(path).\(member.name)", into: &requiring)
        }
    }
}
