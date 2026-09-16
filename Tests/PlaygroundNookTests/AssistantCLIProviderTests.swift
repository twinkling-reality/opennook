// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// The command line providers. Nothing here launches a real tool: the tools call a model, and a test
/// suite must not spend someone's subscription. What is checked instead is every decision the
/// provider makes on its own, which is the part that can be wrong.
final class AssistantCLIProviderTests: XCTestCase {
    // MARK: - Doubles

    /// A process runner that answers from a script and remembers what it was asked to run.
    private struct FakeRunner: AssistantProcessRunner {
        var events: [AssistantProcessEvent]
        let log = Log()

        init(answering text: String, status: Int32 = 0) {
            events = [.output(Data(text.utf8)), .finished(status: status)]
        }

        init(events: [AssistantProcessEvent]) {
            self.events = events
        }

        func run(_ invocation: AssistantProcessInvocation) -> AsyncThrowingStream<
            AssistantProcessEvent, any Error
        > {
            AsyncThrowingStream { continuation in
                Task {
                    await log.record(invocation)
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            }
        }

        actor Log {
            private(set) var invocations: [AssistantProcessInvocation] = []

            func record(_ invocation: AssistantProcessInvocation) {
                invocations.append(invocation)
            }
        }
    }

    /// A scratch space that hands out paths without touching the file system.
    private struct FakeScratch: AssistantScratchSpace {
        var imageCount = 0
        let log = Log()

        func makeFiles(
            for request: AssistantRequest,
            capabilities: AssistantCapabilities
        ) throws -> AssistantScratchFiles {
            let directory = URL(fileURLWithPath: "/tmp/fake-scratch")
            return AssistantScratchFiles(
                directory: directory,
                schema: capabilities.enforcesSchema ? directory.appendingPathComponent("answer-schema.json") : nil,
                images: capabilities.acceptsImages
                    ? request.attachments.indices.map {
                        directory.appendingPathComponent("reference-\($0 + 1).jpg")
                    } : []
            )
        }

        func discard(_ files: AssistantScratchFiles) {
            Task { await log.record(files) }
        }

        actor Log {
            private(set) var discarded: [AssistantScratchFiles] = []

            func record(_ files: AssistantScratchFiles) {
                discarded.append(files)
            }
        }
    }

