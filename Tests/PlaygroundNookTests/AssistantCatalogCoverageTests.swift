// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import NookSurface
import XCTest

@testable import PlaygroundNookCore

/// The assistant's field catalog against the preset it describes. These are the tests that make
/// the catalog safe to trust: a setting added to ``PlaygroundSettings`` and forgotten here fails
/// ``testEveryPresetFieldIsInTheCatalog``, rather than quietly becoming a value the assistant can
/// never change.
final class AssistantCatalogCoverageTests: XCTestCase {
    /// Keys a preset encodes that are deliberately not the assistant's to change.
    ///
    /// Each one is listed with its reason, so leaving a new field out is a decision someone has to
    /// write down rather than an oversight.
    private static let excludedPaths: Set<String> = [
        // The format stamp and version are the coder's, not a setting.
        "format",
        "version",
        // A working aid rather than part of a look. `PlaygroundPreset` clears it on the way in and
        // out, so a patch could not make it stick anyway.
        "appearance.keepNookOpen",
    ]

    // MARK: - Coverage

    func testEveryPresetFieldIsInTheCatalog() throws {
        let encoded = try PlaygroundPresetCoder.encode(Self.fullyPopulatedPreset)
        let json = try XCTUnwrap(AssistantJSON(parsing: encoded))
        let presetPaths = Self.leafPaths(of: json).subtracting(Self.excludedPaths)
        let catalogPaths = Set(AssistantSettingsCatalog.fields.map(\.path.text))

        let missing = presetPaths.subtracting(catalogPaths).sorted()
        XCTAssertEqual(
            missing,
            [],
            "These preset fields have no entry in AssistantSettingsCatalog, so the assistant "
                + "cannot change them. Add one, or list the path in excludedPaths with a reason."
        )
    }

    func testTheCatalogDescribesNothingThatIsNotInAPreset() throws {
        let encoded = try PlaygroundPresetCoder.encode(Self.fullyPopulatedPreset)
        let json = try XCTUnwrap(AssistantJSON(parsing: encoded))
        let presetPaths = Self.leafPaths(of: json)
        let catalogPaths = Set(AssistantSettingsCatalog.fields.map(\.path.text))

        let unknown = catalogPaths.subtracting(presetPaths).sorted()
        XCTAssertEqual(unknown, [], "These catalog entries name fields a preset does not have.")
    }

