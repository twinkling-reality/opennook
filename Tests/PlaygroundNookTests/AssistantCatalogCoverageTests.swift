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
        // The person's switch for a theme's sounds. The playground's theme has no sounds, so
        // the switch changes nothing there; a catalog entry can come with playground sounds.
        "appearance.soundsEnabled",
    ]

    // MARK: - Coverage

    func testEveryPresetFieldIsInTheCatalog() throws {
        let encoded = try PlaygroundPresetCoder.encode(Self.fullyPopulatedPreset)
        let json = try XCTUnwrap(AssistantJSON(parsing: encoded))
        let presetPaths = Self.leafPaths(of: json, stoppingAt: Self.structuredPaths).subtracting(Self.excludedPaths)
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
        let presetPaths = Self.leafPaths(of: json, stoppingAt: Self.structuredPaths)
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
        try assertChoices("settings.theme.motion", NookMotionScheme.allCases.map(\.rawValue))
        try assertChoices("settings.theme.fontWidth", NookFontWidth.allCases.map(\.rawValue))
        try assertChoices("settings.theme.palette", NookChromePalette.allCases.map(\.rawValue))
        try assertChoices("settings.theme.surface", NookSurfaceStyle.allCases.map(\.rawValue))
        try assertChoices(
            "settings.theme.backdrops.glassShading",
            PlaygroundSettings.Behavior.GlassShading.allCases.map(\.rawValue)
        )
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
                case (.number, .number), (.flag, .bool), (.text, .string), (.color, .string), (.choice, .string),
                    (.tokenOverrides, .object), (.backdrop, .object):
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

    // MARK: - Tokens

    /// The tokens field takes every token the framework defines and nothing else, so the model can
    /// propose an override of any of them by id.
    func testTheTokensFieldListsEveryRegisteredToken() throws {
        let field = try XCTUnwrap(AssistantSettingsCatalog.field(at: AssistantFieldPath("settings.theme.tokens")))
        XCTAssertEqual(field.kind, .tokenOverrides)
        XCTAssertEqual(field.group, .tokens)
        let tokens = try XCTUnwrap(
            AssistantSchema.patch["properties"]?["settings"]?["properties"]?["theme"]?["properties"]?["tokens"]
        )
        let ids = try XCTUnwrap(tokens["properties"]?.members).map(\.name)
        XCTAssertEqual(ids, NookTokenDescriptor.all.map(\.id))
        XCTAssertEqual(tokens["additionalProperties"], .bool(false))
        XCTAssertEqual(
            tokens["properties"]?["banner.cornerRadius"]?["description"]?.stringValue,
            "A dimension. Default \"{radius.md}\"."
        )
    }

    func testTheFieldGuideListsEveryTokenID() {
        for descriptor in NookTokenDescriptor.all {
            XCTAssertTrue(AssistantSchema.fieldGuide.contains(descriptor.id), "\(descriptor.id) is not in the guide")
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
        settings.theme.radius = 1.2
        settings.theme.scale = 1.1
        settings.theme.motion = .calm
        settings.theme.fontWidth = .condensed
        settings.theme.soundVolume = 0.5
        settings.theme.allowsUserAccent = false
        settings.theme.allowsUserSoundToggle = false
        settings.theme.palette = .dark
        settings.theme.surface = .liquidGlass
        settings.theme.backdropStrength = 0.6
        settings.theme.name = "Night"
        let gradient = NookBackdropDescription.linearGradient(.init(gradient: NookGradientSpec(colors: ["#101014", "#000000"])))
        settings.theme.backdrops = NookThemeBackdrops(
            solid: .solid("#1C1C1E"),
            translucent: gradient,
            liquidGlass: .liquidGlass(.init(variant: .clear)),
            glassShading: .even
        )
        settings.theme.tokens[.bannerCornerRadius] = 12
        settings.theme.tokens[.chrome] = NookShadowSpec()
        for group in PlaygroundSettings.Labels.GroupTitle.allCases {
            settings.labels[group] = "Title"
        }
        for symbol in PlaygroundSettings.TopBar.Symbol.allCases {
            settings.topBar[symbol] = "circle"
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

    /// The catalog fields that hold an object, such as a backdrop or the token overrides: the
    /// keys below one are the field's own, so the walk stops there.
    private static var structuredPaths: Set<String> {
        Set(AssistantSettingsCatalog.fields.filter(\.isStructured).map(\.path.text))
    }

    /// Every path in `json` that holds a value rather than more structure, with list indices
    /// collapsed to `[]` so one entry in the catalog covers every element. A path in `stops` is a
    /// value however much structure it holds.
    private static func leafPaths(
        of json: AssistantJSON,
        prefix: String = "",
        stoppingAt stops: Set<String> = []
    ) -> Set<String> {
        if stops.contains(prefix) { return [prefix] }
        switch json {
            case .object(let members):
                guard !members.isEmpty else { return [prefix] }
                var paths = Set<String>()
                for member in members {
                    let path = prefix.isEmpty ? member.name : "\(prefix).\(member.name)"
                    paths.formUnion(leafPaths(of: member.value, prefix: path, stoppingAt: stops))
                }
                return paths
            case .array(let values):
                guard !values.isEmpty else { return [prefix] }
                var paths = Set<String>()
                for value in values {
                    paths.formUnion(leafPaths(of: value, prefix: prefix + "[]", stoppingAt: stops))
                }
                return paths
            case .string, .number, .bool, .null:
                return [prefix]
        }
    }
}
