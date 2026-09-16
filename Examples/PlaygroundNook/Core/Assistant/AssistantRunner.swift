// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Glendon Chin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// A copy is included at /LICENSE in the repository root.

import Foundation

/// What a run has to report as it goes.
public enum AssistantOutcome: Sendable, Equatable {
    /// Progress that is not part of the answer, such as a tool starting up.
    case note(String)
    /// The explanation as far as it has arrived. Each one replaces the last.
    case explanation(String)
    /// The first answer could not be used and is being sent back once for correction. The reason is
    /// worth showing quietly, because a run that takes twice as long should say why.
    case repairing(reason: String)
    case proposal(AssistantProposal)
}

/// Runs one request through a provider and turns its stream of text into a proposal.
///
/// This is where the repair round lives. A model that answers with a field that does not exist, or
/// with prose instead of JSON, gets exactly one correction, carrying the specific complaint from
/// ``AssistantPatchError`` or ``AssistantResponseError`` rather than a restatement of the rules. One
/// round, because a second rarely helps and the person is waiting; if the correction also fails, the
/// original problem is what they are shown.
///
/// Nothing here touches the network or the file system. Everything provider-specific is behind
/// ``AssistantProvider``, so the whole path including streaming, cancellation, and repair is tested
/// against a fake.
public struct AssistantRunner: Sendable {
    private let provider: any AssistantProvider

    public init(provider: any AssistantProvider) {
        self.provider = provider
    }

    /// The run, as it happens. Cancelling the task consuming the stream cancels the provider.
    public func run(_ request: AssistantRequest, base: PlaygroundPreset) -> AsyncThrowingStream<
        AssistantOutcome, any Error
    > {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let answer = try await attempt(request, base: base, continuation: continuation)
                    continuation.yield(.proposal(answer))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The first attempt, and one repair if it is needed.
    private func attempt(
        _ request: AssistantRequest,
        base: PlaygroundPreset,
        continuation: AsyncThrowingStream<AssistantOutcome, any Error>.Continuation
    ) async throws -> AssistantProposal {
        let raw = try await collect(request, continuation: continuation)
        do {
            return try proposal(from: raw, base: base)
        } catch {
            guard let repair = Self.repairRequest(for: error) else { throw error }
            try Task.checkCancellation()

            continuation.yield(.repairing(reason: Self.reason(for: error)))
            continuation.yield(.explanation(""))

            var corrected = request
            corrected.turns.append(AssistantTurn(role: .assistant, text: raw))
            corrected.turns.append(AssistantTurn(role: .person, text: repair))
            let secondRaw = try await collect(corrected, continuation: continuation)
            do {
                return try proposal(from: secondRaw, base: base)
            } catch {
                // The repair failed too. What the person sees is the first problem, which is the one
                // that describes what actually went wrong.
                throw error
            }
        }
    }

    /// Streams one call, passing the explanation on as it grows, and returns the whole answer.
    private func collect(
        _ request: AssistantRequest,
        continuation: AsyncThrowingStream<AssistantOutcome, any Error>.Continuation
    ) async throws -> String {
        var raw = ""
        var shown = ""
        for try await event in provider.stream(request) {
            try Task.checkCancellation()
            switch event {
                case .note(let note):
                    continuation.yield(.note(note))
                case .text(let delta):
                    raw += delta
                    // Only the explanation is shown while the answer arrives; the patch that follows
                    // it becomes the proposal card instead.
                    if let found = AssistantResponseScanner.explanation(in: raw), found.text != shown {
                        shown = found.text
                        continuation.yield(.explanation(found.text))
                    }
            }
        }
        try Task.checkCancellation()
        return raw
    }

    private func proposal(from raw: String, base: PlaygroundPreset) throws -> AssistantProposal {
        let answer = try AssistantResponseParser.parse(raw)
        return try AssistantDiff.proposal(
            base: base,
            patch: answer.patch,
            explanation: answer.explanation,
            notReproduced: answer.notReproduced
        )
    }

    /// What to send back for the one repair round, or `nil` for a failure no correction can fix,
    /// such as the network being down.
    static func repairRequest(for error: any Error) -> String? {
        switch error {
            case let error as AssistantResponseError: error.repairRequest
            case let error as AssistantPatchError: error.repairRequest
            default: nil
        }
    }

    /// The one-line reason shown while a repair is in flight.
    static func reason(for error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? "The answer could not be used."
    }
}
