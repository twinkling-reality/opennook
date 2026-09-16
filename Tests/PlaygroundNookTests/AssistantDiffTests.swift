// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import NookKit
import XCTest

@testable import PlaygroundNookCore

/// The diff behind the proposal card: what a person reads before deciding, and what happens when
/// they switch a row off.
final class AssistantDiffTests: XCTestCase {
    private func patch(_ text: String) throws -> AssistantJSON {
        try XCTUnwrap(AssistantJSON(parsing: text))
    }

    // MARK: - Reading a change

    func testAnUnchangedPresetHasNoChanges() throws {
        let preset = PlaygroundPreset()
        XCTAssertEqual(try AssistantDiff.changes(from: preset, to: preset), [])
    }

    func testANumberReadsWithItsUnitOnce() throws {
        var proposed = PlaygroundPreset()
        proposed.settings.panel.expandedWidth = 420

        let changes = try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed)
        XCTAssertEqual(changes.map(\.summary), ["Width 520 -> 420 pt"])
        XCTAssertEqual(changes.first?.group, .panel)
        XCTAssertEqual(changes.first?.id, "settings.panel.expandedWidth")
    }

    func testAFlagReadsAsOnOrOff() throws {
        var proposed = PlaygroundPreset()
        proposed.settings.topBar.showsTopBar = false

        let changes = try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed)
        XCTAssertEqual(changes.map(\.summary), ["Top bar on -> off"])
    }

    func testAChoiceReadsByName() throws {
        var proposed = PlaygroundPreset()
        proposed.appearance.surfaceStyle = .liquidGlass

        let changes = try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed)
        XCTAssertEqual(changes.map(\.summary), ["Surface Solid -> Liquid Glass"])
        XCTAssertEqual(changes.first?.group, .appearance)
    }

    func testAFractionReadsAsAPercentage() throws {
        var proposed = PlaygroundPreset()
        proposed.settings.rimGlow.intensity = 0.8

        let changes = try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed)
        XCTAssertEqual(changes.map(\.summary), ["Intensity 90% -> 80%"])
    }

    /// A color keeps its value, so the row can show a swatch of each side rather than only hex.
    func testAColorCarriesTheColorItself() throws {
        var proposed = PlaygroundPreset()
        proposed.settings.theme.accent = PlaygroundColor(red: 1, green: 0.54, blue: 0.2)

        let change = try XCTUnwrap(try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed).first)
        XCTAssertEqual(change.oldValue, AssistantChange.Value.none)
        guard case .color(let color) = change.newValue else { return XCTFail("expected a color") }
        XCTAssertEqual(color.hex, "#FF8A33")
        XCTAssertEqual(change.summary, "Accent none -> #FF8A33")
    }

    func testASpringSaysWhichRoleItBelongsTo() throws {
        var proposed = PlaygroundPreset()
        proposed.settings.motion.viewModeChange = PlaygroundSettings.SpringSpec(
            response: 0.5,
            dampingFraction: 0.84
        )

        let changes = try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed)
        XCTAssertEqual(changes.map(\.summary), ["View mode change response 0.38 -> 0.5 s"])
        XCTAssertEqual(changes.first?.group, .typeAndMotion)
    }

    func testAFontSaysWhichRoleItBelongsTo() throws {
        var proposed = PlaygroundPreset()
        proposed.settings.typography.topBarLabel = PlaygroundSettings.FontSpec(size: 12, weight: .medium)

        let changes = try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed)
        XCTAssertEqual(
            changes.map(\.summary),
            ["Top bar label size 11 -> 12 pt", "Top bar label weight Regular -> Medium"]
        )
    }

    // MARK: - Grouping

    func testChangesAreGroupedTheWayTheWindowIs() throws {
        var proposed = PlaygroundPreset()
        proposed.appearance.chromePalette = .dark
        proposed.settings.panel.expandedWidth = 420
        proposed.settings.topBar.showsTopBar = false
        proposed.settings.theme.fontDesign = .rounded

        let proposal = AssistantProposal(
            explanation: "",
            notReproduced: [],
            changes: try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed),
            proposed: proposed,
            base: PlaygroundPreset()
        )

        XCTAssertEqual(proposal.groups.map(\.group), [.appearance, .theme, .panel, .topBar])
    }

    // MARK: - Companions

    func testAddingACompanionIsOneRow() throws {
        var proposed = PlaygroundPreset()
        var timer = PlaygroundSettings.Companion(id: "sleep-timer", kind: .button)
        timer.anchor = .trailing
        timer.outline = .circle
        proposed.settings.companions = [timer]

        let changes = try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed)
        XCTAssertEqual(changes.map(\.summary), ["Add sleep-timer"])
        XCTAssertEqual(changes.first?.kind, .companionAdded)
        XCTAssertEqual(changes.first?.subject, "sleep-timer")
        XCTAssertEqual(changes.first?.newValue.text, "round button, trailing")
    }

    func testRemovingACompanionIsOneRow() throws {
        var base = PlaygroundPreset()
        base.settings.companions = [PlaygroundSettings.Companion(id: "status", kind: .chip)]

        let changes = try AssistantDiff.changes(from: base, to: PlaygroundPreset())
        XCTAssertEqual(changes.map(\.summary), ["Remove status"])
        XCTAssertEqual(changes.first?.kind, .companionRemoved)
    }

    /// Replacing the whole list to change one companion shows only what actually differs, and says
    /// which companion it belongs to.
    func testChangingOneCompanionInAListDoesNotRewriteTheOthers() throws {
        var base = PlaygroundPreset()
        base.settings.companions = [
            PlaygroundSettings.Companion(id: "actions", kind: .actions),
            PlaygroundSettings.Companion(id: "status", kind: .chip),
        ]
        var proposed = base
        proposed.settings.companions[1].spacing = 14

        let changes = try AssistantDiff.changes(from: base, to: proposed)
        XCTAssertEqual(changes.map(\.summary), ["Spacing 8 -> 14 pt"])
        XCTAssertEqual(changes.first?.subject, "status")
        XCTAssertEqual(changes.first?.id, "settings.companions[status].spacing")
    }

    func testCompanionRowsAreOrderedRemovedThenChangedThenAdded() throws {
        var base = PlaygroundPreset()
        base.settings.companions = [
            PlaygroundSettings.Companion(id: "gone", kind: .chip),
            PlaygroundSettings.Companion(id: "stays", kind: .actions),
        ]
        var proposed = base
        proposed.settings.companions.removeFirst()
        proposed.settings.companions[0].spacing = 12
        proposed.settings.companions.append(PlaygroundSettings.Companion(id: "fresh", kind: .button))

        let changes = try AssistantDiff.changes(from: base, to: proposed)
        XCTAssertEqual(changes.map(\.kind), [.companionRemoved, .value, .companionAdded])
        XCTAssertEqual(changes.map(\.subject), ["gone", "stays", "fresh"])
    }

    /// The order of a proposal cannot depend on dictionary hashing, or two identical runs would
    /// list the same rows differently.
    func testTheOrderOfChangesIsStable() throws {
        var base = PlaygroundPreset()
        base.settings.companions = (1...6).map {
            PlaygroundSettings.Companion(id: "companion-\($0)", kind: .actions)
        }
        var proposed = base
        for index in proposed.settings.companions.indices {
            proposed.settings.companions[index].spacing = 12
        }

        let first = try AssistantDiff.changes(from: base, to: proposed).map(\.id)
        for _ in 0..<8 {
            XCTAssertEqual(try AssistantDiff.changes(from: base, to: proposed).map(\.id), first)
        }
    }

    // MARK: - Switching a change off

    func testApplyingEveryChangeGivesThePropsedPreset() throws {
        let proposal = try proposalChangingSeveralThings()
        let selection = Set(proposal.changes.map(\.id))
        XCTAssertEqual(try proposal.preset(applying: selection), proposal.proposed)
    }

    func testApplyingNothingGivesTheBasePresetBack() throws {
        let proposal = try proposalChangingSeveralThings()
        XCTAssertEqual(try proposal.preset(applying: []), proposal.base)
    }

    func testASwitchedOffRowLeavesItsFieldAlone() throws {
        let proposal = try proposalChangingSeveralThings()
        let kept = proposal.changes.filter { $0.id != "settings.panel.expandedWidth" }

        let result = try proposal.preset(applying: Set(kept.map(\.id)))

        XCTAssertEqual(result.settings.panel.expandedWidth, proposal.base.settings.panel.expandedWidth)
        XCTAssertEqual(result.appearance.chromePalette, .dark)
        XCTAssertEqual(result.settings.theme.fontDesign, .rounded)
    }

    /// A companion's field can be switched off on its own, even though the whole list is what gets
    /// written.
    func testASwitchedOffCompanionFieldLeavesTheRestOfTheListAlone() throws {
        var base = PlaygroundPreset()
        base.settings.companions = [
            PlaygroundSettings.Companion(id: "actions", kind: .actions),
            PlaygroundSettings.Companion(id: "status", kind: .chip),
        ]
        var proposed = base
        proposed.settings.companions[0].spacing = 16
        proposed.settings.companions[1].outline = .circle

        let proposal = AssistantProposal(
            explanation: "",
            notReproduced: [],
            changes: try AssistantDiff.changes(from: base, to: proposed),
            proposed: proposed,
            base: base
        )
        let spacing = try XCTUnwrap(proposal.changes.first { $0.id == "settings.companions[actions].spacing" })
        let kept = proposal.changes.filter { $0.id != spacing.id }

        let result = try proposal.preset(applying: Set(kept.map(\.id)))

        XCTAssertEqual(result.settings.companions.map(\.id), ["actions", "status"])
        XCTAssertEqual(result.settings.companions[0].spacing, base.settings.companions[0].spacing)
        XCTAssertEqual(result.settings.companions[1].outline, .circle)
    }

    func testASwitchedOffAdditionDoesNotAddTheCompanion() throws {
        var proposed = PlaygroundPreset()
        proposed.settings.companions = [
            PlaygroundSettings.Companion(id: "sleep-timer", kind: .button),
            PlaygroundSettings.Companion(id: "status", kind: .chip),
        ]
        let proposal = AssistantProposal(
            explanation: "",
            notReproduced: [],
            changes: try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed),
            proposed: proposed,
            base: PlaygroundPreset()
        )
        let kept = proposal.changes.filter { $0.subject != "sleep-timer" }

        let result = try proposal.preset(applying: Set(kept.map(\.id)))
        XCTAssertEqual(result.settings.companions.map(\.id), ["status"])
    }

    func testASwitchedOffRemovalKeepsTheCompanionWhereItWas() throws {
        var base = PlaygroundPreset()
        base.settings.companions = [
            PlaygroundSettings.Companion(id: "first", kind: .actions),
            PlaygroundSettings.Companion(id: "second", kind: .chip),
            PlaygroundSettings.Companion(id: "third", kind: .button),
        ]
        var proposed = base
        proposed.settings.companions.remove(at: 1)

        let proposal = AssistantProposal(
            explanation: "",
            notReproduced: [],
            changes: try AssistantDiff.changes(from: base, to: proposed),
            proposed: proposed,
            base: base
        )

        let result = try proposal.preset(applying: [])
        XCTAssertEqual(result.settings.companions.map(\.id), ["first", "second", "third"])
    }

    // MARK: - From a patch

    func testAProposalComesFromAPatchAndItsExplanation() throws {
        let proposal = try AssistantDiff.proposal(
            base: PlaygroundPreset(),
            patch: patch(
                """
                {
                  "appearance": { "chromePalette": "dark" },
                  "settings": { "panel": { "expandedWidth": 420 } }
                }
                """
            ),
            explanation: "Going dark and narrow.",
            notReproduced: ["the album art grid"]
        )

        XCTAssertEqual(proposal.explanation, "Going dark and narrow.")
        XCTAssertEqual(proposal.notReproduced, ["the album art grid"])
        XCTAssertEqual(proposal.changes.map(\.summary), ["Palette Follow the system -> Dark", "Width 520 -> 420 pt"])
        XCTAssertFalse(proposal.isEmpty)
    }

    /// A patch that asks for what is already true is not an error, it is simply nothing to do, and
    /// the composer says so rather than showing an empty card.
    func testAPatchThatChangesNothingMakesAnEmptyProposal() throws {
        var base = PlaygroundPreset()
        base.settings.panel.expandedWidth = 420

        let proposal = try AssistantDiff.proposal(
            base: base,
            patch: patch(#"{ "settings": { "panel": { "expandedWidth": 420 } } }"#),
            explanation: "Already that wide.",
            notReproduced: []
        )
        XCTAssertTrue(proposal.isEmpty)
        XCTAssertEqual(proposal.groups.count, 0)
    }

    // MARK: - Helpers

    private func proposalChangingSeveralThings() throws -> AssistantProposal {
        var proposed = PlaygroundPreset()
        proposed.appearance.chromePalette = .dark
        proposed.settings.panel.expandedWidth = 420
        proposed.settings.theme.fontDesign = .rounded
        return AssistantProposal(
            explanation: "",
            notReproduced: [],
            changes: try AssistantDiff.changes(from: PlaygroundPreset(), to: proposed),
            proposed: proposed,
            base: PlaygroundPreset()
        )
    }
}