    /// Every choice field offers exactly the cases the type has, so a case added to an enum in the
    /// settings model reaches the model.
    func testChoiceFieldsOfferEveryCase() throws {
        func assertChoices(_ path: String, _ expected: [String]) throws {
            let field = try XCTUnwrap(
                AssistantSettingsCatalog.field(at: AssistantFieldPath(path)),
                "\(path) is not in the catalog"
            )
            guard case .choice(let choices) = field.kind else {
                return XCTFail("\(path) is not a choice field")
            }
            XCTAssertEqual(choices, expected, "\(path) does not offer every case")
        }

        try assertChoices("appearance.chromePalette", NookChromePalette.allCases.map(\.rawValue))
        try assertChoices("appearance.surfaceStyle", NookSurfaceStyle.allCases.map(\.rawValue))
        try assertChoices("appearance.presentation", NookPresentation.allCases.map(\.rawValue))
        try assertChoices("appearance.accentPreset", NookAccentPreset.allCases.map(\.rawValue))
        try assertChoices("settings.theme.fontDesign", PlaygroundSettings.FontDesign.allCases.map(\.rawValue))
        try assertChoices("settings.topBar.width", PlaygroundSettings.TopBar.Width.allCases.map(\.rawValue))
        try assertChoices(
            "settings.topBar.notchClearance",
            PlaygroundSettings.TopBar.NotchClearance.allCases.map(\.rawValue)
        )
        try assertChoices(
            "settings.typography.headerIcon.weight",
            PlaygroundSettings.FontWeight.allCases.map(\.rawValue)
        )
        try assertChoices(
            "settings.companionDefaults.size",
            PlaygroundSettings.Companion.Size.allCases.map(\.rawValue)
        )
        try assertChoices(
            "settings.companionDefaults.presence",
            PlaygroundSettings.Companion.Presence.allCases.map(\.rawValue)
        )
        try assertChoices(
            "settings.companionDefaults.hover",
            PlaygroundSettings.Companion.Hover.allCases.map(\.rawValue)
        )
        try assertChoices("settings.companions[].layout", PlaygroundSettings.Companion.Layout.allCases.map(\.rawValue))
        try assertChoices("settings.companions[].size", PlaygroundSettings.Companion.Size.allCases.map(\.rawValue))
        try assertChoices(
            "settings.companions[].presence",
            PlaygroundSettings.Companion.Presence.allCases.map(\.rawValue)
        )
        try assertChoices("settings.companions[].hover", PlaygroundSettings.Companion.Hover.allCases.map(\.rawValue))
        try assertChoices(
            "settings.companions[].rowAlignment",
            PlaygroundSettings.Companion.AnchorAlignment.allCases.map(\.rawValue)
        )
        try assertChoices("settings.companions[].items[].type", PlaygroundSettings.Item.Kind.allCases.map(\.rawValue))
        try assertChoices("settings.companions[].items[].fill", PlaygroundSettings.Item.Fill.allCases.map(\.rawValue))
        try assertChoices("settings.companions[].items[].size", PlaygroundSettings.Item.Size.allCases.map(\.rawValue))
        try assertChoices(
            "settings.companions[].items[].action",
            PlaygroundSettings.Item.Action.allCases.map(\.rawValue)
        )
        try assertChoices("settings.companions[].anchor", PlaygroundSettings.Companion.Anchor.allCases.map(\.rawValue))
        try assertChoices(
            "settings.companions[].alignment",
            PlaygroundSettings.Companion.AnchorAlignment.allCases.map(\.rawValue)
        )
        try assertChoices(
            "settings.companions[].visibility",
            PlaygroundSettings.Companion.Visibility.allCases.map(\.rawValue)
        )
        try assertChoices(
            "settings.companions[].outline",
            PlaygroundSettings.Companion.Outline.allCases.map(\.rawValue)
        )
        try assertChoices(
            "settings.companions[].backdrop",
            PlaygroundSettings.Companion.Backdrop.allCases.map(\.rawValue)
        )
    }

    /// Every typography and motion role gets both of its fields, so a role added to either group
    /// cannot be half described.
    func testEveryTypographyAndMotionRoleIsDescribed() {
        for role in PlaygroundSettings.Typography.Role.allCases {
            for leaf in ["size", "weight"] {
                let path = AssistantFieldPath("settings.typography.\(role.rawValue).\(leaf)")
                XCTAssertNotNil(AssistantSettingsCatalog.field(at: path), "\(path.text) is missing")
            }
        }
        for role in PlaygroundSettings.Motion.Role.allCases {
            for leaf in ["response", "dampingFraction"] {
                let path = AssistantFieldPath("settings.motion.\(role.rawValue).\(leaf)")
                XCTAssertNotNil(AssistantSettingsCatalog.field(at: path), "\(path.text) is missing")
            }
        }
    }

    /// The groups the catalog sorts fields into are the window's own pages, so a proposal can be
    /// grouped the way the controls are. `PlaygroundPage` lives in the app target, so this checks
    /// the titles rather than the type.
    func testEveryGroupIsUsedAndTitled() {
        for group in AssistantFieldGroup.allCases {
            XCTAssertFalse(
                AssistantSettingsCatalog.fields(in: group).isEmpty,
                "the \(group.rawValue) group has no fields"
            )
            XCTAssertFalse(group.title.isEmpty)
        }
    }

    // MARK: - Descriptions

    func testEveryFieldHasAOneLineSummaryEndingInAPeriod() {
        for field in AssistantSettingsCatalog.fields {
            XCTAssertFalse(field.summary.isEmpty, "\(field.path.text) has no summary")
            XCTAssertFalse(field.summary.contains("\n"), "\(field.path.text) has a multi-line summary")
            XCTAssertTrue(field.summary.hasSuffix("."), "\(field.path.text) does not end in a period")
        }
    }

