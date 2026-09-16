// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// Reading a model's answer: the scanner that shows the explanation while it is still arriving, and
/// the parser that has the last word on whether the answer is usable.
final class AssistantResponseTests: XCTestCase {
    // MARK: - Scanning a partial answer

    /// The scanner is fed one character at a time, which is the worst case a stream can produce.
    private func scanned(_ answer: String) -> [String] {
        var seen: [String] = []
        var buffer = ""
        for character in answer {
            buffer.append(character)
            if let found = AssistantResponseScanner.explanation(in: buffer), found.text != seen.last {
                seen.append(found.text)
            }
        }
        return seen
    }

    func testTheExplanationIsReadAsItArrives() {
        let steps = scanned(#"{ "explanation": "Going dark.", "notReproduced": [], "patch": {} }"#)
        XCTAssertEqual(steps.first, "")
        XCTAssertEqual(steps.last, "Going dark.")
        XCTAssertEqual(
            steps,
            [
                "", "G", "Go", "Goi", "Goin", "Going", "Going ", "Going d", "Going da", "Going dar", "Going dark",
                "Going dark.",
            ]
        )
    }

    func testNothingIsReportedBeforeTheValueStarts() {
        XCTAssertNil(AssistantResponseScanner.explanation(in: "{"))
        XCTAssertNil(AssistantResponseScanner.explanation(in: #"{ "expl"#))
        XCTAssertNil(AssistantResponseScanner.explanation(in: #"{ "explanation""#))
        XCTAssertNil(AssistantResponseScanner.explanation(in: #"{ "explanation":"#))
        XCTAssertNotNil(AssistantResponseScanner.explanation(in: #"{ "explanation": ""#))
    }

    func testAnIncompleteExplanationIsNotYetComplete() throws {
        let partial = try XCTUnwrap(AssistantResponseScanner.explanation(in: #"{ "explanation": "Going da"#))
        XCTAssertEqual(partial.text, "Going da")
        XCTAssertFalse(partial.isComplete)

        let whole = try XCTUnwrap(AssistantResponseScanner.explanation(in: #"{ "explanation": "Going dark.","#))
        XCTAssertEqual(whole.text, "Going dark.")
        XCTAssertTrue(whole.isComplete)
    }

    func testEscapesAreDecoded() throws {
        let found = try XCTUnwrap(
            AssistantResponseScanner.explanation(in: #"{ "explanation": "A \"quote\", a slash \\ and a\nbreak." }"#)
        )
        XCTAssertEqual(found.text, "A \"quote\", a slash \\ and a\nbreak.")
        XCTAssertTrue(found.isComplete)
    }

    /// A quote inside the explanation must not look like the end of it.
    func testAnEscapedQuoteDoesNotEndTheExplanation() throws {
        let found = try XCTUnwrap(
            AssistantResponseScanner.explanation(in: #"{ "explanation": "Called \"Music\" now." }"#)
        )
        XCTAssertEqual(found.text, "Called \"Music\" now.")
    }

    /// Half of an escape has to be held back rather than shown as a stray backslash that then
    /// disappears.
    func testAHalfArrivedEscapeIsHeldBack() throws {
        let found = try XCTUnwrap(AssistantResponseScanner.explanation(in: #"{ "explanation": "One\"#))
        XCTAssertEqual(found.text, "One")
        XCTAssertFalse(found.isComplete)
    }

    func testAHalfArrivedUnicodeEscapeIsHeldBack() throws {
        let found = try XCTUnwrap(AssistantResponseScanner.explanation(in: #"{ "explanation": "Wide \u00"#))
        XCTAssertEqual(found.text, "Wide ")
        let complete = try XCTUnwrap(AssistantResponseScanner.explanation(in: #"{ "explanation": "Wide \u00e9" }"#))
        XCTAssertEqual(complete.text, "Wide \u{e9}")
    }

    /// A character built from a surrogate pair is held back until both halves land, so no
    /// replacement glyph is ever shown and then swapped.
    func testASurrogatePairIsHeldBackUntilBothHalvesArrive() throws {
        let half = try XCTUnwrap(AssistantResponseScanner.explanation(in: #"{ "explanation": "Nice \ud83c"#))
        XCTAssertEqual(half.text, "Nice ")
        let whole = try XCTUnwrap(
            AssistantResponseScanner.explanation(in: #"{ "explanation": "Nice \ud83c\udfb5" }"#)
        )
        XCTAssertEqual(whole.text, "Nice \u{1F3B5}")
    }

    /// Anthropic streams a tool's arguments as partial JSON with no outer object, which is the same
    /// problem and has to work the same way.
    func testAnAnswerWithNoOuterBraceStillStreams() throws {
        let found = try XCTUnwrap(AssistantResponseScanner.explanation(in: #""explanation": "Going dark"#))
        XCTAssertEqual(found.text, "Going dark")
    }

    // MARK: - Parsing a whole answer

    private static let answer = """
        {
          "explanation": "Going dark and narrow.",
          "notReproduced": ["the album art grid"],
          "patch": { "appearance": { "chromePalette": "dark" } }
        }
        """

    func testAWellFormedAnswerIsRead() throws {
        let parsed = try AssistantResponseParser.parse(Self.answer)
        XCTAssertEqual(parsed.explanation, "Going dark and narrow.")
        XCTAssertEqual(parsed.notReproduced, ["the album art grid"])
        XCTAssertEqual(parsed.patch["appearance"]?["chromePalette"], .string("dark"))
    }

    /// A command line tool prints its own chatter around the answer, and a chat window wraps it in a
    /// code fence. Both have to work, since both are how a person actually gets an answer here.
    func testTheAnswerIsFoundInsideOtherOutput() throws {
        let noisy = """
            Reading the current settings...
            ```json
            \(Self.answer)
            ```
            Done in 3.2s.
            """
        XCTAssertEqual(try AssistantResponseParser.parse(noisy).explanation, "Going dark and narrow.")
    }

    /// A brace inside a string cannot end the object early.
    func testABraceInsideAStringDoesNotEndTheObject() throws {
        let answer = """
            { "explanation": "Wrote { and } in a label.", "notReproduced": [],
              "patch": { "settings": { "labels": { "settingsBreadcrumb": "{ }" } } } }
            """
        let parsed = try AssistantResponseParser.parse(answer)
        XCTAssertEqual(parsed.explanation, "Wrote { and } in a label.")
        XCTAssertEqual(parsed.patch["settings"]?["labels"]?["settingsBreadcrumb"], .string("{ }"))
    }

    func testAnEmptyNotReproducedListIsFine() throws {
        let parsed = try AssistantResponseParser.parse(
            #"{ "explanation": "Done.", "notReproduced": [], "patch": {} }"#
        )
        XCTAssertEqual(parsed.notReproduced, [])
    }

    /// A model with nothing to report writes null about as often as it writes an empty list. They
    /// mean the same thing, so it is read rather than sent back for repair.
    func testNullNotReproducedIsReadAsNothingToReport() throws {
        let parsed = try AssistantResponseParser.parse(
            #"{ "explanation": "Done.", "notReproduced": null, "patch": {} }"#
        )
        XCTAssertEqual(parsed.notReproduced, [])
    }

    func testAMissingNotReproducedIsReadAsNothingToReport() throws {
        let parsed = try AssistantResponseParser.parse(#"{ "explanation": "Done.", "patch": {} }"#)
        XCTAssertEqual(parsed.notReproduced, [])
    }

    func testProseIsRejected() {
        XCTAssertThrowsError(try AssistantResponseParser.parse("I would make the panel narrower.")) { error in
            guard case .noJSON = error as? AssistantResponseError else {
                return XCTFail("expected noJSON, got \(error)")
            }
        }
    }

    func testAnUnfinishedObjectIsRejected() {
        XCTAssertThrowsError(try AssistantResponseParser.parse(#"{ "explanation": "Going dark"#)) { error in
            guard case .noJSON = error as? AssistantResponseError else {
                return XCTFail("expected noJSON, got \(error)")
            }
        }
    }

    func testAMissingExplanationIsRejected() {
        XCTAssertThrowsError(try AssistantResponseParser.parse(#"{ "notReproduced": [], "patch": {} }"#)) { error in
            XCTAssertEqual(error as? AssistantResponseError, .missingKey("explanation"))
        }
    }

    func testAMissingPatchIsRejected() {
        XCTAssertThrowsError(try AssistantResponseParser.parse(#"{ "explanation": "Done." }"#)) { error in
            XCTAssertEqual(error as? AssistantResponseError, .missingKey("patch"))
        }
    }

    func testAPatchThatIsNotAnObjectIsRejected() {
        XCTAssertThrowsError(
            try AssistantResponseParser.parse(#"{ "explanation": "Done.", "patch": "nothing" }"#)
        ) { error in
            XCTAssertEqual(error as? AssistantResponseError, .wrongType(key: "patch", expected: "an object"))
        }
    }

    func testANotReproducedListOfSomethingElseIsRejected() {
        XCTAssertThrowsError(
            try AssistantResponseParser.parse(#"{ "explanation": "Done.", "notReproduced": [3], "patch": {} }"#)
        ) { error in
            XCTAssertEqual(
                error as? AssistantResponseError,
                .wrongType(key: "notReproduced", expected: "a list of strings")
            )
        }
    }

    func testEveryResponseErrorAsksForOneJSONObjectBack() {
        let errors: [AssistantResponseError] = [
            .noJSON(answer: "hello"),
            .malformedJSON,
            .missingKey("patch"),
            .wrongType(key: "patch", expected: "an object"),
        ]
        for error in errors {
            XCTAssertTrue(error.repairRequest.contains("JSON object"), error.repairRequest)
            XCTAssertNotNil(error.errorDescription)
        }
    }
}
