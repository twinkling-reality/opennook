// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// One request from end to end against a scripted provider: what streams out, what happens when the
/// model answers badly, and what happens when the person presses Stop.
final class AssistantRunnerTests: XCTestCase {
    private let base = PlaygroundPreset()

    private func request(_ text: String = "make it dark") throws -> AssistantRequest {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: text))
        return try conversation.request(preset: base, model: "example", capabilities: .fake)
    }

    private func run(
        _ provider: AssistantFakeProvider,
        request: AssistantRequest? = nil
    ) async throws -> [AssistantOutcome] {
        let request = try request ?? self.request()
        var outcomes: [AssistantOutcome] = []
        for try await outcome in AssistantRunner(provider: provider).run(request, base: base) {
            outcomes.append(outcome)
        }
        return outcomes
    }

    private static let goodAnswer = AssistantFakeProvider.answer(
        explanation: "Going dark and a little narrower.",
        notReproduced: ["the album art grid"],
        patch: #"{ "appearance": { "chromePalette": "dark" }, "settings": { "panel": { "expandedWidth": 420 } } }"#
    )

    // MARK: - The happy path

    func testARunEndsInAProposal() async throws {
        let outcomes = try await run(AssistantFakeProvider(script: .answers([Self.goodAnswer])))

        guard case .proposal(let proposal)? = outcomes.last else {
            return XCTFail("the run did not end in a proposal: \(outcomes)")
        }
        XCTAssertEqual(proposal.explanation, "Going dark and a little narrower.")
        XCTAssertEqual(proposal.notReproduced, ["the album art grid"])
        XCTAssertEqual(proposal.changes.map(\.summary), ["Palette Follow the system -> Dark", "Width 520 -> 420 pt"])
        XCTAssertEqual(proposal.proposed.appearance.chromePalette, .dark)
        // The base is untouched: nothing is applied until the person says so.
        XCTAssertEqual(base.appearance.chromePalette, .followSystem)
    }

    /// The explanation has to arrive in pieces while the patch is still coming, since that is what
    /// the composer shows instead of a spinner.
    func testTheExplanationStreamsBeforeTheProposalArrives() async throws {
        let outcomes = try await run(AssistantFakeProvider(script: .answers([Self.goodAnswer]), chunk: 8))

        let explanations = outcomes.compactMap { outcome -> String? in
            guard case .explanation(let text) = outcome else { return nil }
            return text
        }
        XCTAssertGreaterThan(explanations.count, 2, "the explanation arrived all at once")
        XCTAssertEqual(explanations.last, "Going dark and a little narrower.")
        // Each one extends the one before it, so the composer only ever adds text.
        for (earlier, later) in zip(explanations, explanations.dropFirst()) {
            XCTAssertTrue(later.hasPrefix(earlier), "\(later) does not continue \(earlier)")
        }
        // And the whole explanation is known before the proposal lands.
        let explanationIndex = try XCTUnwrap(outcomes.lastIndex { if case .explanation = $0 { true } else { false } })
        let proposalIndex = try XCTUnwrap(outcomes.lastIndex { if case .proposal = $0 { true } else { false } })
        XCTAssertLessThan(explanationIndex, proposalIndex)
    }

    func testAProviderNoteIsPassedOn() async throws {
        let outcomes = try await run(AssistantFakeProvider(script: .answers([Self.goodAnswer])))
        XCTAssertEqual(
            outcomes.compactMap { outcome -> String? in
                guard case .note(let note) = outcome else { return nil }
                return note
            },
            ["Example is thinking"]
        )
    }

    /// A patch that asks for what is already true is a proposal with no rows, not an error.
    func testAnAnswerThatChangesNothingIsAnEmptyProposal() async throws {
        let answer = AssistantFakeProvider.answer(
            explanation: "It is already that wide.",
            patch: #"{ "settings": { "panel": { "expandedWidth": 520 } } }"#
        )
        let outcomes = try await run(AssistantFakeProvider(script: .answers([answer])))

        guard case .proposal(let proposal)? = outcomes.last else { return XCTFail("expected a proposal") }
        XCTAssertTrue(proposal.isEmpty)
    }

    // MARK: - Repair

    func testAnAnswerThatIsNotJSONIsRepairedOnce() async throws {
        let provider = AssistantFakeProvider(
            script: .answers(["I would make it dark and narrow.", Self.goodAnswer])
        )
        let outcomes = try await run(provider)

        guard
            case .repairing(let reason) = try XCTUnwrap(
                outcomes.first(where: {
                    if case .repairing = $0 { true } else { false }
                })
            )
        else {
            return XCTFail("no repair round happened")
        }
        XCTAssertEqual(reason, "The model did not answer with JSON.")
        guard case .proposal(let proposal)? = outcomes.last else { return XCTFail("expected a proposal") }
        XCTAssertEqual(proposal.explanation, "Going dark and a little narrower.")

        // The repair carries the model's own answer back with the specific complaint.
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].turns.dropLast().last?.text, "I would make it dark and narrow.")
        XCTAssertEqual(requests[1].turns.dropLast().last?.role, .assistant)
        let correction = try XCTUnwrap(requests[1].turns.last)
        XCTAssertEqual(correction.role, .person)
        XCTAssertTrue(correction.text.contains("That was not JSON"), correction.text)
    }

    /// A field that does not exist is the mistake a model is most likely to make, and the repair has
    /// to name it rather than restate the rules.
    func testAnInventedFieldIsRepairedWithItsName() async throws {
        let wrong = AssistantFakeProvider.answer(
            explanation: "Rounding the panel.",
            patch: #"{ "settings": { "panel": { "cornerRadius": 20 } } }"#
        )
        let provider = AssistantFakeProvider(script: .answers([wrong, Self.goodAnswer]))
        let outcomes = try await run(provider)

        let reasons = outcomes.compactMap { outcome -> String? in
            guard case .repairing(let reason) = outcome else { return nil }
            return reason
        }
        XCTAssertEqual(reasons, ["There is no setting called settings.panel.cornerRadius."])

        let requests = await provider.requests
        let correction = try XCTUnwrap(requests[1].turns.last?.text)
        XCTAssertTrue(correction.contains("settings.panel.cornerRadius"), correction)
        guard case .proposal? = outcomes.last else { return XCTFail("expected a proposal after the repair") }
    }

    /// The explanation from a discarded answer is cleared, so text from an answer that was thrown
    /// away is never left on screen.
    func testARepairClearsTheExplanationItIsReplacing() async throws {
        let wrong = AssistantFakeProvider.answer(
            explanation: "Rounding the panel.",
            patch: #"{ "settings": { "panel": { "cornerRadius": 20 } } }"#
        )
        let outcomes = try await run(AssistantFakeProvider(script: .answers([wrong, Self.goodAnswer])))

        let repairIndex = try XCTUnwrap(outcomes.firstIndex { if case .repairing = $0 { true } else { false } })
        XCTAssertEqual(outcomes[repairIndex + 1], .explanation(""))
    }

    /// One round only. A second failure is reported rather than retried again.
    func testARepairThatAlsoFailsIsReported() async throws {
        let wrong = AssistantFakeProvider.answer(
            explanation: "Rounding the panel.",
            patch: #"{ "settings": { "panel": { "cornerRadius": 20 } } }"#
        )
        let provider = AssistantFakeProvider(script: .answers([wrong, wrong]))

        do {
            _ = try await run(provider)
            XCTFail("expected the second failure to be thrown")
        } catch {
            XCTAssertEqual(error as? AssistantPatchError, .unknownField(path: "settings.panel.cornerRadius"))
        }
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2, "the runner tried more than one repair")
    }

    // MARK: - Failures

    func testAProviderFailureIsThrown() async throws {
        let provider = AssistantFakeProvider(script: .fails(.serviceUnavailable(provider: "Ollama", hint: "Run it.")))
        do {
            _ = try await run(provider)
            XCTFail("expected the failure to be thrown")
        } catch {
            XCTAssertEqual(error as? AssistantProviderError, .serviceUnavailable(provider: "Ollama", hint: "Run it."))
        }
    }

    /// A transport failure is worth a Retry button; a missing sign-in is not, since retrying it
    /// unchanged cannot work.
    func testAnErrorKnowsWhetherRetryingIsWorthOffering() {
        XCTAssertTrue(AssistantProviderError.transport(detail: "offline").isWorthRetrying)
        XCTAssertTrue(AssistantProviderError.rateLimited(provider: "codex", retryAfter: 30).isWorthRetrying)
        XCTAssertFalse(AssistantProviderError.toolMissing(command: "codex").isWorthRetrying)
        XCTAssertFalse(AssistantProviderError.notAuthorized(provider: "codex", detail: nil).isWorthRetrying)
    }

    func testEveryProviderErrorReadsAsASentence() {
        let errors: [AssistantProviderError] = [
            .notAuthorized(provider: "codex", detail: nil),
            .notAuthorized(provider: "codex", detail: "expired token"),
            .toolMissing(command: "codex"),
            .toolFailed(command: "codex", status: 1, detail: "no such model"),
            .serviceUnavailable(provider: "Ollama", hint: "Run ollama serve."),
            .rateLimited(provider: "codex", retryAfter: 30),
            .rateLimited(provider: "codex", retryAfter: nil),
            .transport(detail: "offline"),
            .badResponse(detail: "empty"),
            .imagesNotSupported(provider: "claude"),
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "\(error) has no description")
            XCTAssertTrue(description.hasSuffix(".") || description.hasSuffix("?"), description)
        }
    }

    // MARK: - Cancellation

    /// Stop has to end the run promptly and leave nothing behind, including for a provider that
    /// would otherwise never answer.
    func testCancellingEndsTheRunWithoutAProposal() async throws {
        let provider = AssistantFakeProvider(script: .waits)
        let runner = AssistantRunner(provider: provider)
        let request = try request()

        let task = Task {
            var outcomes: [AssistantOutcome] = []
            for try await outcome in runner.run(request, base: base) {
                outcomes.append(outcome)
            }
            return outcomes
        }
        // Let the provider start before stopping it.
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let outcomes = try await task.value
        XCTAssertFalse(
            outcomes.contains { if case .proposal = $0 { true } else { false } },
            "a cancelled run still produced a proposal"
        )
    }

    func testCancellingPartWayThroughAnAnswerProducesNoProposal() async throws {
        let provider = AssistantFakeProvider(
            script: .answers([Self.goodAnswer]),
            chunk: 4,
            pace: .milliseconds(20)
        )
        let runner = AssistantRunner(provider: provider)
        let request = try request()

        let task = Task {
            var outcomes: [AssistantOutcome] = []
            for try await outcome in runner.run(request, base: base) {
                outcomes.append(outcome)
            }
            return outcomes
        }
        try await Task.sleep(for: .milliseconds(60))
        task.cancel()

        let outcomes = try await task.value
        XCTAssertFalse(outcomes.contains { if case .proposal = $0 { true } else { false } })
    }
}
