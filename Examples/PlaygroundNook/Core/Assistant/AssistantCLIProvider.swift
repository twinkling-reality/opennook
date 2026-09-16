// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// Asks a command line tool the person already has, so the assistant costs nothing to use.
///
/// This is the provider that matters most. Customizing an open source app should not need an API key
/// and a billing account: someone who already pays for Codex or Claude, or who signed in to either
/// tool once, has already paid for this. The tool is run the way it documents for scripts, with the
/// sign-in it already holds, and the playground never sees a credential.
///
/// What the two tools can do differs, and the composer says so rather than papering over it. `codex
/// exec` takes images with `--image` and enforces the answer's shape with `--output-schema`, so a
/// screenshot reaches the model and the JSON comes back well formed. `claude --print` has neither, so
/// it is told the shape in words and the paperclip is disabled with a tooltip explaining why.
public struct AssistantCLIProvider: AssistantProvider {
    /// Which tool this is. Everything that differs between them is switched on this rather than
    /// configured, so a new tool has to state its own answers.
    public enum Tool: String, CaseIterable, Sendable {
        case codex
        case claude

        /// The command to look for on the PATH.
        public var command: String { rawValue }

        public var identity: AssistantProviderIdentity {
            switch self {
                case .codex:
                    AssistantProviderIdentity(
                        id: "codex-cli",
                        name: "codex",
                        summary: "Uses the codex command you are already signed in to. No key, no extra cost."
                    )
                case .claude:
                    AssistantProviderIdentity(
                        id: "claude-cli",
                        name: "claude",
                        summary: "Uses the claude command you are already signed in to. No key, no extra cost."
                    )
            }
        }

        public var capabilities: AssistantCapabilities {
            switch self {
                case .codex:
                    AssistantCapabilities(
                        acceptsImages: true,
                        imageEdge: 1536,
                        enforcesSchema: true,
                        needsAPIKey: false,
                        usesNetwork: true
                    )
                case .claude:
                    AssistantCapabilities(
                        acceptsImages: false,
                        imageLimit: "The claude command cannot be given images. Use codex, or a provider "
                            + "with an API key, to match a screenshot.",
                        enforcesSchema: false,
                        needsAPIKey: false,
                        usesNetwork: true
                    )
            }
        }

        /// What the model is called when nothing has been chosen. Both tools take an alias and pick
        /// the current model behind it, which is better than naming a version here that goes stale.
        public var defaultModel: String {
            switch self {
                case .codex: ""
                case .claude: "sonnet"
            }
        }
    }

    public let tool: Tool
    /// The full path to the tool, found once when the provider was set up.
    public let executable: String
    public let model: String
    private let runner: any AssistantProcessRunner
    private let workspace: any AssistantScratchSpace

    public init(
        tool: Tool,
        executable: String,
        model: String,
        runner: any AssistantProcessRunner = AssistantProcessLauncher(),
        workspace: any AssistantScratchSpace = AssistantTemporaryDirectory()
    ) {
        self.tool = tool
        self.executable = executable
        self.model = model
        self.runner = runner
        self.workspace = workspace
    }

    public var identity: AssistantProviderIdentity { tool.identity }
    public var capabilities: AssistantCapabilities { tool.capabilities }

    /// Whether the tool is installed, and where.
    public static func locate(_ tool: Tool) -> String? {
        AssistantToolLocator.locate(tool.command)
    }

    // MARK: - Running

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var scratch: AssistantScratchFiles?
                do {
                    let files = try workspace.makeFiles(for: request, capabilities: capabilities)
                    scratch = files
                    let invocation = Self.invocation(
                        tool: tool,
                        executable: executable,
                        model: model,
                        request: request,
                        files: files
                    )
                    continuation.yield(.note("\(tool.command) is working"))

                    var diagnostics = ""
                    for try await event in runner.run(invocation) {
                        try Task.checkCancellation()
                        switch event {
                            case .output(let data):
                                if let text = String(data: data, encoding: .utf8) {
                                    continuation.yield(.text(text))
                                }
                            case .diagnostic(let text):
                                diagnostics += text
                            case .finished(let status):
                                guard status == 0 else {
                                    throw Self.failure(tool: tool, status: status, diagnostics: diagnostics)
                                }
                        }
                    }
                    if let scratch { workspace.discard(scratch) }
                    continuation.finish()
                } catch {
                    if let scratch { workspace.discard(scratch) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The command to run. Pure, so every flag is covered by a test rather than discovered when a
    /// person's request fails.
    static func invocation(
        tool: Tool,
        executable: String,
        model: String,
        request: AssistantRequest,
        files: AssistantScratchFiles
    ) -> AssistantProcessInvocation {
        var arguments: [String]
        switch tool {
            case .codex:
                arguments = [
                    "exec",
                    // Nothing this asks for needs the file system or the shell, so the sandbox is
                    // closed and the tool is kept away from anything it might decide to change.
                    "--sandbox", "read-only",
                    // The playground is not a project, and codex otherwise refuses to run outside a
                    // repository.
                    "--skip-git-repo-check",
                    // No session file is left behind for a request about someone's window chrome.
                    "--ephemeral",
                    "--color", "never",
                ]
                if let schema = files.schema {
                    arguments += ["--output-schema", schema.path]
                }
                if !model.isEmpty {
                    arguments += ["--model", model]
                }
                for image in files.images {
                    arguments += ["--image", image.path]
                }
                // A bare dash tells codex the prompt is on standard input.
                arguments.append("-")
            case .claude:
                arguments = [
                    "--print",
                    "--output-format", "text",
                    // Answering this needs no tools at all, so the ones that run code are gone and
                    // the ones that touch files are denied.
                    "--restricted",
                    "--disallowedTools", "Read,Edit,Write,WebFetch,WebSearch",
                    "--no-session-persistence",
                ]
                if !model.isEmpty {
                    arguments += ["--model", model]
                }
        }

        return AssistantProcessInvocation(
            executable: executable,
            arguments: arguments,
            standardInput: Data(prompt(for: request, tool: tool).utf8),
            workingDirectory: files.directory
        )
    }

    /// The whole request as one piece of text, since neither tool takes a conversation.
    static func prompt(for request: AssistantRequest, tool: Tool) -> String {
        // With a schema file, the shape of the answer is already settled and only needs pointing at.
        let note =
            tool.capabilities.enforcesSchema
            ? "Answer with the JSON object described by the output schema, and nothing else." : nil
        return AssistantPrompt.flattened(request, adding: note)
    }

    /// What a non-zero exit means. A tool that has lost its sign-in is the one failure a person has
    /// to act on rather than retry, so it is told apart from the rest by what it printed.
    static func failure(tool: Tool, status: Int32, diagnostics: String) -> AssistantProviderError {
        let detail = lastMeaningfulLine(of: diagnostics)
        let lowercased = diagnostics.lowercased()
        let signInWords = ["not logged in", "unauthorized", "authentication", "please log in", "please login", "401"]
        if signInWords.contains(where: lowercased.contains) {
            return .notAuthorized(provider: tool.command, detail: detail.isEmpty ? nil : detail)
        }
        let limitWords = ["rate limit", "usage limit", "too many requests", "429", "quota"]
        if limitWords.contains(where: lowercased.contains) {
            return .rateLimited(provider: tool.command, retryAfter: nil)
        }
        return .toolFailed(command: tool.command, status: status, detail: detail)
    }

    /// The last line worth showing from a tool's diagnostics, which are usually progress noise with
    /// the real complaint at the end.
    static func lastMeaningfulLine(of diagnostics: String) -> String {
        let lines =
            diagnostics
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? ""
    }
}
