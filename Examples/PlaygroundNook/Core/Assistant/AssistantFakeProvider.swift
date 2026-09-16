// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// A provider that answers from a script instead of a model.
///
/// It ships in the module rather than in the tests because it has two jobs. It is how streaming,
/// cancellation, the repair round, and the capability gate are tested without a network. It is also
/// what the playground uses when `OPENNOOK_ASSISTANT_FAKE` is set, so every state of the composer can
/// be reached, screenshotted, and driven over accessibility without calling a real model or spending
/// anyone's tokens.
public struct AssistantFakeProvider: AssistantProvider, Sendable {
    /// What the fake does when it is asked.
    public enum Script: Sendable {
        /// One answer per attempt. The first is used for the first call, the second for a repair, and
        /// the last one repeats if it is asked again.
        case answers([String])
        case fails(AssistantProviderError)
        /// Never answers, so cancellation has something to cancel.
        case waits
    }

    public let identity: AssistantProviderIdentity
    public let capabilities: AssistantCapabilities
    public let script: Script
    /// How many characters arrive at a time, so a test can watch an answer build up.
    public let chunk: Int
    /// How long between chunks. Zero in tests; a little in the app, so the streaming can be seen.
    public let pace: Duration
    private let log: Log

    public init(
        identity: AssistantProviderIdentity = .fake,
        capabilities: AssistantCapabilities = .fake,
        script: Script,
        chunk: Int = 32,
        pace: Duration = .zero
    ) {
        self.identity = identity
        self.capabilities = capabilities
        self.script = script
        self.chunk = chunk
        self.pace = pace
        self.log = Log()
    }

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let attempt = await log.record(request)
                switch script {
                    case .fails(let error):
                        continuation.finish(throwing: error)
                    case .waits:
                        // Sleeps in short hops so cancellation is noticed promptly.
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(20))
                        }
                        continuation.finish()
                    case .answers(let answers):
                        guard !answers.isEmpty else { return continuation.finish() }
                        let answer = answers[min(attempt, answers.count - 1)]
                        continuation.yield(.note("\(identity.name) is thinking"))
                        for piece in Self.pieces(of: answer, every: chunk) {
                            if Task.isCancelled { break }
                            if pace > .zero {
                                try? await Task.sleep(for: pace)
                            }
                            continuation.yield(.text(piece))
                        }
                        continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every request the fake has been given, in order, so a test can assert on what a provider
    /// would have been sent.
    public var requests: [AssistantRequest] {
        get async { await log.requests }
    }

    static func pieces(of text: String, every size: Int) -> [String] {
        guard size > 0 else { return [text] }
        var pieces: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            pieces.append(String(text[index..<end]))
            index = end
        }
        return pieces
    }

    /// The attempt counter and the record of requests. An actor because a provider is `Sendable` and
    /// may be called from any task.
    private actor Log {
        private(set) var requests: [AssistantRequest] = []

        /// Records `request` and returns which attempt it is, counting from zero.
        func record(_ request: AssistantRequest) -> Int {
            requests.append(request)
            return requests.count - 1
        }
    }
}

extension AssistantProviderIdentity {
    public static let fake = AssistantProviderIdentity(
        id: "fake",
        name: "Example",
        summary: "A scripted provider, for screenshots and tests"
    )
}

extension AssistantCapabilities {
    /// Everything on, so a test has to turn a capability off deliberately to test the gate.
    public static let fake = AssistantCapabilities(
        acceptsImages: true,
        enforcesSchema: true,
        needsAPIKey: false,
        usesNetwork: false
    )

    /// A provider that cannot see images, for the capability gate.
    public static let fakeWithoutImages = AssistantCapabilities(
        acceptsImages: false,
        imageLimit: "Example cannot see images.",
        enforcesSchema: true,
        needsAPIKey: false,
        usesNetwork: false
    )
}

// MARK: - Scripted answers

extension AssistantFakeProvider {
    /// A well-formed answer, for the happy path and for the app's scripted mode.
    public static func answer(
        explanation: String,
        notReproduced: [String] = [],
        patch: String
    ) -> String {
        let notReproducedText = notReproduced.map { AssistantJSON.quoted($0) }.joined(separator: ", ")
        return """
            {
              "explanation": \(AssistantJSON.quoted(explanation)),
              "notReproduced": [\(notReproducedText)],
              "patch": \(patch)
            }
            """
    }

    /// What the playground's scripted mode answers with: a dark, narrow media player with the lock
    /// and gear moved into a round companion.
    public static let mediaPlayerAnswer = answer(
        explanation: "Going dark and narrow, with the lock and gear moved out of the top bar into a "
            + "round companion on the trailing edge.",
        notReproduced: ["the album art grid", "the scrubbing bar"],
        patch: """
            {
                "appearance": { "chromePalette": "dark" },
                "settings": {
                  "panel": { "expandedWidth": 420 },
                  "topBar": {
                    "leadingTitle": "Music",
                    "leadingIcon": "music.note",
                    "showsKeepOpenButton": false,
                    "showsSettingsButton": false
                  },
                  "companions": [
                    { "id": "sleep-timer", "kind": "button", "outline": "circle", "anchor": "trailing", "spacing": 10,
                      "accessibilityLabel": "Sleep timer" },
                    { "id": "controls", "kind": "controls", "anchor": "trailing", "spacing": 10,
                      "hidesInSettings": false, "accessibilityLabel": "Nook controls" }
                  ]
                }
            }
            """
    )
}