    private func request(attachments: [AssistantAttachment] = []) throws -> AssistantRequest {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "make it a media player", attachments: attachments))
        return try conversation.request(
            preset: PlaygroundPreset(),
            model: "",
            capabilities: AssistantCLIProvider.Tool.codex.capabilities
        )
    }

    private func attachment() -> AssistantAttachment {
        AssistantAttachment(jpeg: Data([0xFF, 0xD8]), pixelWidth: 800, pixelHeight: 600)
    }

    private func invocation(
        tool: AssistantCLIProvider.Tool,
        model: String = "",
        attachments: [AssistantAttachment] = []
    ) throws -> AssistantProcessInvocation {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "make it a media player", attachments: attachments))
        let request = try conversation.request(
            preset: PlaygroundPreset(),
            model: model,
            capabilities: tool.capabilities
        )
        let files = try FakeScratch().makeFiles(for: request, capabilities: tool.capabilities)
        return AssistantCLIProvider.invocation(
            tool: tool,
            executable: "/opt/homebrew/bin/\(tool.command)",
            model: model,
            request: request,
            files: files
        )
    }

    // MARK: - What codex is asked to run

    func testCodexIsRunNonInteractivelyAgainstTheSchema() throws {
        let invocation = try invocation(tool: .codex)

        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/codex")
        XCTAssertEqual(invocation.arguments.first, "exec")
        XCTAssertTrue(invocation.arguments.contains("--output-schema"))
        XCTAssertTrue(invocation.arguments.contains("/tmp/fake-scratch/answer-schema.json"))
        // The prompt is on standard input, which a dash tells codex to read.
        XCTAssertEqual(invocation.arguments.last, "-")
    }

    /// The tool is answering a question about window chrome. It has no business running commands or
    /// writing files, and nothing about this request should outlive it.
    func testCodexIsRunSandboxedAndLeavesNoSession() throws {
        let arguments = try invocation(tool: .codex).arguments
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--sandbox")! + 1], "read-only")
        XCTAssertTrue(arguments.contains("--ephemeral"))
        XCTAssertTrue(arguments.contains("--skip-git-repo-check"))
        XCTAssertTrue(arguments.contains("--color"))
    }

    func testCodexIsGivenEachImageByPath() throws {
        let invocation = try invocation(tool: .codex, attachments: [attachment(), attachment()])
        let images = invocation.arguments.enumerated().compactMap { index, argument in
            argument == "--image" ? invocation.arguments[index + 1] : nil
        }
        XCTAssertEqual(images, ["/tmp/fake-scratch/reference-1.jpg", "/tmp/fake-scratch/reference-2.jpg"])
    }

    func testCodexIsOnlyGivenAModelWhenOneWasChosen() throws {
        XCTAssertFalse(try invocation(tool: .codex).arguments.contains("--model"))

        let chosen = try invocation(tool: .codex, model: "gpt-5-codex")
        let arguments = chosen.arguments
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--model")! + 1], "gpt-5-codex")
    }

    // MARK: - What claude is asked to run

    func testClaudeIsRunInPrintModeWithoutTools() throws {
        let invocation = try invocation(tool: .claude, model: "sonnet")

        XCTAssertTrue(invocation.arguments.contains("--print"))
        XCTAssertEqual(invocation.arguments[invocation.arguments.firstIndex(of: "--output-format")! + 1], "text")
        XCTAssertTrue(invocation.arguments.contains("--restricted"))
        XCTAssertTrue(invocation.arguments.contains("--no-session-persistence"))
        XCTAssertEqual(invocation.arguments[invocation.arguments.firstIndex(of: "--model")! + 1], "sonnet")
    }

    func testClaudeIsNotGivenASchemaFileItCannotUse() throws {
        let invocation = try invocation(tool: .claude)
        XCTAssertFalse(invocation.arguments.contains("--output-schema"))
        XCTAssertFalse(invocation.arguments.contains("--image"))
    }

    /// The claude command has no way to take an image, so it says so rather than dropping them
    /// silently. This is what the disabled paperclip's tooltip shows.
    func testClaudeSaysWhyItCannotSeeImages() {
        let capabilities = AssistantCLIProvider.Tool.claude.capabilities
        XCTAssertFalse(capabilities.acceptsImages)
        let limit = capabilities.imageLimit ?? ""
        XCTAssertTrue(limit.contains("cannot be given images"), limit)
        XCTAssertTrue(limit.contains("codex"), "the limit should point at something that does work: \(limit)")
    }

    func testAnImageNeverReachesClaude() throws {
        let invocation = try invocation(tool: .claude, attachments: [attachment()])
        XCTAssertFalse(invocation.arguments.contains { $0.hasSuffix(".jpg") })
    }

    // MARK: - Neither tool needs a key

    /// The whole point of these two providers.
    func testNeitherToolNeedsAnAPIKey() {
        for tool in AssistantCLIProvider.Tool.allCases {
            XCTAssertFalse(tool.capabilities.needsAPIKey, "\(tool.command) should reuse its own sign-in")
            XCTAssertFalse(tool.identity.summary.isEmpty)
            XCTAssertTrue(tool.identity.summary.contains("No key"), tool.identity.summary)
        }
    }

    // MARK: - The prompt

    func testThePromptIsOnStandardInputRatherThanInAnArgument() throws {
        let invocation = try invocation(tool: .codex)
        let prompt = String(decoding: try XCTUnwrap(invocation.standardInput), as: UTF8.self)

        XCTAssertTrue(prompt.contains("make it a media player"))
        XCTAssertTrue(prompt.contains("The settings as they are now"))
        // Nothing about the request is visible in the process table.
        XCTAssertFalse(invocation.arguments.contains { $0.contains("media player") })
    }

    func testTheHistoryIsFlattenedWithPlainMarkers() throws {
        var conversation = AssistantConversation()
        conversation.add(AssistantTurn(role: .person, text: "make it dark"))
        conversation.add(AssistantTurn(role: .assistant, text: "Done."))
        conversation.add(AssistantTurn(role: .person, text: "softer"))
        let request = try conversation.request(
            preset: PlaygroundPreset(),
            model: "",
            capabilities: AssistantCLIProvider.Tool.claude.capabilities
        )

        let prompt = AssistantCLIProvider.prompt(for: request, tool: .claude)
        XCTAssertTrue(prompt.contains("The person said:\nmake it dark"))
        XCTAssertTrue(prompt.contains("You answered:\nDone."))
        // The newest request is last, where both tools weight their attention.
        let lastPerson = try XCTUnwrap(prompt.range(of: "softer"))
        let answered = try XCTUnwrap(prompt.range(of: "You answered:"))
        XCTAssertLessThan(answered.lowerBound, lastPerson.lowerBound)
    }

    /// claude cannot be handed a schema, so the shape of the answer has to be in the words.
    func testClaudeIsToldTheShapeOfTheAnswerInWords() throws {
        let request = try request()
        let prompt = AssistantCLIProvider.prompt(
            for: AssistantRequest(
                systemPrompt: AssistantPrompt.systemPrompt(
                    capabilities: AssistantCLIProvider.Tool.claude.capabilities
                ),
                turns: request.turns,
                model: "sonnet",
                sendsImages: false
            ),
            tool: .claude
        )
        XCTAssertTrue(prompt.contains("Answer with one JSON object"))
        XCTAssertTrue(prompt.contains("settings.panel.expandedWidth"))
    }

    func testCodexIsToldTheAnswerIsTheSchemaAndNotGivenTheFieldList() throws {
        let prompt = AssistantCLIProvider.prompt(for: try request(), tool: .codex)
        XCTAssertTrue(prompt.contains("described by the output schema"))
        XCTAssertFalse(prompt.contains("settings.panel.expandedWidth: number"))
    }

    // MARK: - Reading the answer

    func testAnAnswerFromTheToolBecomesAProposal() async throws {
        let answer = AssistantFakeProvider.answer(
            explanation: "Going dark and narrow.",
            patch: #"{ "settings": { "panel": { "expandedWidth": 420 } } }"#
        )
        let scratch = FakeScratch()
        let provider = AssistantCLIProvider(
            tool: .codex,
            executable: "/opt/homebrew/bin/codex",
            model: "",
            runner: FakeRunner(answering: answer),
            workspace: scratch
        )

        var outcomes: [AssistantOutcome] = []
        for try await outcome in AssistantRunner(provider: provider).run(try request(), base: PlaygroundPreset()) {
            outcomes.append(outcome)
        }

        guard case .proposal(let proposal)? = outcomes.last else {
            return XCTFail("no proposal: \(outcomes)")
        }
        XCTAssertEqual(proposal.changes.map(\.summary), ["Width 520 -> 420 pt"])
    }

    /// Command line tools print their own progress around the answer. It has to be found in there.
    func testTheAnswerIsFoundAmongTheToolsOwnOutput() async throws {
        let answer = AssistantFakeProvider.answer(
            explanation: "Narrower.",
            patch: #"{ "settings": { "panel": { "expandedWidth": 400 } } }"#
        )
        let noisy = "Reading prompt from stdin\nthinking...\n\(answer)\ntokens used: 1841\n"
        let provider = AssistantCLIProvider(
            tool: .codex,
            executable: "/opt/homebrew/bin/codex",
            model: "",
            runner: FakeRunner(answering: noisy),
            workspace: FakeScratch()
        )

        var outcomes: [AssistantOutcome] = []
        for try await outcome in AssistantRunner(provider: provider).run(try request(), base: PlaygroundPreset()) {
            outcomes.append(outcome)
        }
        guard case .proposal(let proposal)? = outcomes.last else {
            return XCTFail("no proposal: \(outcomes)")
        }
        XCTAssertEqual(proposal.explanation, "Narrower.")
    }

    /// Whatever happens, the directory holding the schema and the screenshots goes away.
    func testTheScratchDirectoryIsDiscardedAfterwards() async throws {
        let scratch = FakeScratch()
        let provider = AssistantCLIProvider(
            tool: .codex,
            executable: "/opt/homebrew/bin/codex",
            model: "",
            runner: FakeRunner(answering: "not json", status: 1),
            workspace: scratch
        )

        // The tool failing is the point: the files have to go either way.
        do {
            for try await _ in provider.stream(try request()) {}
        } catch {}
        // The discard is recorded on a task of its own, so give it a moment to land.
        try await Task.sleep(for: .milliseconds(50))
        let discarded = await scratch.log.discarded
        XCTAssertEqual(discarded.count, 1, "the screenshots were left on disk")
    }

    // MARK: - Failures

    func testALostSignInIsReportedAsSomethingToFixRatherThanRetry() {
        let error = AssistantCLIProvider.failure(
            tool: .codex,
            status: 1,
            diagnostics: "stream error\nERROR: Not logged in. Run codex login.\n"
        )
        XCTAssertEqual(
            error,
            .notAuthorized(provider: "codex", detail: "ERROR: Not logged in. Run codex login.")
        )
        XCTAssertFalse(error.isWorthRetrying)
    }

    func testUsageLimitsAreReportedAsWorthRetrying() {
        let error = AssistantCLIProvider.failure(
            tool: .claude,
            status: 1,
            diagnostics: "You have hit your usage limit for this session."
        )
        XCTAssertEqual(error, .rateLimited(provider: "claude", retryAfter: nil))
        XCTAssertTrue(error.isWorthRetrying)
    }

    func testAnyOtherFailureShowsTheToolsLastComplaint() {
        let error = AssistantCLIProvider.failure(
            tool: .codex,
            status: 2,
            diagnostics: "warming up\n\nunknown model \"gpt-9\"\n"
        )
        XCTAssertEqual(error, .toolFailed(command: "codex", status: 2, detail: "unknown model \"gpt-9\""))
        XCTAssertEqual(error.errorDescription, "codex: unknown model \"gpt-9\".")
    }

    func testAFailureWithNothingToSayStillNamesTheStatus() {
        let error = AssistantCLIProvider.failure(tool: .codex, status: 127, diagnostics: "   \n\n")
        XCTAssertEqual(error, .toolFailed(command: "codex", status: 127, detail: ""))
        XCTAssertEqual(error.errorDescription, "codex exited with status 127.")
    }

    func testANonZeroExitEndsTheStreamWithThatFailure() async throws {
        let provider = AssistantCLIProvider(
            tool: .codex,
            executable: "/opt/homebrew/bin/codex",
            model: "",
            runner: FakeRunner(
                events: [.diagnostic("Not logged in."), .finished(status: 1)]
            ),
            workspace: FakeScratch()
        )

        do {
            for try await _ in provider.stream(try request()) {}
            XCTFail("expected the failure to be thrown")
        } catch {
            XCTAssertEqual(
                error as? AssistantProviderError,
                .notAuthorized(provider: "codex", detail: "Not logged in.")
            )
        }
    }

    // MARK: - Finding the tools

    /// The reason this exists: a playground opened from Finder has a bare PATH, so the tools people
    /// actually have would look missing.
    func testAToolIsFoundWhereItIsNormallyInstalledEvenWithABarePath() {
        let paths = AssistantToolLocator.searchPaths(
            environment: ["PATH": "/usr/bin:/bin"],
            home: "/Users/example"
        )
        XCTAssertEqual(paths.prefix(2).map { $0 }, ["/usr/bin", "/bin"])
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/Users/example/.local/bin"))

        let found = AssistantToolLocator.locate(
            "claude",
            searchPaths: paths,
            isExecutable: { $0 == "/Users/example/.local/bin/claude" }
        )
        XCTAssertEqual(found, "/Users/example/.local/bin/claude")
    }

    func testWhatThePathSaysIsTriedFirst() {
        let paths = AssistantToolLocator.searchPaths(
            environment: ["PATH": "/custom/bin"],
            home: "/Users/example"
        )
        let found = AssistantToolLocator.locate("codex", searchPaths: paths, isExecutable: { _ in true })
        XCTAssertEqual(found, "/custom/bin/codex")
    }

    func testAToolThatIsNotInstalledIsNotFound() {
        XCTAssertNil(
            AssistantToolLocator.locate("codex", searchPaths: ["/usr/bin"], isExecutable: { _ in false })
        )
    }

    func testTheSearchPathHasNoEmptyOrRepeatedEntries() {
        let paths = AssistantToolLocator.searchPaths(
            environment: ["PATH": "/usr/bin::/bin:/opt/homebrew/bin"],
            home: "/Users/example"
        )
        XCTAssertFalse(paths.contains(""))
        XCTAssertEqual(Set(paths).count, paths.count, "\(paths)")
    }
}