    func testEveryPathRoundTripsThroughItsText() {
        for field in AssistantSettingsCatalog.fields {
            XCTAssertEqual(
                AssistantFieldPath(field.path.text),
                field.path,
                "\(field.path.text) does not survive being parsed back"
            )
        }
    }

    /// A field's default has to be the kind of value the field holds, or the guide would tell the
    /// model something the decoder rejects.
    func testEveryDefaultMatchesItsKind() {
        for field in AssistantSettingsCatalog.fields {
            switch (field.kind, field.defaultValue) {
                case (.number, .number), (.flag, .bool), (.text, .string), (.color, .string), (.choice, .string):
                    continue
                case (_, .null) where field.isNullable:
                    continue
                default:
                    XCTFail("\(field.path.text) has a default of \(field.defaultValue.text) for its kind")
            }
        }
    }

    /// A choice field's default has to be one of its own choices.
    func testEveryChoiceDefaultIsOneOfItsChoices() {
        for field in AssistantSettingsCatalog.fields {
            guard case .choice(let choices) = field.kind, let value = field.defaultValue.stringValue else { continue }
            XCTAssertTrue(choices.contains(value), "\(field.path.text) defaults to \(value), which is not a choice")
        }
    }

    /// A number's default has to sit inside the range the guide advertises, or every proposal that
    /// leaves the field alone would look out of bounds.
    func testEveryNumberDefaultIsInRange() {
        for field in AssistantSettingsCatalog.fields {
            guard case .number(let minimum, let maximum, _) = field.kind,
                case .number(let value) = field.defaultValue
            else { continue }
            if let minimum {
                XCTAssertGreaterThanOrEqual(value, minimum, "\(field.path.text) defaults below its own minimum")
            }
            if let maximum {
                XCTAssertLessThanOrEqual(value, maximum, "\(field.path.text) defaults above its own maximum")
            }
        }
    }

    // MARK: - Walking a preset

    /// A preset with every optional field present and one companion holding one item, so encoding
    /// it reaches every key the format has. The values do not matter; the keys do.
    private static var fullyPopulatedPreset: PlaygroundPreset {
        var settings = PlaygroundSettings()
        for role in PlaygroundSettings.Theme.ColorRole.allCases {
            settings.theme[role] = PlaygroundColor(red: 0.5, green: 0.5, blue: 0.5)
        }
        settings.topBar.leadingIcon = "music.note"
        var item = PlaygroundSettings.Item(symbol: "moon.fill", title: "Sleep")
        item.tint = PlaygroundColor(red: 1, green: 1, blue: 1)
        item.fill = .color
        item.fillColor = PlaygroundColor(red: 0, green: 0, blue: 1)
        item.fade = 0.5
        var companion = PlaygroundSettings.Companion(id: "sleep-timer", items: [item], accessibilityLabel: "Timer")
        companion.outline = .circle
        companion.gap = 12
        companion.rowAlignment = .start
        companion.size = .small
        companion.presence = .pop
        companion.fade = 0.4
        companion.stroke = true
        companion.shadow = false
        companion.hover = .lift
        companion.accent = PlaygroundColor(red: 1, green: 0, blue: 0)
        settings.companions = [companion]
        return PlaygroundPreset(
            appearance: NookAppearancePreferences(chromePalette: .dark, surfaceStyle: .liquidGlass),
            settings: settings
        )
    }

    /// Every path in `json` that holds a value rather than more structure, with list indices
    /// collapsed to `[]` so one entry in the catalog covers every element.
    private static func leafPaths(of json: AssistantJSON, prefix: String = "") -> Set<String> {
        switch json {
            case .object(let members):
                guard !members.isEmpty else { return [prefix] }
                var paths = Set<String>()
                for member in members {
                    let path = prefix.isEmpty ? member.name : "\(prefix).\(member.name)"
                    paths.formUnion(leafPaths(of: member.value, prefix: path))
                }
                return paths
            case .array(let values):
                guard !values.isEmpty else { return [prefix] }
                var paths = Set<String>()
                for value in values {
                    paths.formUnion(leafPaths(of: value, prefix: prefix + "[]"))
                }
                return paths
            case .string, .number, .bool, .null:
                return [prefix]
        }
    }
}
