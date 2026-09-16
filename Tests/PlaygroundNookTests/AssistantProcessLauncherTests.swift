// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import XCTest

@testable import PlaygroundNookCore

/// The process plumbing behind the command line providers, against system binaries rather than a
/// model: whether the prompt reaches standard input, whether output streams, whether the exit status
/// comes back, and whether Stop actually stops the child.
final class AssistantProcessLauncherTests: XCTestCase {
    private let launcher = AssistantProcessLauncher()

    private func collect(_ invocation: AssistantProcessInvocation) async throws -> (
        output: String, status: Int32?
    ) {
        var output = ""
        var status: Int32?
        for try await event in launcher.run(invocation) {
            switch event {
                case .output(let data):
                    output += String(decoding: data, as: UTF8.self)
                case .diagnostic:
                    break
                case .finished(let code):
                    status = code
            }
        }
        return (output, status)
    }

    func testOutputAndExitStatusComeBack() async throws {
        let result = try await collect(
            AssistantProcessInvocation(executable: "/bin/echo", arguments: ["hello playground"])
        )
        XCTAssertEqual(result.output, "hello playground\n")
        XCTAssertEqual(result.status, 0)
    }

    /// The prompt is thousands of characters and goes in on standard input, so this is the path that
    /// carries every real request.
    func testStandardInputReachesTheTool() async throws {
        let prompt = "the whole system prompt\nand a person's request"
        let result = try await collect(
            AssistantProcessInvocation(
                executable: "/bin/cat",
                arguments: [],
                standardInput: Data(prompt.utf8)
            )
        )
        XCTAssertEqual(result.output, prompt)
        XCTAssertEqual(result.status, 0)
    }

    /// A prompt with the field guide in it is larger than a pipe buffer. Writing it from the calling
    /// thread would deadlock against a tool that has not started reading yet.
    func testAPromptLargerThanAPipeBufferDoesNotDeadlock() async throws {
        let prompt = String(repeating: "settings.panel.expandedWidth: number 320 to 760 pt\n", count: 8000)
        XCTAssertGreaterThan(prompt.utf8.count, 256 * 1024)

        let result = try await collect(
            AssistantProcessInvocation(
                executable: "/bin/cat",
                arguments: [],
                standardInput: Data(prompt.utf8)
            )
        )
        XCTAssertEqual(result.output.utf8.count, prompt.utf8.count)
        XCTAssertEqual(result.status, 0)
    }

    func testAFailingToolReportsItsStatus() async throws {
        let result = try await collect(
            AssistantProcessInvocation(executable: "/bin/sh", arguments: ["-c", "exit 3"])
        )
        XCTAssertEqual(result.status, 3)
    }

    func testDiagnosticsAreKeptApartFromTheAnswer() async throws {
        var output = ""
        var diagnostics = ""
        for try await event in launcher.run(
            AssistantProcessInvocation(
                executable: "/bin/sh",
                arguments: ["-c", "echo answer; echo complaint 1>&2"]
            )
        ) {
            switch event {
                case .output(let data): output += String(decoding: data, as: UTF8.self)
                case .diagnostic(let text): diagnostics += text
                case .finished: break
            }
        }
        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), "answer")
        XCTAssertEqual(diagnostics.trimmingCharacters(in: .whitespacesAndNewlines), "complaint")
    }

    /// Output arrives while the tool is still running, which is what lets the explanation stream.
    func testOutputArrivesWhileTheToolIsStillRunning() async throws {
        var pieces: [String] = []
        for try await event in launcher.run(
            AssistantProcessInvocation(
                executable: "/bin/sh",
                arguments: ["-c", "echo one; sleep 0.2; echo two; sleep 0.2; echo three"]
            )
        ) {
            if case .output(let data) = event {
                pieces.append(String(decoding: data, as: UTF8.self))
            }
        }
        XCTAssertGreaterThan(pieces.count, 1, "everything arrived in one lump: \(pieces)")
        XCTAssertEqual(pieces.joined(), "one\ntwo\nthree\n")
    }

    func testAToolThatIsNotThereFailsRatherThanHanging() async throws {
        do {
            _ = try await collect(
                AssistantProcessInvocation(executable: "/nowhere/at/all/codex", arguments: [])
            )
            XCTFail("expected launching to fail")
        } catch {
            guard case .toolFailed(let command, let status, _) = error as? AssistantProviderError else {
                return XCTFail("expected toolFailed, got \(error)")
            }
            XCTAssertEqual(command, "codex")
            XCTAssertEqual(status, -1)
        }
    }

    /// Stop has to reach the child process, or a cancelled request would keep running and keep
    /// spending someone's subscription.
    func testCancellingTerminatesTheTool() async throws {
        let started = Date()
        let task = Task {
            for try await _ in launcher.run(
                AssistantProcessInvocation(executable: "/bin/sleep", arguments: ["30"])
            ) {}
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        try? await task.value

        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the tool was left running")
    }
}
