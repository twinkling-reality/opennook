// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// The path that needs nothing installed: copy the prompt, paste the reply. It has to reach the same
/// proposal as every other provider, and it has to survive whatever a chat window wraps a reply in.
final class AssistantClipboardExchangeTests: XCTestCase {
    private let base = PlaygroundPreset()

    private func request(attachments: [AssistantAttachment] = []) throws -> AssistantRequest {
        var conversation = AssistantConversation()
        conversation.add(
            AssistantTurn(role: .person, text: "a dark media player", attachments: attachments)
        )
        return try conversation.request(
            preset: base,
            model: "",
            capabilities: AssistantClipboardExchange.capabilities
        )
    }

    private static let reply = AssistantFakeProvider.answer(
        explanation: "Going dark and narrower.",
        notReproduced: ["the album art grid"],
        patch: #"{ "appearance": { "chromePalette": "dark" }, "settings": { "panel": { "expandedWidth": 420 } } }"#
    )

    // MARK: - Nothing is sent

    /// The whole point: this path reaches nothing and needs nothing.
    func testItNeedsNoKeyAndTouchesNoNetwork() {
        XCTAssertFalse(AssistantClipboardExchange.capabilities.needsAPIKey)
        XCTAssertFalse(AssistantClipboardExchange.capabilities.usesNetwork)
    }

    // MARK: - The prompt

    /// A chat window cannot be handed a schema, so the prompt has to carry the field list and the
    /// shape of the answer in words.
    func testThePromptCarriesEverythingAModelNeeds() throws {
        let prompt = AssistantClipboardExchange.prompt(for: try request())

        XCTAssertTrue(prompt.contains("a dark media player"))
        XCTAssertTrue(prompt.contains("The settings as they are now"))
        XCTAssertTrue(prompt.contains("settings.panel.expandedWidth: number 320 to 760 pt"))
        XCTAssertTrue(prompt.contains("Answer with one JSON object"))
        XCTAssertTrue(prompt.contains("notReproduced"))
    }

    /// Pasted into a chat window, the reply comes back by hand, so asking for a bare object rather
    /// than a fenced block saves the person a step.
    func testThePromptAsksForABareObject() throws {
        XCTAssertTrue(
            AssistantClipboardExchange.prompt(for: try request()).contains("No code fence"),
            "the prompt does not ask for a bare object"
        )
    }

    /// The image cannot travel on the clipboard, but what was measured from it can, so a screenshot
    /// is still worth attaching on this path.
    func testTheColorsFromAScreenshotAreInThePromptEvenThoughTheImageIsNot() throws {
        let attachment = AssistantAttachment(
            jpeg: Data([0xFF, 0xD8]),
            pixelWidth: 1440,
            pixelHeight: 900,
            palette: [PlaygroundColor(hex: "#101114")!, PlaygroundColor(hex: "#E8E8EA")!],
            measurements: ["Mostly dark"]
        )
        let prompt = AssistantClipboardExchange.prompt(for: try request(attachments: [attachment]))

        XCTAssertTrue(prompt.contains("#101114, #E8E8EA"), prompt)
        XCTAssertTrue(prompt.contains("Mostly dark"))
        XCTAssertTrue(prompt.contains("which you cannot see"))
    }

    func testTheImageLimitPointsAtWhatToDoInstead() {
        let limit = AssistantClipboardExchange.capabilities.imageLimit ?? ""
        XCTAssertTrue(limit.contains("your own chat window"), limit)
    }

    // MARK: - Reading a reply

    func testAPastedReplyBecomesTheSameProposalAsAnyProvider() throws {
        let proposal = try AssistantClipboardExchange.proposal(from: Self.reply, base: base)

        XCTAssertEqual(proposal.explanation, "Going dark and narrower.")
        XCTAssertEqual(proposal.notReproduced, ["the album art grid"])
        XCTAssertEqual(proposal.changes.map(\.summary), ["Palette Follow the system -> Dark", "Width 520 -> 420 pt"])
        XCTAssertEqual(proposal.proposed.appearance.chromePalette, .dark)
    }

    /// What a chat window actually gives you.
    func testAReplyInsideACodeFenceIsRead() throws {
        let pasted = """
            Sure, here is a patch that does that:

            ```json
            \(Self.reply)
            ```

            Let me know if you want it rounder.
            """
        let proposal = try AssistantClipboardExchange.proposal(from: pasted, base: base)
        XCTAssertEqual(proposal.changes.count, 2)
    }

    func testAReplyWithSurroundingChatterIsRead() throws {
        let pasted = "Happy to help. \(Self.reply) That should be close to what you described."
        XCTAssertEqual(
            try AssistantClipboardExchange.proposal(from: pasted, base: base).explanation,
            "Going dark and narrower."
        )
    }

    func testAnEmptyClipboardSaysSo() {
        for pasted in ["", "   ", "\n\n"] {
            XCTAssertThrowsError(try AssistantClipboardExchange.proposal(from: pasted, base: base)) { error in
                XCTAssertEqual(error as? AssistantClipboardError, .nothingToRead)
                XCTAssertEqual(
                    error.localizedDescription,
                    "There is no text on the clipboard to read a reply from."
                )
            }
        }
    }

    func testAReplyWithNoJSONInItSaysSo() {
        XCTAssertThrowsError(
            try AssistantClipboardExchange.proposal(from: "I would make it narrower and darker.", base: base)
        ) { error in
            guard case .noJSON = error as? AssistantResponseError else {
                return XCTFail("expected noJSON, got \(error)")
            }
        }
    }

    // MARK: - Correcting by hand

    /// The repair round cannot be automatic when a person is the transport, so they get the same
    /// specific complaint to paste back rather than being told to start over.
    func testAnInventedFieldGivesACorrectionToPasteBack() throws {
        let wrong = AssistantFakeProvider.answer(
            explanation: "Rounder.",
            patch: #"{ "settings": { "panel": { "cornerRadius": 20 } } }"#
        )
        do {
            _ = try AssistantClipboardExchange.proposal(from: wrong, base: base)
            XCTFail("expected the invented field to be caught")
        } catch {
            let correction = try XCTUnwrap(AssistantClipboardExchange.correction(for: error))
            XCTAssertTrue(correction.contains("settings.panel.cornerRadius"), correction)
            XCTAssertTrue(correction.contains("JSON object"), correction)
        }
    }

    func testProseGivesACorrectionToPasteBack() {
        do {
            _ = try AssistantClipboardExchange.proposal(from: "Sure, I can do that!", base: base)
            XCTFail("expected prose to be caught")
        } catch {
            XCTAssertEqual(
                AssistantClipboardExchange.correction(for: error),
                "That was not JSON. Answer with one JSON object holding explanation, notReproduced, "
                    + "and patch, and nothing else."
            )
        }
    }

    /// An empty clipboard is the person's mistake, not the model's, so there is nothing to paste back.
    func testAnEmptyClipboardHasNoCorrectionToOffer() {
        XCTAssertNil(AssistantClipboardExchange.correction(for: AssistantClipboardError.nothingToRead))
    }
}
