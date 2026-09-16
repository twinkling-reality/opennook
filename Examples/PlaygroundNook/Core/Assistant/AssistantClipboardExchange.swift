// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// The way of asking that needs nothing installed, no key, and no network from this app: the person
/// carries the message themselves.
///
/// Copy Prompt puts the whole request on the clipboard. They paste it wherever they already have a
/// model, which might be a subscription chat window, an editor, or their own agent, and paste the
/// reply back. What comes back goes through exactly the same parser, patch merge, and diff as every
/// other provider, so the proposal card, the preview, and the undo are identical.
///
/// It is here for two reasons. It is the honest answer to "why should I pay to customize an open
/// source app", since it works with whatever someone already has and sends nothing anywhere. And it
/// is the fallback when nothing is detected on the machine, so the assistant is never a dead end.
///
/// Not an ``AssistantProvider``: there is no stream to await, because the transport is a person.
public enum AssistantClipboardExchange {
    public static let identity = AssistantProviderIdentity(
        id: "clipboard",
        name: "Clipboard",
        summary: "Copy the prompt into any chat or agent you already have, then paste the reply back."
    )

    /// Images cannot be carried on the clipboard with the text, but the colors and measurements taken
    /// from them are in the prompt, and the person can drop the same screenshot into their own chat
    /// window themselves.
    public static let capabilities = AssistantCapabilities(
        acceptsImages: false,
        imageLimit: "The prompt carries the colors measured from your screenshot, but not the image. "
            + "Drop the screenshot into your own chat window alongside the pasted prompt.",
        enforcesSchema: false,
        needsAPIKey: false,
        usesNetwork: false
    )

    /// What Copy Prompt puts on the clipboard.
    public static func prompt(for request: AssistantRequest) -> String {
        AssistantPrompt.flattened(
            request,
            adding: "Reply with only the JSON object. No code fence, no explanation around it."
        )
    }

    /// A pasted reply, read into a proposal.
    ///
    /// Lenient about the wrapping, because a chat window's reply arrives with a code fence, a "Sure,
    /// here you go" in front, and sometimes a follow-up question behind. The object inside is what
    /// matters.
    public static func proposal(from pasted: String, base: PlaygroundPreset) throws -> AssistantProposal {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AssistantClipboardError.nothingToRead
        }
        let answer = try AssistantResponseParser.parse(trimmed)
        return try AssistantDiff.proposal(
            base: base,
            patch: answer.patch,
            explanation: answer.explanation,
            notReproduced: answer.notReproduced
        )
    }

    /// What to copy back when the reply could not be used.
    ///
    /// The repair round cannot be automatic here, since the person is the transport. They get the same
    /// specific complaint the other providers send themselves, as one line to paste into the same
    /// chat, rather than being told to start again.
    public static func correction(for error: any Error) -> String? {
        AssistantRunner.repairRequest(for: error)
    }
}

/// Why a pasted reply could not be read at all.
public enum AssistantClipboardError: Error, Equatable, LocalizedError {
    case nothingToRead

    public var errorDescription: String? {
        switch self {
            case .nothingToRead:
                "There is no text on the clipboard to read a reply from."
        }
    }
}
