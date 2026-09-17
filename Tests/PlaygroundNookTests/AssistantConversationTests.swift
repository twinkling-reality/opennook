// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// What the model is actually sent: the history behind a follow-up, the settings as they are now,
/// and the reference images, which only travel to a provider that can see them.
final class AssistantConversationTests: XCTestCase {
    private func attachment(palette: [String] = ["#101114", "#E8E8EA"]) -> AssistantAttachment {
        AssistantAttachment(
            jpeg: Data([0xFF, 0xD8, 0xFF]),
            pixelWidth: 1440,
            pixelHeight: 900,
            palette: palette.compactMap { PlaygroundColor(hex: $0) },
            measurements: ["Mostly dark", "Corners look rounded, about 20 pt"]
        )
    }

    // MARK: - History

    func testAFollowUpCarriesTheTurnBeforeIt() throws {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "make it a media player"))
        conversation.add(AssistantTurn(role: .assistant, text: "Going dark and narrow."))
        conversation.add(AssistantTurn(role: .person, text: "softer and glassier"))

        let request = try conversation.request(preset: PlaygroundPreset(), model: "example", capabilities: .fake)

        XCTAssertEqual(request.turns.map(\.role), [.person, .assistant, .person])
        XCTAssertTrue(request.turns[0].text.hasPrefix("make it a media player"))
        XCTAssertEqual(request.turns[1].text, "Going dark and narrow.")
        XCTAssertTrue(request.turns[2].text.hasPrefix("softer and glassier"))
    }

    /// A long conversation cannot grow the request without bound, since every turn is re-sent.
    func testOnlyTheLastFewTurnsAreRemembered() throws {
        var conversation = AssistantConversation()
        for index in 1...12 {
            conversation.add(AssistantTurn(role: .person, text: "change \(index)"))
            conversation.add(AssistantTurn(role: .assistant, text: "done \(index)"))
        }
        XCTAssertEqual(conversation.turns.count, AssistantConversation.rememberedTurns)
        XCTAssertTrue(conversation.turns.last?.text.contains("done 12") ?? false)
    }

    func testANewConversationForgetsEverything() {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "make it dark"))
        conversation.clear()
        XCTAssertTrue(conversation.isEmpty)
        XCTAssertEqual(conversation.attachments, [])
    }

    // MARK: - The current state

    /// The settings ride on the newest turn, not the oldest, because a person may have applied,
    /// undone, or hand-edited things between turns.
    func testTheNewestTurnCarriesTheSettingsAsTheyAreNow() throws {
        var preset = PlaygroundPreset()
        preset.settings.panel.expandedWidth = 420

        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "make it dark"))
        conversation.add(AssistantTurn(role: .assistant, text: "Done."))
        conversation.add(AssistantTurn(role: .person, text: "a bit rounder"))

        let request = try conversation.request(preset: preset, model: "example", capabilities: .fake)

        XCTAssertFalse(request.turns[0].text.contains("The settings as they are now"))
        XCTAssertTrue(request.turns[2].text.contains("The settings as they are now"))
        XCTAssertTrue(request.turns[2].text.contains("\"expandedWidth\": 420"), request.turns[2].text)
    }

    // MARK: - Attachments and the capability gate

    func testAProviderThatSeesImagesGetsThePixels() throws {
        var conversation = AssistantConversation()
        conversation.add(
            AssistantTurn(role: .person, text: "copy this style", attachments: [attachment()])
        )

        let request = try conversation.request(preset: PlaygroundPreset(), model: "example", capabilities: .fake)

        XCTAssertTrue(request.sendsImages)
        XCTAssertEqual(request.attachments.count, 1)
        XCTAssertTrue(request.turns[0].text.contains("1 reference attached"), request.turns[0].text)
    }

    /// The gate that matters: a provider that cannot see images is never sent any, and the request
    /// says out loud that the model cannot see them, so it does not pretend to have looked.
    func testAProviderThatCannotSeeImagesIsSentNone() throws {
        var conversation = AssistantConversation()
        conversation.add(
            AssistantTurn(role: .person, text: "copy this style", attachments: [attachment()])
        )

        let request = try conversation.request(
            preset: PlaygroundPreset(),
            model: "example",
            capabilities: .fakeWithoutImages
        )

        XCTAssertFalse(request.sendsImages)
        XCTAssertEqual(request.attachments, [], "images reached a provider that cannot see them")
        XCTAssertTrue(request.turns[0].text.contains("which you cannot see"), request.turns[0].text)
    }

    /// The colors are measured on this machine, so they are in the text either way. This is what
    /// makes "match this screenshot" mean something through a text-only provider.
    func testTheSampledColorsAreInTheTextForEveryProvider() throws {
        var conversation = AssistantConversation()
        conversation.add(
            AssistantTurn(role: .person, text: "copy this style", attachments: [attachment()])
        )

        for capabilities in [AssistantCapabilities.fake, .fakeWithoutImages] {
            let request = try conversation.request(
                preset: PlaygroundPreset(),
                model: "example",
                capabilities: capabilities
            )
            let text = request.turns[0].text
            XCTAssertTrue(text.contains("#101114, #E8E8EA"), text)
            XCTAssertTrue(text.contains("Mostly dark"), text)
            XCTAssertTrue(text.contains("1440 by 900"), text)
        }
    }

    /// Only the newest turn's images are re-sent, so a long conversation with a screenshot in it does
    /// not send that screenshot again and again.
    func testOnlyTheNewestTurnCarriesItsImages() throws {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "copy this", attachments: [attachment()]))
        conversation.add(AssistantTurn(role: .assistant, text: "Done."))
        conversation.add(AssistantTurn(role: .person, text: "closer to it", attachments: [attachment()]))

        let request = try conversation.request(preset: PlaygroundPreset(), model: "example", capabilities: .fake)

        XCTAssertEqual(request.turns[0].attachments.count, 0)
        XCTAssertEqual(request.turns[2].attachments.count, 1)
    }

    func testTheAttachmentsStillInPlayAreTheNewestOnes() {
        var conversation = AssistantConversation()
        let first = attachment(palette: ["#000000"])
        let second = attachment(palette: ["#FFFFFF"])
        conversation.add(AssistantTurn(role: .person, text: "copy this", attachments: [first]))
        conversation.add(AssistantTurn(role: .assistant, text: "Done."))
        XCTAssertEqual(conversation.attachments.map(\.id), [first.id])

        conversation.add(AssistantTurn(role: .person, text: "and this", attachments: [second]))
        XCTAssertEqual(conversation.attachments.map(\.id), [second.id])

        // A follow-up with no new image keeps the last one in play, so "closer to the screenshot"
        // still has a screenshot.
        conversation.add(AssistantTurn(role: .assistant, text: "Done."))
        conversation.add(AssistantTurn(role: .person, text: "closer"))
        XCTAssertEqual(conversation.attachments.map(\.id), [second.id])
    }

    // MARK: - The prompt

    /// A provider that enforces the schema does not also need the field guide, which is most of the
    /// prompt's length.
    func testTheFieldGuideIsOnlySentWhenTheSchemaCannotBeEnforced() {
        let enforced = AssistantPrompt.systemPrompt(capabilities: .fake)
        XCTAssertFalse(enforced.contains("settings.panel.expandedWidth"))

        var loose = AssistantCapabilities.fake
        loose.enforcesSchema = false
        let guided = AssistantPrompt.systemPrompt(capabilities: loose)
        XCTAssertTrue(guided.contains("settings.panel.expandedWidth: number 320 to 760 pt"))
        XCTAssertTrue(guided.contains("Answer with one JSON object"))
        XCTAssertGreaterThan(guided.count, enforced.count)
    }

    /// The prompt has to say what these settings cannot express, or a model invents fields instead of
    /// admitting the limit.
    func testThePromptSaysWhatTheSettingsCannotExpress() {
        let prompt = AssistantPrompt.systemPrompt(capabilities: .fake)
        XCTAssertTrue(prompt.contains("notReproduced"))
        XCTAssertTrue(prompt.contains("home content"))
        XCTAssertTrue(prompt.contains("four system designs"))
    }

    func testThePromptExplainsHowCompanionListsAreWritten() {
        let prompt = AssistantPrompt.systemPrompt(capabilities: .fake)
        XCTAssertTrue(prompt.contains("sets which companions exist and in what order"))
        XCTAssertTrue(prompt.contains("keeps any field you leave out"))
        XCTAssertTrue(prompt.contains("listing items replaces that companion's items"))
    }

    /// Controls outside the panel are the assistant's to compose now; only what is inside the panel
    /// is off limits.
    func testThePromptLetsTheModelComposeCompanionControls() {
        let prompt = AssistantPrompt.systemPrompt(capabilities: .fake)
        XCTAssertTrue(prompt.contains("you can compose them freely"))
        XCTAssertTrue(prompt.contains("controls inside the panel"))
        XCTAssertFalse(prompt.contains("custom controls"))
    }
}
