// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import XCTest

@testable import PlaygroundNookCore

/// Merging a model's patch onto a preset. The patch is the only thing a model produces, so this is
/// the boundary where a wrong answer has to become a clear error rather than a strange nook.
final class AssistantPatchTests: XCTestCase {
    private func patch(_ text: String) throws -> AssistantJSON {
        try XCTUnwrap(AssistantJSON(parsing: text), "the test's own patch is not JSON")
    }

    // MARK: - Merging

    func testAPatchChangesOnlyWhatItNames() throws {
        var base = PlaygroundPreset()
        base.settings.panel.expandedWidth = 520
        base.settings.topBar.leadingTitle = "Home"

        let result = try AssistantPatch.apply(
            patch(#"{ "settings": { "panel": { "expandedWidth": 420 } } }"#),
            to: base
        )

        XCTAssertEqual(result.settings.panel.expandedWidth, 420)
        XCTAssertEqual(result.settings.topBar.leadingTitle, "Home")
        XCTAssertEqual(result.settings.panel.topCornerRadius, base.settings.panel.topCornerRadius)
    }

    func testAPatchCanChangeTheAppearanceAndTheSettingsAtOnce() throws {
        let result = try AssistantPatch.apply(
            patch(
                """
                {
                  "appearance": { "chromePalette": "dark", "surfaceStyle": "liquidGlass" },
                  "settings": { "theme": { "fontDesign": "rounded" } }
                }
                """
            ),
            to: PlaygroundPreset()
        )

        XCTAssertEqual(result.appearance.chromePalette, .dark)
        XCTAssertEqual(result.appearance.surfaceStyle, .liquidGlass)
        XCTAssertEqual(result.settings.theme.fontDesign, .rounded)
    }

    func testAColorArrivesAsHex() throws {
        let result = try AssistantPatch.apply(
            // Two hashes, since the hex color puts a quote and a hash inside the raw string.
            patch(##"{ "settings": { "theme": { "accent": "#FF8A33" } } }"##),
            to: PlaygroundPreset()
        )
        XCTAssertEqual(result.settings.theme.accent?.hex, "#FF8A33")
    }

    /// Null is a value, not a deletion: it is how a theme color goes back to following the user's
    /// own palette.
    func testNullClearsAThemeColor() throws {
        var base = PlaygroundPreset()
        base.settings.theme.accent = PlaygroundColor(red: 1, green: 0, blue: 0)

        let result = try AssistantPatch.apply(
            patch(#"{ "settings": { "theme": { "accent": null } } }"#),
            to: base
        )
        XCTAssertNil(result.settings.theme.accent)
    }

    /// The companions list replaces rather than merges, so a patch that lists one companion is a
    /// list of one.
    func testAListReplacesRatherThanMerges() throws {
        var base = PlaygroundPreset()
        base.settings.companions = [
            PlaygroundSettings.Companion(id: "actions", kind: .actions),
            PlaygroundSettings.Companion(id: "status", kind: .chip),
        ]

        let result = try AssistantPatch.apply(
            patch(
                """
                { "settings": { "companions": [
                    { "id": "sleep-timer", "kind": "button", "outline": "circle", "anchor": "trailing" }
                ] } }
                """
            ),
            to: base
        )

        XCTAssertEqual(result.settings.companions.map(\.id), ["sleep-timer"])
        XCTAssertEqual(result.settings.companions.first?.outline, .circle)
        XCTAssertEqual(result.settings.companions.first?.anchor, .trailing)
    }

    /// A value out of range is clamped by the same normalizing an imported preset goes through, so
    /// the chrome never sees it.
    func testAValueOutOfRangeIsNormalizedRatherThanRefused() throws {
        let result = try AssistantPatch.apply(
            patch(#"{ "settings": { "panel": { "expandedWidth": 99999, "topCornerRadius": -8 } } }"#),
            to: PlaygroundPreset()
        )
        XCTAssertEqual(result.settings.panel.expandedWidth, 2000)
        XCTAssertEqual(result.settings.panel.topCornerRadius, 0)
    }

    /// Two companions with the same name would trap `addCompanion`, so normalizing renames one.
    func testDuplicateCompanionNamesAreMadeUnique() throws {
        let result = try AssistantPatch.apply(
            patch(
                """
                { "settings": { "companions": [
                    { "id": "actions", "kind": "actions" },
                    { "id": "actions", "kind": "chip" }
                ] } }
                """
            ),
            to: PlaygroundPreset()
        )
        XCTAssertEqual(result.settings.companions.map(\.id), ["actions", "actions-2"])
    }

    /// Keep-open is a working aid rather than part of a look, so a patch cannot pin the nook open.
    func testAPatchCannotPinTheNookOpen() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(patch(#"{ "appearance": { "keepNookOpen": true } }"#), to: PlaygroundPreset())
        ) { error in
            XCTAssertEqual(error as? AssistantPatchError, .unknownField(path: "appearance.keepNookOpen"))
        }
    }

    // MARK: - Fidelity

    /// A patch merge rewrites the whole preset on its way through JSON, so a value it does not mention
    /// has to come back bit for bit. A slider leaves values such as 0.8300000000000001 behind, and
    /// rounding one of those on the way through would make the proposal list a change to a field
    /// nobody asked about.
    func testAValueTheePatchDoesNotMentionSurvivesExactly() throws {
        var base = PlaygroundPreset()
        base.settings.motion.viewModeChange = PlaygroundSettings.SpringSpec(
            response: 0.38,
            dampingFraction: 0.8300000000000001
        )
        base.settings.rimGlow.intensity = 0.7000000000000001
        base.appearance.backdropStrength = 0.6900000000000001

        let result = try AssistantPatch.apply(
            patch(#"{ "settings": { "panel": { "expandedWidth": 420 } } }"#),
            to: base
        )

        XCTAssertEqual(
            result.settings.motion.viewModeChange.dampingFraction,
            0.8300000000000001,
            "the damping fraction was rewritten"
        )
        XCTAssertEqual(result.settings.rimGlow.intensity, 0.7000000000000001)
        XCTAssertEqual(result.appearance.backdropStrength, 0.6900000000000001)
    }

    /// The same thing seen from the proposal: a patch that changes one field lists exactly one change,
    /// however much precision the other values carry.
    func testAPatchOfOneFieldListsOneChange() throws {
        var base = PlaygroundPreset()
        base.settings.motion.viewModeChange = PlaygroundSettings.SpringSpec(
            response: 0.38,
            dampingFraction: 0.8300000000000001
        )
        base.settings.rimGlow.intensity = 0.7000000000000001

        let proposal = try AssistantDiff.proposal(
            base: base,
            patch: patch(#"{ "settings": { "panel": { "expandedWidth": 420 } } }"#),
            explanation: "Narrower.",
            notReproduced: []
        )
        XCTAssertEqual(proposal.changes.map(\.summary), ["Width 520 -> 420 pt"])
    }

    /// Every number in a preset reads back as itself.
    func testEveryNumberSurvivesBeingWrittenAndReadBack() throws {
        let awkward: [Double] = [0.8300000000000001, 0.1 + 0.2, 1.0 / 3.0, 0.0001, 1e-7, 12345.6789, 520, -0.0]
        for value in awkward {
            let text = AssistantJSON.numberText(value)
            let json = try XCTUnwrap(AssistantJSON(parsing: text))
            guard case .number(let read) = json else {
                return XCTFail("\(text) did not read back as a number")
            }
            XCTAssertEqual(read, value, "\(value) came back as \(read) through \(text)")
        }
    }

    /// Whole numbers still print without a decimal point, so a schema's bounds stay readable.
    func testWholeNumbersStayTidy() {
        XCTAssertEqual(AssistantJSON.numberText(520), "520")
        XCTAssertEqual(AssistantJSON.numberText(0), "0")
        XCTAssertEqual(AssistantJSON.numberText(-8), "-8")
        XCTAssertEqual(AssistantJSON.numberText(1.5), "1.5")
    }

    /// A proposal row rounds for reading even though the JSON behind it does not.
    func testAChangeRowRoundsForReading() {
        XCTAssertEqual(
            AssistantChange.Value.number(0.8300000000000001, .none).text,
            "0.83"
        )
        XCTAssertEqual(AssistantChange.Value.number(420, .points).text, "420 pt")
        XCTAssertEqual(AssistantChange.Value.number(0.38, .seconds).text, "0.38 s")
        XCTAssertEqual(AssistantChange.Value.number(0.9, .fraction).text, "90%")
    }

    // MARK: - Errors

    func testAnInventedFieldIsNamed() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(
                patch(#"{ "settings": { "panel": { "cornerRadius": 20 } } }"#),
                to: PlaygroundPreset()
            )
        ) { error in
            XCTAssertEqual(error as? AssistantPatchError, .unknownField(path: "settings.panel.cornerRadius"))
        }
    }

    func testAnInventedGroupIsNamed() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(patch(#"{ "settings": { "shadow": { "radius": 4 } } }"#), to: PlaygroundPreset())
        ) { error in
            XCTAssertEqual(error as? AssistantPatchError, .unknownField(path: "settings.shadow"))
        }
    }

    func testAValueWhereAnObjectBelongsIsReported() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(patch(#"{ "settings": { "panel": 420 } }"#), to: PlaygroundPreset())
        ) { error in
            XCTAssertEqual(error as? AssistantPatchError, .wrongShape(path: "settings.panel", expected: "an object"))
        }
    }

    func testAnObjectWhereAValueBelongsIsReported() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(
                patch(#"{ "settings": { "panel": { "expandedWidth": { "value": 420 } } } }"#),
                to: PlaygroundPreset()
            )
        ) { error in
            XCTAssertEqual(
                error as? AssistantPatchError,
                .wrongShape(path: "settings.panel.expandedWidth", expected: "a single value")
            )
        }
    }

    func testAValueWhereAListBelongsIsReported() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(patch(#"{ "settings": { "companions": 3 } }"#), to: PlaygroundPreset())
        ) { error in
            XCTAssertEqual(error as? AssistantPatchError, .wrongShape(path: "settings.companions", expected: "a list"))
        }
    }

    func testSomethingOtherThanAnObjectIsReported() throws {
        XCTAssertThrowsError(try AssistantPatch.apply(patch("[1, 2]"), to: PlaygroundPreset())) { error in
            XCTAssertEqual(error as? AssistantPatchError, .notAnObject)
        }
    }

    /// The wrong type for a real field is caught by the preset decoder, whose message already names
    /// the path. That message is what the repair round sends back.
    func testTheWrongTypeForARealFieldNamesThePath() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(
                patch(#"{ "settings": { "panel": { "expandedWidth": "wide" } } }"#),
                to: PlaygroundPreset()
            )
        ) { error in
            XCTAssertEqual(
                error as? AssistantPatchError,
                .invalidValue(detail: "settings.panel.expandedWidth should be a number")
            )
        }
    }

    func testAnUnknownChoiceNamesThePath() throws {
        XCTAssertThrowsError(
            try AssistantPatch.apply(
                patch(#"{ "settings": { "theme": { "fontDesign": "handwriting" } } }"#),
                to: PlaygroundPreset()
            )
        ) { error in
            guard case .invalidValue(let detail) = try? XCTUnwrap(error as? AssistantPatchError) else {
                return XCTFail("expected an invalid value, got \(error)")
            }
            XCTAssertTrue(detail.contains("settings.theme.fontDesign"), detail)
        }
    }

    /// Every error has to give the model something to act on, since it gets exactly one repair
    /// round before the person sees a failure.
    func testEveryErrorAsksForOneJSONObjectBack() {
        let errors: [AssistantPatchError] = [
            .notAnObject,
            .unknownField(path: "settings.panel.cornerRadius"),
            .wrongShape(path: "settings.panel", expected: "an object"),
            .invalidValue(detail: "settings.panel.expandedWidth should be a number"),
        ]
        for error in errors {
            XCTAssertTrue(
                error.repairRequest.contains("JSON object"),
                "\(error) does not ask for a JSON object: \(error.repairRequest)"
            )
            XCTAssertNotNil(error.errorDescription)
        }
    }

    func testAnErrorNamesTheFieldItIsAbout() {
        XCTAssertEqual(
            AssistantPatchError.unknownField(path: "settings.panel.cornerRadius").errorDescription,
            "There is no setting called settings.panel.cornerRadius."
        )
    }

    // MARK: - Merging JSON

    func testMergingKeepsTheOrderOfTheBase() throws {
        let base = try patch(#"{ "a": 1, "b": { "c": 2, "d": 3 } }"#)
        let overlay = try patch(#"{ "b": { "c": 9 }, "e": 5 }"#)
        XCTAssertEqual(
            AssistantPatch.merge(overlay, onto: base).text,
            """
            {
              "a": 1,
              "b": {
                "c": 9,
                "d": 3
              },
              "e": 5
            }
            """
        )
    }
}
