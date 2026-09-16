// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// The turns so far, and how they become a request.
///
/// A follow-up such as "a bit rounder" only means anything with the turn before it, so the history
/// travels with each request. The providers are all stateless, so that means re-sending it, which is
/// why the history is trimmed to the last few turns and why the current settings ride on the newest
/// turn rather than the oldest: by the time someone asks for "a bit rounder" they may have applied,
/// undone, or hand-edited the last proposal, and the state at the moment of asking is the only one
/// worth sending.
public struct AssistantConversation: Sendable, Equatable {
    /// How many turns are remembered. Six is three exchanges, which covers "make it dark", "softer",
    /// "actually a bit narrower" without the request growing without bound.
    public static let rememberedTurns = 6

    public private(set) var turns: [AssistantTurn] = []

    public init() {}

    public var isEmpty: Bool { turns.isEmpty }

    /// The attachments still in play, which are the ones on the most recent person turn that had
    /// any. They stay in play across follow-ups so "closer to the screenshot" works without the
    /// screenshot being attached again.
    public var attachments: [AssistantAttachment] {
        turns.last { $0.role == .person && !$0.attachments.isEmpty }?.attachments ?? []
    }

    public mutating func add(_ turn: AssistantTurn) {
        turns.append(turn)
        if turns.count > Self.rememberedTurns {
            turns.removeFirst(turns.count - Self.rememberedTurns)
        }
    }

    public mutating func clear() {
        turns = []
    }

    /// The request for the newest turn, with the history behind it.
    ///
    /// - Parameters:
    ///   - preset: the settings as they are right now, which the model is asked to change.
    ///   - model: the model name to ask for.
    ///   - capabilities: what the chosen provider can do. Images are described in words either way
    ///     and only attached when the provider can see them.
    public func request(
        preset: PlaygroundPreset,
        model: String,
        capabilities: AssistantCapabilities
    ) throws -> AssistantRequest {
        let sendsImages = capabilities.acceptsImages
        var rendered: [AssistantTurn] = []
        let lastPersonIndex = turns.lastIndex { $0.role == .person }

        for (index, turn) in turns.enumerated() {
            switch turn.role {
                case .assistant:
                    rendered.append(turn)
                case .person:
                    var text = AssistantPrompt.personTurn(turn, sendsImages: sendsImages)
                    if index == lastPersonIndex {
                        text += "\n\n" + (try AssistantPrompt.currentState(preset))
                    }
                    rendered.append(
                        AssistantTurn(
                            id: turn.id,
                            role: .person,
                            text: text,
                            // Only the newest turn carries its pixels. Sending every image of every
                            // turn again would multiply the cost of a long conversation for no gain,
                            // since the newest turn already carries the references still in play.
                            attachments: index == lastPersonIndex ? turn.attachments : []
                        )
                    )
            }
        }

        return AssistantRequest(
            systemPrompt: AssistantPrompt.systemPrompt(capabilities: capabilities),
            turns: rendered,
            model: model,
            sendsImages: sendsImages
        )
    }
}
